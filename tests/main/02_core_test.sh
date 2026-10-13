#!/bin/ash
#
# 2. Core: the helpers in mods/core/libmod.sh, on their own.
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

meta_file() {  # meta_file <dir> <meta>: write <dir>/meta (\n separates lines)
    mkdir -p "$1"
    printf '%b' "$2" >"$1/meta"
}

problem_with() {  # problem_with <meta>: what meta_problem says about it
    meta_file "$WORLD/p" "$1"
    meta_problem "$WORLD/p"
}

test_webos_version_is_read_from_os_info() {
    printf '{\n    "core_os_name": "Rockhopper",\n    "core_os_release": "6.5.3-47",\n    "core_os_release_codename": "kisscurl-koli",\n}\n' >"$WORLD/os_info.json"
    assertEquals "build suffix dropped, codename ignored" 6.5.3 "$(_os_info_release "$WORLD/os_info.json")"
    assertEquals "missing file" "" "$(_os_info_release "$WORLD/none.json")"
}

test_webos_version_can_be_overridden() {
    assertEquals 7.1.0 "$(MODS_WEBOS=7.1.0 webos_version)"
    assertEquals "unknown means unreadable" "" "$(MODS_WEBOS=unknown webos_version)"
}

test_webos_version_falls_back_to_nyx_cmd() {
    # a real TV's os_info.json answers before nyx-cmd is asked, so this only runs elsewhere
    if [ -f /var/run/nyx/os_info.json ]; then skip_test; return; fi
    assertEquals "neither source" "" "$(MODS_WEBOS='' webos_version)"
    mkdir -p "$WORLD/bin"
    printf '#!/bin/ash\necho 6.5.3-47\n' >"$WORLD/bin/nyx-cmd"
    chmod 755 "$WORLD/bin/nyx-cmd"
    assertEquals "build suffix dropped" 6.5.3 "$(PATH="$WORLD/bin:$PATH" MODS_WEBOS='' webos_version)"
    printf '#!/bin/ash\nexit 1\n' >"$WORLD/bin/nyx-cmd"
    assertEquals "nyx-cmd fails" "" "$(PATH="$WORLD/bin:$PATH" MODS_WEBOS='' webos_version)"
}

test_webos_version_on_this_tv() {
    if [ ! -f /var/run/nyx/os_info.json ]; then skip_test; return; fi
    local version=''
    version=$(MODS_WEBOS='' webos_version)
    assertNotNull "nothing read from /var/run/nyx/os_info.json" "$version"
    _version_ok "$version"
    assertTrue "'$version' isn't a dotted version" $?
}

test_meta_reads_values() {
    meta_file "$WORLD/m" 'version=1.2.3\nengines.webos=>=4.5 <8\n'
    assertEquals 1.2.3 "$(meta "$WORLD/m" version)"
    assertEquals "values keep their spaces" ">=4.5 <8" "$(meta "$WORLD/m" 'engines\.webos')"
    assertEquals "missing key" "" "$(meta "$WORLD/m" boot_order)"
    assertEquals "missing meta file" "" "$(meta "$WORLD/none" version)"
}

test_every_mod_but_core_depends_on_core() {
    meta_file "$WORLD/a" 'version=1.0.0\n'
    meta_file "$WORLD/b" 'version=1.0.0\ndependencies.x=^1\ndependencies.core=^1.2.0\n'
    meta_file "$WORLD/core" 'version=1.0.0\n'
    assertEquals "no dependencies declared" "core" "$(dep_names "$WORLD/a" | words)"
    assertEquals "declared core isn't listed twice" "x core" "$(dep_names "$WORLD/b" | words)"
    assertEquals "core itself" "" "$(dep_names "$WORLD/core" | words)"
}

test_dependency_ranges() {
    meta_file "$WORLD/a" 'version=1.0.0\ndependencies.x=>=1.2 <2\n'
    assertEquals ">=1.2 <2" "$(dep_range "$WORLD/a" x)"
    assertEquals "implied core accepts any version" "" "$(dep_range "$WORLD/a" core)"
}

test_dep_order_puts_dependencies_first() {
    meta_file "$WORLD/m/a" 'version=1.0.0\ndependencies.b=\n'
    meta_file "$WORLD/m/b" 'version=1.0.0\ndependencies.c=\n'
    meta_file "$WORLD/m/c" 'version=1.0.0\nboot_order=90\n'
    meta_file "$WORLD/m/d" 'version=1.0.0\nboot_order=10\n'
    assertEquals "a chain, then the rest by name; boot_order plays no part" "c b a d" \
        "$(dep_order "$WORLD/m" d a c b | words)"
    meta_file "$WORLD/m/e" 'version=1.0.0\ndependencies.a=\ndependencies.d=\n'
    assertEquals "after everything it depends on" "c b a d e" "$(dep_order "$WORLD/m" e d c b a | words)"
    assertEquals "only the mods named" "b a" "$(dep_order "$WORLD/m" a b | words)"
    assertEquals "a dependency not named doesn't wait" "a" "$(dep_order "$WORLD/m" a)"
    meta_file "$WORLD/m/f" 'version=1.0.0\ndependencies.g=\n'
    meta_file "$WORLD/m/g" 'version=1.0.0\ndependencies.z=\n'
    assertEquals "nor does it hold back what depends on it" "g f" "$(dep_order "$WORLD/m" f g | words)"
}

test_dep_order_puts_a_cycle_together_by_name() {
    meta_file "$WORLD/m/a" 'version=1.0.0\ndependencies.b=\n'
    meta_file "$WORLD/m/b" 'version=1.0.0\ndependencies.c=\n'
    meta_file "$WORLD/m/c" 'version=1.0.0\ndependencies.b=\ndependencies.d=\n'
    meta_file "$WORLD/m/d" 'version=1.0.0\n'
    assertEquals "one line per group: after what it needs, before what needs it" "d
b c
a" "$(dep_order "$WORLD/m" a b c d)"
    meta_file "$WORLD/m/s" 'version=1.0.0\ndependencies.s=\n'
    assertEquals "a mod that depends on itself" "s" "$(dep_order "$WORLD/m" s)"
}

test_boot_order_defaults_to_50() {
    meta_file "$WORLD/a" 'version=1.0.0\n'
    meta_file "$WORLD/b" 'version=1.0.0\nboot_order=07\n'
    assertEquals 50 "$(boot_order "$WORLD/a")"
    assertEquals 07 "$(boot_order "$WORLD/b")"
}

test_webos_ok() {
    meta_file "$WORLD/plain" 'version=1.0.0\n'
    meta_file "$WORLD/ranged" 'version=1.0.0\nengines.webos=6.x\n'
    webos_ok "$WORLD/plain" 7.1.0
    assertTrue "no range: any webOS" $?
    webos_ok "$WORLD/ranged" 6.5.3
    assertTrue "inside the range" $?
    webos_ok "$WORLD/ranged" 7.1.0
    assertFalse "outside the range" $?
    webos_ok "$WORLD/ranged" ""
    assertTrue "unknown version counts as inside" $?
}

test_valid_meta_has_no_problem() {
    assertEquals "" "$(problem_with 'version=1.2.3\nboot_order=60\ndependencies.core=^1.0.0\ndependencies.foo-bar_2=>=1.2 <2 || ^3\nengines.webos=>=4.5 <8\n')"
}

test_meta_needs_a_plain_version() {
    local version=''
    assertContains "missing" "$(problem_with 'boot_order=50\n')" "version="
    for version in 1.2 1.2.3.4 01.2.3 1.2.3-beta v1.2.3 1.x; do
        assertContains "version=$version" "$(problem_with "version=$version\n")" "version="
    done
}

test_boot_order_must_be_two_digits() {
    local order=''
    for order in 5 100 ab; do
        assertContains "boot_order=$order" "$(problem_with "version=1.0.0\nboot_order=$order\n")" "boot_order"
    done
}

test_dependency_names_are_checked() {
    local line=''
    for line in 'dependencies.foo bar=1' 'dependencies.=1' 'dependencies.foo.bar=1'; do
        assertContains "$line" "$(problem_with "version=1.0.0\n$line\n")" "dependency names"
    done
}

test_ranges_in_meta_are_checked() {
    assertContains "$(problem_with 'version=1.0.0\ndependencies.b=>=one\n')" "dependencies.b"
    assertContains "$(problem_with 'version=1.0.0\nengines.webos=>=six\n')" "engines.webos"
}

test_more_meta_fields_are_checked() {
    assertContains "keywords" "$(problem_with 'version=1.0.0\nkeywords=a b\n')" \
        "keywords must be words separated by commas"
    assertContains "an empty keyword" "$(problem_with 'version=1.0.0\nkeywords=a,,b\n')" "keywords must be"
    assertEquals "good keywords" "" "$(problem_with 'version=1.0.0\nkeywords=dns,ad-block\n')"
    assertContains "homepage" "$(problem_with 'version=1.0.0\nhomepage=http://x.org\n')" \
        "homepage must be an https:// URL"
    assertContains "license" "$(problem_with 'version=1.0.0\nlicense=MIT; rm\n')" \
        "license must be an SPDX expression"
    assertEquals "a license expression" "" \
        "$(problem_with 'version=1.0.0\nlicense=(MIT OR Apache-2.0) AND GPL-2.0-only\n')"
    assertContains "the index's keys" "$(problem_with 'version=1.0.0\nfile=x\n')" "meta can't set file"
    assertContains "CRLF" "$(problem_with 'version=1.0.0\r\n')" "Unix line endings"
}

test_publishing_needs_a_description_and_a_license() {
    meta_file "$WORLD/p" 'version=1.0.0\nlicense=MIT\n'
    assertContains "$(publish_problem "$WORLD/p")" "meta needs description="
    meta_file "$WORLD/p" 'version=1.0.0\ndescription=x\n'
    assertContains "$(publish_problem "$WORLD/p")" "meta needs license="
    meta_file "$WORLD/p" 'version=1.0.0\ndescription=x\nlicense=MIT\n'
    assertEquals "" "$(publish_problem "$WORLD/p")"
}

test_published_meta_has_known_keys_only_once_each() {
    meta_file "$WORLD/p" 'version=1.0.0\ndescription=x\nlicense=MIT\ndependency.core=^1.0.0\n'
    assertContains "a misspelt key" "$(publish_problem "$WORLD/p")" "unknown meta key: dependency.core"
    meta_file "$WORLD/p" 'version=1.0.0\ndescription=x\nlicense=MIT\nhello\n'
    assertContains "no =" "$(publish_problem "$WORLD/p")" "meta line isn't key=value or a comment: hello"
    meta_file "$WORLD/p" 'version=1.0.0\ndescription=x\nlicense=MIT\n  # indented\n'
    assertContains "a comment starts the line" "$(publish_problem "$WORLD/p")" "isn't key=value or a comment"
    meta_file "$WORLD/p" 'version=1.0.0\ndescription=x\ndescription=y\nlicense=MIT\n'
    assertContains "a key twice" "$(publish_problem "$WORLD/p")" "meta sets description more than once"
    meta_file "$WORLD/p" '# about\n\nversion=1.0.0\ndescription=x\nlicense=MIT\nkeywords=a,b\nhomepage=https://x.org\nauthor=Someone\nboot_order=60\nengines.webos=>=4.5\ndependencies.core=^1.0.0\ndependencies.b=\n'
    assertEquals "every known key, a comment and a blank line" "" "$(publish_problem "$WORLD/p")"
}

test_installed_mods_lists_folders_only() {
    mkdir -p "$WORLD/mods/a" "$WORLD/mods/b"
    : >"$WORLD/mods/boot.log"
    assertEquals "a b" "$(installed_mods "$WORLD/mods" | words)"
    assertEquals "no mods dir" "" "$(installed_mods "$WORLD/none" | words)"
}

test_run_boot_logs_and_reports_the_outcome() {
    meta_file "$WORLD/mods/ok" 'version=1.0.0\n'
    echo 'echo hello' >"$WORLD/mods/ok/boot"
    meta_file "$WORLD/mods/old" 'version=1.0.0\nengines.webos=<=5\n'
    echo "touch $WORLD/old-ran" >"$WORLD/mods/old/boot"
    meta_file "$WORLD/mods/bad" 'version=1.0.0\n'
    echo 'echo oops; exit 3' >"$WORLD/mods/bad/boot"
    (MODS_WEBOS=6.5.3 run_boot "$WORLD/mods" ok)
    assertEquals "ran" 0 $?
    assertEquals "hello" "$(cat "$WORLD/mods/ok/boot.log")"
    (MODS_WEBOS=6.5.3 run_boot "$WORLD/mods" old)
    assertEquals "skipped" 1 $?
    assertEquals "not started: webOS 6.5.3 is outside engines.webos <=5" "$(cat "$WORLD/mods/old/boot.log")"
    assertFalse "skipped mod's boot didn't run" "[ -e '$WORLD/old-ran' ]"
    (MODS_WEBOS=unknown run_boot "$WORLD/mods" old)
    assertEquals "unknown webOS still starts" 0 $?
    (MODS_WEBOS=6.5.3 run_boot "$WORLD/mods" bad)
    assertEquals "failed" 2 $?
    assertEquals "oops
boot script failed (exit 3)" "$(cat "$WORLD/mods/bad/boot.log")"
}

test_is_mounted() {
    is_mounted /
    assertTrue "/ is a mount point" $?
    is_mounted "$WORLD"
    assertFalse "a plain directory isn't" $?
}

# shellcheck disable=SC1090
. "$SHUNIT2"
