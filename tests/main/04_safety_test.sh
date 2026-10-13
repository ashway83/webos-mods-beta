#!/bin/ash
#
# 4. Installer safety: refusing to run, the index's signature, broken or tampered
#    downloads, bad input.
#    Every failure here must leave the TV exactly as it was.
#
# Copyright (c) 2026 Andriy Sharandakov
#
# This script is licensed under the MIT License.
# See the LICENSE file for details.
#
# GitHub: https://github.com/ashway83/webos-mods
#
# shellcheck shell=dash

# shellcheck disable=SC1091
. "$(dirname "$0")/helpers.sh"

setUp() {
    new_world
    mod b 'version=1.0.0\nboot_order=40\n' "$(starts b)"
    mod a 'version=1.0.0\nboot_order=60\ndependencies.b=^1.0.0\n' "$(starts a)"
    publish
}

test_refuses_to_run_as_non_root() {
    mkdir -p "$WORLD/bin"
    printf '#!/bin/ash\necho 1000\n' >"$WORLD/bin/id"
    chmod 755 "$WORLD/bin/id"
    # shellcheck disable=SC2034 # read by installer() in helpers.sh
    TV_ENV="PATH=$WORLD/bin:$PATH"
    installer install a
    assertEquals "exit" 1 $?
    assertContains "$(output)" "must run as root"
    assertEquals "nothing installed" "" "$(installed)"
}

test_refuses_to_run_without_homebrew_channel() {
    TV_INITD=$WORLD/tv/no-hbc/init.d
    installer install a
    assertEquals "exit" 1 $?
    assertContains "$(output)" "Homebrew Channel not found"
    assertEquals "nothing installed" "" "$(installed)"
}

test_an_unpublished_command_needs_MODS_REPOSITORY() {
    env MODS_PREFIX="$WORLD/tv/mods" MODS_INITD="$TV_INITD" MODS_WEBOS="$TV_WEBOS" \
        sh "$ROOT/mods/core/bin/webos-mods" install a >"$WORLD/out" 2>&1
    assertEquals "exit" 1 $?
    assertContains "$(output)" "unpublished webos-mods: set MODS_REPOSITORY"
}

boot_id() { cat /proc/sys/kernel/random/boot_id; }
held_by() { mkdir -p "$WORLD/tv/mods/.lock"; echo "$*" >"$WORLD/tv/mods/.lock/holder"; }  # held_by <pid> <boot>

test_a_run_in_progress_holds_off_another() {
    held_by $$ "$(boot_id)"   # this test's shell: alive, and since this boot
    installer install a
    assertEquals "exit" 1 $?
    assertContains "$(output)" "another webos-mods run (pid $$) is changing $WORLD/tv/mods; try again once it's done"
    assertEquals "nothing installed" "" "$(installed)"
    assertTrue "its lock stays" "[ -f '$WORLD/tv/mods/.lock/holder' ]"
    installer list
    assertEquals "list doesn't need the lock: exit" 0 $?
    installer search
    assertEquals "nor does search: exit" 0 $?
    installer info b
    assertEquals "nor info: exit" 0 $?
}

test_a_run_just_starting_holds_off_another() {
    mkdir -p "$WORLD/tv/mods/.lock"   # taken, but not named yet
    installer install a
    assertEquals "exit" 1 $?
    assertContains "$(output)" \
        "another webos-mods run is starting on $WORLD/tv/mods; if none is, remove $WORLD/tv/mods/.lock"
}

test_the_lock_of_a_run_thats_gone_is_taken_over() {
    local gone=''
    sh -c 'exit 0' &
    gone=$!
    wait "$gone"
    held_by "$gone" "$(boot_id)"
    installer install a
    assertEquals "no such process: exit" 0 $?
    assertContains "$(output)" "taking over $WORLD/tv/mods/.lock from a webos-mods run that's gone (pid $gone)"
    assertEquals "a b core" "$(installed)"
    held_by $$ another-boot
    installer remove a
    assertEquals "from before a reboot: exit" 0 $?
    assertContains "$(output)" "taking over $WORLD/tv/mods/.lock"
}

test_a_run_leaves_no_lock_behind() {
    installer install a
    assertFalse "after a run" "[ -e '$WORLD/tv/mods/.lock' ]"
    installer install nosuchmod
    assertFalse "after a run that stopped" "[ -e '$WORLD/tv/mods/.lock' ]"
}

test_truncated_download_runs_nothing() {
    local script="$WORLD/pub/webos-mods" size='' bytes=0 ran=''
    size=$(wc -c <"$script")
    while [ "$bytes" -lt $((size - 12)) ]; do
        head -c "$bytes" "$script" | env MODS_PREFIX="$WORLD/tv/mods" \
            MODS_INITD="$TV_INITD" MODS_WEBOS="$TV_WEBOS" sh -s -- install a >/dev/null 2>&1
        if [ -e "$WORLD/tv/mods" ]; then
            ran="$ran $bytes"
            rm -rf "$WORLD/tv/mods"
        fi
        bytes=$((bytes + 256))
    done
    assertNull "cut after these many bytes, it still installed:$ran" "$ran"
}

test_invalid_mod_names_are_rejected() {
    local name=''
    for name in ../etc foo.sh 'a b'; do
        installer install "$name"
        assertEquals "'$name': exit" 1 $?
        assertContains "'$name'" "$(output)" "invalid mod name"
    done
    assertEquals "nothing installed" "" "$(installed)"
}

test_unknown_mod_stops_the_run() {
    installer install a nosuchmod
    assertEquals "exit" 1 $?
    assertContains "$(output)" "nosuchmod: no such mod in file://$WORLD/pub"
    assertEquals "nothing installed, not even a" "" "$(installed)"
}

test_missing_archive_stops_the_run() {
    rm "$WORLD/pub/b-1.0.0.tar.gz"
    installer install a
    assertEquals "exit" 1 $?
    assertContains "$(output)" "download failed: file://$WORLD/pub/b-1.0.0.tar.gz"
    assertEquals "nothing installed" "" "$(installed)"
}

test_an_unreachable_repository_stops_the_run() {
    # shellcheck disable=SC2034 # read by installer() in helpers.sh
    TV_REPOSITORY=https://127.0.0.1:9
    installer install a
    assertEquals "exit" 1 $?
    assertContains "$(output)" "couldn't read https://127.0.0.1:9/index"
}

test_the_repository_must_be_https_or_file() {
    # shellcheck disable=SC2034 # read by installer() in helpers.sh
    TV_REPOSITORY=http://127.0.0.1:9
    installer install a
    assertEquals "exit" 1 $?
    assertContains "$(output)" "the repository URL must start with https:// or file://: http://127.0.0.1:9"
    # shellcheck disable=SC2034 # read by installer() in helpers.sh
    TV_REPOSITORY="file://$WORLD/p*b"
    installer install a
    assertEquals "a glob character: exit" 1 $?
    assertContains "$(output)" "the repository URL may only hold letters, digits and . _ ~ : / % + @ -: file://$WORLD/p*b"
    assertEquals "nothing installed" "" "$(installed)"
}

test_an_index_that_doesnt_match_its_signature_is_refused() {
    printf '\nname=x\nversion=1.0.0\nfile=x.tar.gz\nsha256=0\n' >>"$WORLD/pub/index"   # not signed again
    installer install a
    assertEquals "exit" 1 $?
    assertContains "$(output)" \
        "!! can't verify the signature of file://$WORLD/pub/index: it's invalid, or made with another key"
    assertEquals "nothing installed" "" "$(installed)"
    installer search
    assertEquals "search reads nothing either: exit" 1 $?
}

test_an_index_without_its_signature_is_refused() {
    rm "$WORLD/pub/index.sig"
    installer install a
    assertEquals "exit" 1 $?
    assertContains "$(output)" "can't verify the signature of file://$WORLD/pub/index: couldn't download index.sig"
    assertEquals "nothing installed" "" "$(installed)"
}

test_an_index_signed_with_another_key_is_refused() {
    openssl ecparam -name prime256v1 -genkey -noout -out "$WORLD/other.pem"
    sign_index "$WORLD/pub" "$WORLD/other.pem"
    installer install a
    assertEquals "exit" 1 $?
    assertContains "$(output)" "can't verify the signature of file://$WORLD/pub/index: it's invalid, or made with another key"
    assertEquals "nothing installed" "" "$(installed)"
}

test_one_valid_signature_is_enough() {   # as during a key change
    openssl ecparam -name prime256v1 -genkey -noout -out "$WORLD/other.pem"
    sign_index "$WORLD/pub" "$WORLD/other.pem"
    {
        echo 'not a signature'
        cat "$WORLD/pub/index.sig"
        openssl dgst -sha256 -sign "$WORLD/key.pem" "$WORLD/pub/index" | openssl base64 -A   # last, no line end
    } >"$WORLD/index.sig"
    mv "$WORLD/index.sig" "$WORLD/pub/index.sig"
    installer install a
    assertEquals "exit: $(output)" 0 $?
    assertEquals "a b core" "$(installed)"
}

test_a_command_trusting_two_keys_takes_a_signature_by_either() {   # as during a key change
    openssl ecparam -name prime256v1 -genkey -noout -out "$WORLD/new.pem"
    openssl pkey -in "$WORLD/new.pem" -pubout >>"$WORLD/trusted.pem"
    core_at 1.1.0
    publish   # core 1.1.0's command trusts both keys
    sign_index "$WORLD/pub" "$WORLD/new.pem"
    installer install a
    assertEquals "exit: $(output)" 0 $?
    assertEquals "with that command's core" 1.1.0 "$(version_of core)"
}

path_without() {  # path_without <command>: $WORLD/path, with links to every command on PATH
                  # but that one, for a PATH that lacks it
    local dir='' file=''
    mkdir -p "$WORLD/path"
    for dir in $(echo "$PATH" | tr ':' ' '); do
        for file in "$dir"/*; do
            if [ -x "$file" ] && [ "${file##*/}" != "$1" ] && [ ! -e "$WORLD/path/${file##*/}" ]; then
                ln -s "$file" "$WORLD/path/${file##*/}"
            fi
        done
    done
}

test_without_openssl_nothing_is_read() {
    path_without openssl
    # shellcheck disable=SC2034 # read by installer() in helpers.sh
    TV_ENV="PATH=$WORLD/path"
    installer install a
    assertEquals "exit" 1 $?
    assertContains "$(output)" "can't verify the signature of file://$WORLD/pub/index: openssl not found"
    assertEquals "nothing installed" "" "$(installed)"
}

test_a_relative_MODS_PREFIX_is_rejected() {
    # shellcheck disable=SC2034 # read by installer() in helpers.sh
    TV_ENV=MODS_PREFIX=mods
    (cd "$WORLD" && installer install a)
    assertEquals "exit" 1 $?
    assertContains "$(output)" "MODS_PREFIX must be an absolute path: mods"
    assertFalse "nothing installed there" "[ -e '$WORLD/mods' ]"
}

test_checksum_mismatch_keeps_the_installed_copy() {
    installer install a
    mod b 'version=1.1.0\nboot_order=40\n' "$(starts b)"
    publish
    echo tampered >"$WORLD/pub/b-1.1.0.tar.gz"   # the signed index keeps its sha256
    installer update
    assertEquals "exit" 1 $?
    assertContains "$(output)" "b 1.1.0: checksum mismatch (file://$WORLD/pub/b-1.1.0.tar.gz)"
    assertEquals "b kept" 1.0.0 "$(version_of b)"
}

test_an_archive_of_another_version_than_its_index_says_is_rejected() {
    installer install a
    mod b 'version=1.1.0\nboot_order=40\n' "$(starts b)"
    publish
    mkdir -p "$WORLD/wrong/b"
    printf 'version=1.2.0\n' >"$WORLD/wrong/b/meta"
    tar -cf - -C "$WORLD/wrong" b | gzip >"$WORLD/pub/b-1.1.0.tar.gz"
    rehash b-1.1.0.tar.gz
    installer update
    assertEquals "exit" 1 $?
    assertContains "$(output)" "b: file://$WORLD/pub/b-1.1.0.tar.gz holds version 1.2.0, its index says 1.1.0"
    assertEquals "b kept" 1.0.0 "$(version_of b)"
}

test_an_index_pointing_outside_the_repository_is_rejected() {
    sed 's|^file=b-1\.0\.0\.tar\.gz$|file=../../etc/passwd|' "$WORLD/pub/index" >"$WORLD/index"
    mv "$WORLD/index" "$WORLD/pub/index"
    sign_index "$WORLD/pub"   # as a bad build would: the check doesn't rely on the signature
    installer install a
    assertEquals "exit" 1 $?
    assertContains "$(output)" "b 1.0.0: file://$WORLD/pub lists it as '../../etc/passwd', not a file name"
    assertEquals "nothing installed" "" "$(installed)"
}

test_a_repository_without_this_core_stops_the_run() {
    rm "$WORLD/pub/core-1.0.0.tar.gz"
    write_index "$WORLD/pub"
    installer install a
    assertEquals "exit" 1 $?
    assertContains "$(output)" "core 1.0.0 isn't in file://$WORLD/pub"
    assertEquals "nothing installed" "" "$(installed)"
}

test_an_index_of_another_format_is_refused() {
    sed '1s/.*/format=2/' "$WORLD/pub/index" >"$WORLD/index" && mv "$WORLD/index" "$WORLD/pub/index"
    sign_index "$WORLD/pub"
    installer install a
    assertEquals "exit" 1 $?
    assertContains "$(output)" "file://$WORLD/pub uses index format 2; update webos-mods"
    echo '<html>' >"$WORLD/pub/index"
    sign_index "$WORLD/pub"
    installer install a
    assertEquals "not an index: exit" 1 $?
    assertContains "$(output)" "file://$WORLD/pub/index isn't a webos-mods index"
    assertEquals "nothing installed" "" "$(installed)"
}

test_invalid_stanzas_are_left_out() {
    printf '\nname=../evil\nversion=1.0.0\nfile=x.tar.gz\nsha256=0\n' >>"$WORLD/pub/index"
    printf '\nname=c\nversion=1.0.0\ndependencies.../x=*\nfile=x.tar.gz\nsha256=0\n' >>"$WORLD/pub/index"
    sign_index "$WORLD/pub"
    installer install a
    assertEquals "exit" 0 $?
    assertContains "$(output)" "leaving out a stanza with an invalid name, version or dependency (../evil 1.0.0)"
    assertContains "$(output)" "leaving out a stanza with an invalid name, version or dependency (c 1.0.0)"
    assertEquals "the rest goes in" "a b core" "$(installed)"
}

test_archive_without_its_folder_is_rejected() {
    mkdir -p "$WORLD/wrong/elsewhere"
    echo 'version=1.0.0' >"$WORLD/wrong/elsewhere/meta"
    tar -cf - -C "$WORLD/wrong" elsewhere | gzip >"$WORLD/pub/b-1.0.0.tar.gz"
    rehash b-1.0.0.tar.gz
    installer install a
    assertEquals "exit" 1 $?
    assertContains "$(output)" "b: its archive holds elsewhere, outside b/"
    assertEquals "nothing installed" "" "$(installed)"
}

ustar_entry() {  # ustar_entry <archive> <type: 0 file, 2 symlink, 5 folder, 6 fifo> <name> [<link>]:
                 # append an empty entry to an uncompressed tar archive, as only a crafted
                 # archive holds what these tests need
    local header="$1.header" sum='' mode=420
    if [ "$2" = 5 ]; then mode=493; fi
    {
        printf '%s' "$3"; head -c $((100 - ${#3})) /dev/zero
        printf '%07o\000%07o\000%07o\000%011o\000%011o\000' "$mode" 0 0 0 0
        printf '        %s' "$2"
        printf '%s' "${4:-}"; head -c $((100 - ${#4})) /dev/zero
        printf 'ustar'; printf '\000'; printf '00'
        head -c 247 /dev/zero
    } >"$header"
    sum=$(od -An -tu1 -v "$header" | awk '{ for (i = 1; i <= NF; i++) s += $i } END { print s }')
    { head -c 148 "$header"; printf '%06o\000 ' "$sum"; tail -c +157 "$header"; } >>"$1"
    rm -f "$header"
}

crafted() {  # crafted <entry>...: b 1.0.0's published archive, replaced with one holding
             # b/ and b/meta, then these entries, each "<type> <name> [<link>]"
    local tar="$WORLD/crafted.tar" entry=''
    rm -f "$tar"
    ustar_entry "$tar" 5 b/
    ustar_entry "$tar" 0 b/meta
    for entry in "$@"; do
        # shellcheck disable=SC2086 # an entry's words: type, name, link
        ustar_entry "$tar" $entry
    done
    head -c 1024 /dev/zero >>"$tar"
    gzip -c "$tar" >"$WORLD/pub/b-1.0.0.tar.gz"
    rehash b-1.0.0.tar.gz
}

test_an_archive_holding_more_than_its_folder_is_rejected() {
    crafted '0 b/../x'   # GNU tar (the TV's) lists it as it is; busybox tar strips the b/../
    installer install a  # off, so it shows as x, outside b/: refused either way
    assertTrue "a dot dot: $(output)" \
        "grep -qE 'b: its archive holds (b/\.\./x, with \. or \.\. in its path|x, outside b/)' '$WORLD/out'"
    crafted '2 b/link /etc' '0 b/link/passwd'
    installer install a
    assertContains "beneath a symlink" "$(output)" "b: its archive holds b/link/passwd, beneath the symlink b/link"
    crafted '6 b/pipe'
    installer install a
    assertContains "a fifo" "$(output)" "b: its archive holds b/pipe, not a file, folder or symlink"
    crafted '0 b/boot.log'
    installer install a
    assertEquals "exit" 1 $?
    assertContains "what the TV writes" "$(output)" "b: its archive holds boot.log, which only the TV writes"
    assertEquals "nothing installed" "" "$(installed)"
}

test_an_archive_may_hold_symlinks() {
    mod s 'version=1.0.0\n'
    ln -s meta "$WORLD/repo/mods/s/link"
    publish
    installer install s
    assertEquals "exit: $(output)" 0 $?
    assertTrue "the symlink is there" "[ -L '$WORLD/tv/mods/s/link' ]"
}

test_malformed_meta_in_an_archive_stops_the_run() {
    installer install a
    mkdir -p "$WORLD/wrong/b"
    printf 'version=1.1.0\nboot_order=5x\n' >"$WORLD/wrong/b/meta"
    tar -cf - -C "$WORLD/wrong" b | gzip >"$WORLD/pub/b-1.1.0.tar.gz"
    write_index "$WORLD/pub"
    installer update
    assertEquals "exit" 1 $?
    assertContains "$(output)" "b: boot_order must be two digits"
    assertEquals "b kept" 1.0.0 "$(version_of b)"
}

# shellcheck disable=SC1090
. "$SHUNIT2"
