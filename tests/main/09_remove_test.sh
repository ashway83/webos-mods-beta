#!/bin/ash
#
# 9. Removal: what can be removed, in which order, and what's left afterwards.
#    (What uninstall scripts are told is covered in 07_scripts_test.sh.)
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

uninstalls() { echo "echo $1 >>$WORLD/uninstalled"; }   # an uninstall line that logs itself
uninstalled() { if [ -f "$WORLD/uninstalled" ]; then words <"$WORLD/uninstalled"; fi; }

setUp() {
    new_world
    mod b 'version=1.0.0\nboot_order=40\n' "$(starts b)" "$(uninstalls b)"
    mod a 'version=1.0.0\nboot_order=60\ndependencies.b=^1.0.0\n' "$(starts a)" "$(uninstalls a)"
    publish
}

test_a_mod_others_need_cant_be_removed() {
    installer install a
    installer remove b
    assertEquals "exit" 1 $?
    assertContains "$(output)" "b is needed by: a"
    assertEquals "a b core" "$(installed)"
}

test_core_cant_be_removed_while_mods_are_installed() {
    installer install a
    installer remove core
    assertEquals "exit" 1 $?
    assertContains "$(output)" "core (self) is needed by: a b"
}

test_removing_mods_together_puts_dependents_first() {
    installer install a
    installer remove b a
    assertEquals "exit" 0 $?
    assertEquals "the dependent's uninstall script first" "a b" "$(uninstalled)"
}

test_removal_follows_dependencies_not_boot_order() {
    mod early 'version=1.0.0\nboot_order=10\ndependencies.late=\n' "$(starts early)" "$(uninstalls early)"
    mod late 'version=1.0.0\nboot_order=90\n' "$(starts late)" "$(uninstalls late)"
    publish
    installer install early
    installer remove late early
    assertEquals "exit" 0 $?
    assertEquals "the dependent first" "early late" "$(uninstalled)"
}

test_removing_a_mod_that_isnt_installed() {
    installer install b
    installer remove nope
    assertEquals "exit" 0 $?
    assertContains "$(output)" "nope is not installed"
}

test_core_stays_when_the_last_mod_goes() {
    installer install b
    installer remove b
    assertNotContains "$(output)" "core removed"
    assertEquals "core" "$(installed)"
}

test_core_goes_when_named() {
    installer install b
    installer remove b core
    assertEquals "exit" 0 $?
    assertContains "$(output)" "core removed"
    assertEquals "" "$(installed)"
}

test_removal_leaves_nothing_behind() {
    installer install a
    installer remove a b core
    assertFalse "mods dir left" "[ -e '$WORLD/tv/mods' ]"
    assertEquals "hooks left" "" "$(hooks)"
    assertFalse "PATH line left" "grep -q webos-mods '$MODS_PROFILE'"
}

# shellcheck disable=SC1090
. "$SHUNIT2"
