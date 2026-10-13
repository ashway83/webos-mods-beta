#!/bin/ash
#
# 7. Mod scripts: when install and uninstall run, what they're told, and how a failing
#    install script is undone.
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

logs() { echo "echo $1 \"\$@\" >>$WORLD/scripts"; }   # a script line logging its name and arguments
script_log() { cat "$WORLD/scripts" 2>/dev/null; }

setUp() {
    new_world
    mod b 'version=1.0.0\nboot_order=40\n' "$(logs b1-boot)" "$(logs b1-uninstall)" "$(logs b1-install)"
    publish
}

test_install_runs_once_on_a_fresh_install_before_boot() {
    installer install b
    assertEquals "b1-install install
b1-boot" "$(script_log)"
    boot
    assertEquals "boot runs again, install doesn't" "b1-install install
b1-boot
b1-boot" "$(script_log)"
}

test_update_runs_the_old_uninstall_then_the_new_install() {
    installer install b
    : >"$WORLD/scripts"
    mod b 'version=1.1.0\nboot_order=40\n' "$(logs b2-boot)" "$(logs b2-uninstall)" "$(logs b2-install)"
    publish
    installer update
    assertEquals "b1-uninstall update 1.1.0
b2-install update 1.0.0
b2-boot" "$(script_log)"
}

test_removal_runs_uninstall_with_remove() {
    installer install b
    : >"$WORLD/scripts"
    installer remove b
    assertEquals "b1-uninstall remove" "$(script_log)"
}

test_scripts_can_use_the_mods_own_files() {
    mod c 'version=1.0.0\n' '' "cat \"\${0%/*}/data\" >>$WORLD/scripts" "cat \"\${0%/*}/data\" >>$WORLD/scripts"
    echo "c's data" >"$WORLD/repo/mods/c/data"
    publish
    installer install c
    installer remove c
    assertEquals "install and uninstall both read it" "c's data
c's data" "$(script_log)"
}

test_a_failing_uninstall_doesnt_block_removal() {
    mod f 'version=1.0.0\nboot_order=40\n' '' 'exit 5'
    publish
    installer install f
    installer remove f
    assertEquals "exit" 0 $?
    assertContains "a warning" "$(output)" "!! f: uninstall script failed, continuing"
    assertEquals "core" "$(installed)"
}

test_a_failing_uninstall_doesnt_block_an_update() {
    mod f 'version=1.0.0\nboot_order=40\n' '' 'exit 5'
    publish
    installer install f
    mod f 'version=1.1.0\nboot_order=40\n'
    publish
    installer update
    assertEquals "exit" 0 $?
    assertContains "a warning" "$(output)" "!! f: uninstall script failed, continuing"
    assertEquals 1.1.0 "$(version_of f)"
}

test_a_failing_install_is_undone_on_a_fresh_install() {
    mod c 'version=1.0.0\n' "$(logs c-boot)" "$(logs c-uninstall)" "$(logs c-install); exit 3"
    publish
    installer install c
    assertEquals "exit" 1 $?
    assertContains "$(output)" "c 1.0.0 not installed: its install script failed"
    assertEquals "cleaned up and never started" "c-install install
c-uninstall remove" "$(script_log)"
    assertEquals "nothing installed, not even core" "" "$(installed)"
    assertEquals "no hook" "" "$(hooks)"
}

test_a_failed_install_keeps_core_if_it_was_there_or_asked_for() {
    mod c 'version=1.0.0\n' '' '' 'exit 3'
    publish
    installer install core c
    assertEquals "asked for: exit" 1 $?
    assertEquals "asked for" "core" "$(installed)"
    installer install c
    assertEquals "already there: exit" 1 $?
    assertEquals "already there" "core" "$(installed)"
}

test_a_failing_install_on_update_puts_the_old_version_back() {
    installer install b
    : >"$WORLD/scripts"
    mod b 'version=1.1.0\nboot_order=40\n' "$(logs b2-boot)" "$(logs b2-uninstall)" "$(logs b2-install); exit 3"
    publish
    installer update
    assertEquals "exit" 1 $?
    assertContains "$(output)" "b 1.1.0 not installed: its install script failed, so 1.0.0 is back"
    assertEquals "b1-uninstall update 1.1.0
b2-install update 1.0.0
b2-uninstall update 1.0.0
b1-install update 1.1.0
b1-boot" "$(script_log)"
    assertEquals 1.0.0 "$(version_of b)"
    assertEquals "40-mod-b" "$(hooks)"
}

test_mods_needing_a_failed_install_are_skipped() {
    mod f 'version=1.0.0\nboot_order=30\n' '' '' 'exit 3'
    mod x 'version=1.0.0\nboot_order=60\ndependencies.f=^1\n' "$(logs x-boot)"
    publish
    installer install x
    assertEquals "exit" 1 $?
    assertContains "$(output)" "f 1.0.0 not installed: its install script failed"
    assertContains "$(output)" "x skipped: it needs f, which isn't available"
    assertEquals "" "$(installed)"
}

test_a_failed_restore_is_reported() {
    # shellcheck disable=SC2016 # $1 is the generated install script's argument
    mod f 'version=1.0.0\nboot_order=40\n' '' '' '[ "$1" = install ]'
    publish
    installer install f
    mod f 'version=1.1.0\nboot_order=40\n' '' '' 'exit 3'
    publish
    installer update
    assertEquals "exit" 1 $?
    assertContains "$(output)" "putting 1.0.0 back failed too; reinstall or remove f"
}

test_a_restored_version_warns_about_dependencies_it_doesnt_accept() {
    mod d 'version=1.0.0\nboot_order=30\n'
    mod x 'version=1.0.0\nboot_order=60\ndependencies.d=^1\n'
    publish
    installer install x
    mod d 'version=2.0.0\nboot_order=30\n'
    mod x 'version=1.1.0\nboot_order=60\ndependencies.d=^2\n' '' '' 'exit 3'
    publish
    installer update
    assertContains "$(output)" "x 1.0.0 may not work: it needs d@^1, and d is 2.0.0"
}

# shellcheck disable=SC1090
. "$SHUNIT2"
