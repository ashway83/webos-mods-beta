#!/bin/ash
#
# 8. Boot: what the hooks the installer wrote do when the TV starts them. Each is
#    guarded only by its mod's webOS range; problems end up in boot.log and in list.
#    (When and in which order hooks run is Homebrew Channel's business; the hook names
#    and install-time start order are covered in 05_install_test.sh.)
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
    mod x 'version=1.0.0\nboot_order=52\n' "$(starts x)"
    mod f 'version=1.0.0\nboot_order=45\nengines.webos=6.x\n' "touch $WORLD/f.ran; $(starts f)"
    mod g 'version=1.0.0\nboot_order=70\ndependencies.f=^1\n' \
        "[ -e $WORLD/f.ran ] || { echo 'f is not running' >&2; exit 3; }; $(starts g)"
    publish
}

test_a_hook_starts_its_mod() {
    installer install a x
    boot
    assertEquals "a b x" "$(started | tr ' ' '\n' | sort | words)"
}

test_boot_skips_a_mod_outside_its_webos_range() {
    installer install f
    # shellcheck disable=SC2034 # read by installer() and boot() in helpers.sh
    TV_WEBOS=7.1.0
    boot
    assertEquals "f didn't start" "" "$(started)"
    assertEquals "not started: webOS 7.1.0 is outside engines.webos 6.x" "$(boot_log f)"
}

test_boot_starts_mods_when_webos_is_unknown() {
    installer install f
    TV_WEBOS=unknown
    boot
    assertEquals "f" "$(started)"
}

test_a_failing_boot_script_is_logged() {
    mod m 'version=1.0.0\n' 'echo "cannot do it" >&2; exit 3'
    publish
    installer install m
    assertContains "$(output)" "m 1.0.0 installed, but its boot script failed"
    boot
    assertContains "$(boot_log m)" "cannot do it"
    assertContains "$(boot_log m)" "boot script failed (exit 3)"
}

test_dependents_of_a_skipped_mod_run_and_log_their_own_errors() {
    installer install g
    rm -f "$WORLD/f.ran"
    # shellcheck disable=SC2034 # read by installer() and boot() in helpers.sh
    TV_WEBOS=7.1.0
    boot
    assertContains "f skipped" "$(boot_log f)" "not started"
    assertContains "g ran without f" "$(boot_log g)" "f is not running"
}

test_list_reports_boot_problems() {
    installer install g
    rm -f "$WORLD/f.ran"
    # shellcheck disable=SC2034 # read by installer() and boot() in helpers.sh
    TV_WEBOS=7.1.0
    boot
    installer list
    grep -q '^f .*not started: needs webOS 6.x' "$WORLD/out"
    assertTrue "f's line: $(output)" $?
    grep -q '^g .*boot script failed, see ' "$WORLD/out"
    assertTrue "g's line: $(output)" $?
}

# shellcheck disable=SC1090
. "$SHUNIT2"
