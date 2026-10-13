#!/usr/bin/env bash
#
# 2. The repository builder, tools/build-repo: archives, the index, the command's
#    copies, published versions carried over, removed mods left behind, and its
#    command line.
#
# Copyright (c) 2026 Andriy Sharandakov
#
# This script is licensed under the MIT License.
# See the LICENSE file for details.
#
# GitHub: https://github.com/ashway83/webos-mods

set -u
# shellcheck disable=SC1091
. "$(dirname "$0")/helpers.sh"

publish() {  # publish [<url>]: what CI does: build-repo on top of $WORLD/pub into a fresh
             # folder, which then replaces it. Returns the script's exit status
    local st=0
    rm -rf "$WORLD/next"
    if [ -d "$WORLD/pub" ]; then set -- --from "$WORLD/pub" --url "${1-file://$WORLD/pub}"
    else set -- --url "${1-file://$WORLD/pub}"; fi
    set -- "$@" --key "$WORLD/key.pem"
    "$ROOT/tools/build-repo" "$@" "$WORLD/repo/mods" "$WORLD/next" >"$WORLD/out" 2>&1 || st=$?
    if [ "$st" = 0 ]; then rm -rf "$WORLD/pub" && mv "$WORLD/next" "$WORLD/pub"; fi
    return "$st"
}

stanza() {  # stanza <archive>: the index's stanza for that archive
    awk -v want="file=$1" '
        /^$/ { if (found) printf "%s", block; block = ""; found = 0; next }
        { block = block $0 "\n"; if ($0 == want) found = 1 }
        END { if (found) printf "%s", block }' "$WORLD/pub/index"
}

signed_by() {  # signed_by <private key> <line>: that line of index.sig is the key's signature of
               # the index
    local signature=''
    signature=$(sed -n "${2}p" "$WORLD/pub/index.sig")
    printf '%s' "$signature" | openssl base64 -d -A >"$WORLD/signature"
    openssl pkey -in "$1" -pubout >"$WORLD/public.pem"
    openssl dgst -sha256 -verify "$WORLD/public.pem" -signature "$WORLD/signature" "$WORLD/pub/index" >/dev/null
}

gnutar() { if gtar --version 2>/dev/null | grep -q 'GNU tar'; then gtar "$@"; else tar "$@"; fi; }

core_version() { sed -n 's/^version=//p' "$WORLD/repo/mods/core/meta"; }

test_a_repository_lists_every_mod_with_its_checksum() {
    mod b 'version=1.0.0\nboot_order=40\n# a comment\n\nkeywords=x,y\n'
    publish
    assert_status 0 $?
    assertEquals "first line" "format=1" "$(head -n 1 "$WORLD/pub/index")"
    assertEquals "b's stanza: meta lines, no comments or blank lines" "name=b
version=1.0.0
boot_order=40
keywords=x,y
description=Test mod b
license=MIT
file=b-1.0.0.tar.gz
sha256=$(sha256sum "$WORLD/pub/b-1.0.0.tar.gz" | cut -d' ' -f1)" "$(stanza b-1.0.0.tar.gz)"
    assertNotNull "core's stanza" "$(stanza "core-$(core_version).tar.gz")"
}

test_core_brings_its_stamped_command() {
    publish
    assertContains "$(cat "$WORLD/pub/webos-mods-$(core_version)")" "VERSION='$(core_version)'"
    mkdir "$WORLD/unpacked"
    tar -xzf "$WORLD/pub/core-$(core_version).tar.gz" -C "$WORLD/unpacked"
    assertEquals "the copy inside core" "$(cat "$WORLD/pub/webos-mods-$(core_version)")" \
        "$(cat "$WORLD/unpacked/core/bin/webos-mods")"
    assertEquals "the one-liner's copy" "$(cat "$WORLD/pub/webos-mods-$(core_version)")" \
        "$(cat "$WORLD/pub/webos-mods")"
}

test_published_versions_are_copied_not_rebuilt() {
    local first=''
    mod b 'version=1.0.0\n' 'echo b'
    publish
    first=$(sha256sum <"$WORLD/pub/b-1.0.0.tar.gz")
    mod b 'version=1.0.0\n' 'echo changed'   # changed, but with the same version
    mod c 'version=1.0.0\n'
    publish
    assert_status 0 $?
    assertContains "$(output)" "b 1.0.0 is published already"
    assertEquals "b 1.0.0 as published" "$first" "$(sha256sum <"$WORLD/pub/b-1.0.0.tar.gz")"
    assertContains "$(output)" "adding c 1.0.0"
}

test_new_versions_join_the_old_ones() {
    mod b 'version=1.0.0\n'
    publish
    mod b 'version=1.10.0\n'
    publish
    mod b 'version=1.9.0\n'
    publish
    assertContains "$(output)" "adding b 1.9.0"
    assertEquals "all listed, by name and version" \
        "b-1.0.0.tar.gz b-1.9.0.tar.gz b-1.10.0.tar.gz core-$(core_version).tar.gz" \
        "$(sed -n 's/^file=//p' "$WORLD/pub/index" | words)"
}

test_the_index_is_in_byte_order_whatever_the_locale() {   # as the TV sorts
    mod B 'version=1.0.0\n'
    mod a 'version=1.0.0\n'
    LC_ALL=en_US.UTF-8 publish
    assertEquals "B (0x42) before a (0x61)" "B-1.0.0.tar.gz a-1.0.0.tar.gz core-$(core_version).tar.gz" \
        "$(sed -n 's/^file=//p' "$WORLD/pub/index" | words)"
}

test_a_removed_mods_archives_are_left_behind() {
    mod b 'version=1.0.0\n'
    mod c 'version=1.0.0\n'
    publish
    mod c 'version=1.1.0\n'
    publish
    unmod c
    publish
    assert_status 0 $?
    assertContains "$(output)" "leaving out c: it has no folder any more"
    assertEquals "b and core stay" "b-1.0.0.tar.gz core-$(core_version).tar.gz" \
        "$(sed -n 's/^file=//p' "$WORLD/pub/index" | words)"
    assertFalse "c's archives gone" "ls '$WORLD/pub' | grep -q '^c-'"
}

test_the_one_liners_copy_follows_the_newest_core() {
    local first=''
    first=$(core_version)
    publish
    sed 's/^version=.*/version=99.0.0/' "$WORLD/repo/mods/core/meta" >"$WORLD/meta"
    mv "$WORLD/meta" "$WORLD/repo/mods/core/meta"
    publish
    assert_status 0 $?
    assertEquals "the newest core's command" "$(cat "$WORLD/pub/webos-mods-99.0.0")" "$(cat "$WORLD/pub/webos-mods")"
    assertTrue "the older one stays" "[ -f '$WORLD/pub/webos-mods-$first' ]"
}

test_the_index_is_signed() {
    publish
    assert_status 0 $?
    assertEquals "a signature" 1 "$(wc -l <"$WORLD/pub/index.sig" | tr -d ' ')"
    assertTrue "made with the key" "signed_by '$WORLD/key.pem' 1"
    mod b 'version=1.0.0\n'
    publish
    assertTrue "made afresh for the next index" "signed_by '$WORLD/key.pem' 1"
}

test_two_keys_sign_during_a_key_change() {
    openssl ecparam -name prime256v1 -genkey -noout -out "$WORLD/new.pem"
    "$ROOT/tools/build-repo" --url "file://$WORLD/pub" --key "$WORLD/key.pem" --key "$WORLD/new.pem" \
        "$WORLD/repo/mods" "$WORLD/pub" >"$WORLD/out" 2>&1
    assert_status 0 $?
    assertEquals "two signatures" 2 "$(wc -l <"$WORLD/pub/index.sig" | tr -d ' ')"
    assertTrue "the old key's" "signed_by '$WORLD/key.pem' 1"
    assertTrue "the new key's" "signed_by '$WORLD/new.pem' 2"
}

test_a_signing_key_is_required_and_checked() {
    local key=''
    "$ROOT/tools/build-repo" --url "file://$WORLD/pub" "$WORLD/repo/mods" "$WORLD/next" >"$WORLD/out" 2>&1
    assert_status 1 $? "no key"
    assertContains "$(output)" "needs a private key to sign the index with (--key)"
    "$ROOT/tools/build-repo" --url "file://$WORLD/pub" --key "$WORLD/nope.pem" "$WORLD/repo/mods" \
        "$WORLD/next" >"$WORLD/out" 2>&1
    assert_status 1 $? "no such file"
    assertContains "$(output)" "no such signing key: $WORLD/nope.pem"
    openssl pkey -in "$WORLD/key.pem" -pubout >"$WORLD/public.pem"
    openssl ecparam -name secp384r1 -genkey -noout -out "$WORLD/p384.pem"
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$WORLD/rsa.pem" 2>/dev/null
    for key in public p384 rsa; do
        "$ROOT/tools/build-repo" --url "file://$WORLD/pub" --key "$WORLD/$key.pem" "$WORLD/repo/mods" \
            "$WORLD/next" >"$WORLD/out" 2>&1
        assert_status 1 $? "$key"
        assertContains "$key" "$(output)" "the signing key must be an ECDSA P-256 private key, in PEM: $WORLD/$key.pem"
    done
    assertFalse "nothing built" "[ -e '$WORLD/next' ]"
}

test_the_repository_url_is_required_and_checked() {
    "$ROOT/tools/build-repo" "$WORLD/repo/mods" "$WORLD/next" >"$WORLD/out" 2>&1
    assert_status 1 $? "no URL"
    assertContains "$(output)" "needs the repository's URL (--url), to stamp into core's command"
    publish ''
    assert_status 1 $? "an empty one"
    assertContains "$(output)" "needs the repository's URL (--url)"
    publish http://example.org/mods
    assert_status 1 $? "http"
    assertContains "$(output)" "the repository URL must start with https:// or file://"
    publish "https://example.org/it's&more"
    assert_status 1 $? "a quote and an ampersand"
    assertContains "$(output)" "the repository URL may only hold letters, digits and . _ ~ : / % + @ -"
}

test_stamping_leaves_no_placeholder() {
    echo ": '@OTHER@'" >>"$WORLD/repo/mods/core/bin/webos-mods"   # a placeholder nothing stamps
    publish
    assert_status 1 $?
    assertContains "$(output)" "core's command still holds @OTHER@ after stamping"
    assertFalse "nothing written" "[ -e '$WORLD/next' ]"
}

test_the_output_folder_must_be_empty() {
    mkdir "$WORLD/next"
    : >"$WORLD/next/stray"
    "$ROOT/tools/build-repo" --url "file://$WORLD/pub" "$WORLD/repo/mods" "$WORLD/next" >"$WORLD/out" 2>&1
    assert_status 1 $?
    assertContains "$(output)" "the output folder must be empty"
}

test_an_output_path_thats_a_file_is_refused() {
    : >"$WORLD/next"
    "$ROOT/tools/build-repo" --url "file://$WORLD/pub" "$WORLD/repo/mods" "$WORLD/next" >"$WORLD/out" 2>&1
    assert_status 1 $?
    assertContains "$(output)" "the output path isn't a folder"
}

test_help_goes_to_stdout() {
    local word=''
    for word in help -h --help; do
        "$ROOT/tools/build-repo" "$word" >"$WORLD/out" 2>"$WORLD/err"
        assert_status 0 $? "$word"
        assertContains "$word: the usage" "$(output)" "usage: tools/build-repo [<option>...] <mods dir> <output dir>"
        assertEquals "$word: nothing on stderr" "" "$(cat "$WORLD/err")"
    done
}

test_without_its_two_folders_the_usage_goes_to_stderr() {
    "$ROOT/tools/build-repo" >"$WORLD/out" 2>"$WORLD/err"
    assert_status 1 $? "no arguments"
    assertContains "no arguments" "$(cat "$WORLD/err")" "usage: tools/build-repo"
    assertEquals "nothing on stdout" "" "$(output)"
    "$ROOT/tools/build-repo" "$WORLD/repo/mods" >"$WORLD/out" 2>"$WORLD/err"
    assert_status 1 $? "one folder"
    assertContains "one folder" "$(cat "$WORLD/err")" "usage: tools/build-repo"
}

test_unknown_options_and_missing_values_are_refused() {
    "$ROOT/tools/build-repo" --nope "$WORLD/repo/mods" "$WORLD/next" >"$WORLD/out" 2>&1
    assert_status 1 $? "unknown option"
    assertContains "$(output)" "unknown option: --nope (see tools/build-repo help)"
    "$ROOT/tools/build-repo" --url >"$WORLD/out" 2>&1
    assert_status 1 $? "no value"
    assertContains "$(output)" "--url needs a value (see tools/build-repo help)"
    "$ROOT/tools/build-repo" --url "file://$WORLD/pub" --key >"$WORLD/out" 2>&1
    assert_status 1 $? "no key file"
    assertContains "$(output)" "--key needs a value (see tools/build-repo help)"
}

test_names_with_dashes_are_listed_whole() {
    mod foo-bar 'version=1.0.0\n'
    publish
    assertContains "$(stanza foo-bar-1.0.0.tar.gz)" "name=foo-bar"
}

test_archives_are_root_owned_and_not_writable_by_others() {
    mod b 'version=1.0.0\n' 'echo b'
    chmod 666 "$WORLD/repo/mods/b/meta"
    chmod 777 "$WORLD/repo/mods/b/boot"
    publish
    gnutar -tvzf "$WORLD/pub/b-1.0.0.tar.gz" >"$WORLD/listing"
    assertTrue "owner 0/0: $(cat "$WORLD/listing")" "grep -q ' 0/0 .* b/meta$' '$WORLD/listing'"
    assertTrue "meta: rw-r--r--" "grep -q '^-rw-r--r-- .* b/meta$' '$WORLD/listing'"
    assertTrue "boot: rwxr-xr-x" "grep -q '^-rwxr-xr-x .* b/boot$' '$WORLD/listing'"
}

# shellcheck disable=SC1090
. "$SHUNIT2"
