#!/bin/ash
#
# 6. Dependencies: the two install-time checks (what a new version needs; what needs
#    it), what gets pulled in or left out, core's lockstep with the installer, and the
#    core the installed command chooses when it updates itself.
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
    publish
}

test_a_mod_waits_for_a_newer_dependency() {
    installer install b
    mod q 'version=1.0.0\nboot_order=65\ndependencies.b=^2\n' "$(starts q)"
    publish
    installer install q
    assertContains "$(output)" "q skipped: it needs b@^2, but b would be 1.0.0"
    assertEquals "b core" "$(installed)"
}

test_a_dependency_update_is_held_back_for_an_installed_mod() {
    mod p 'version=1.0.0\nboot_order=55\ndependencies.b=~1.0\n' "$(starts p)"
    publish
    installer install p
    mod b 'version=2.0.0\nboot_order=40\n' "$(starts b)"
    publish
    installer update
    assertContains "$(output)" "b 2.0.0 not installed, keeping 1.0.0: p 1.0.0 needs b@~1.0"
    assertEquals 1.0.0 "$(version_of b)"
}

test_a_held_back_dependency_still_serves_mods_that_accept_it() {
    mod p 'version=1.0.0\nboot_order=55\ndependencies.b=~1.0\n' "$(starts p)"
    mod a 'version=1.0.0\nboot_order=60\ndependencies.b=^1\n' "$(starts a)"
    publish
    installer install p a
    mod b 'version=2.0.0\nboot_order=40\n' "$(starts b)"
    mod a 'version=1.1.0\nboot_order=60\ndependencies.b=>=1 <3\n' "$(starts a)"
    publish
    installer update
    assertEquals "b held back" 1.0.0 "$(version_of b)"
    assertEquals "a updated anyway" 1.1.0 "$(version_of a)"
}

test_installing_a_mod_keeps_a_dependency_at_a_version_it_accepts() {
    installer install b
    mod b 'version=2.0.0\nboot_order=40\n' "$(starts b)"
    mod x 'version=1.0.0\ndependencies.b=^1\n'
    publish
    installer install x
    assertContains "$(output)" "b 2.0.0 not installed, keeping 1.0.0: x 1.0.0 needs b@^1"
    assertEquals "x installed" 1.0.0 "$(version_of x)"
    assertEquals "b kept" 1.0.0 "$(version_of b)"
}

test_dependencies_of_a_skipped_mod_stay_out() {
    mod q 'version=1.0.0\ndependencies.b=^2\n'
    publish
    installer install q
    assertContains "$(output)" "q skipped"
    assertEquals "neither b nor core installed" "" "$(installed)"
}

test_install_leaves_dependencies_of_an_unchanged_mod_alone() {
    mod a 'version=1.0.0\nboot_order=60\ndependencies.b=^1\n' "$(starts a)"
    publish
    installer install a
    mod b 'version=1.1.0\nboot_order=40\n' "$(starts b)"
    publish
    installer install a
    assertEquals "install a: b untouched" 1.0.0 "$(version_of b)"
    installer update
    assertEquals "update: b updated" 1.1.0 "$(version_of b)"
}

test_a_mod_needing_a_missing_dependency_is_skipped() {
    mod e 'version=1.0.0\ndependencies.ghost=*\n'
    publish
    installer install e
    assertContains "$(output)" "e skipped: it needs ghost, which isn't available"
}

test_a_dependency_outside_its_webos_range_skips_its_dependents() {
    mod c 'version=2.0.0\nengines.webos=<=5\n'
    mod d 'version=1.0.0\ndependencies.c=*\n'
    publish
    installer install d
    assertContains "$(output)" "c skipped: it needs webOS <=5, this TV has 6.5.3"
    assertContains "$(output)" "d skipped: it needs c, which isn't available"
}

test_an_installed_dependency_outside_its_webos_range_holds_back_dependents() {
    mod f 'version=1.0.0\nengines.webos=6.x\n'
    publish
    installer install f
    mod g 'version=1.0.0\ndependencies.f=^1\n'
    publish
    # shellcheck disable=SC2034 # read by installer() and boot() in helpers.sh
    TV_WEBOS=7.1.0
    installer install g
    assertContains "$(output)" "g skipped: it needs f, which isn't available"
}

test_a_dependency_dropped_from_the_repository_counts_at_its_installed_version() {
    mod lib1 'version=1.0.0\n'
    mod x 'version=1.0.0\ndependencies.lib1=^1\n'
    publish
    installer install x
    unmod lib1
    mod x 'version=1.1.0\ndependencies.lib1=^1\n'
    publish
    installer update
    assertContains "$(output)" "lib1 isn't in the repository any more; leaving it as is"
    assertEquals 1.1.0 "$(version_of x)"
}

test_a_dependency_cycle_installs_and_removes_together() {
    mod x 'version=1.0.0\nboot_order=60\ndependencies.y=*\n' "$(starts x)"
    mod y 'version=1.0.0\nboot_order=40\ndependencies.x=*\n' "$(starts y)"
    publish
    installer install x
    assertEquals "both installed" "core x y" "$(installed)"
    assertEquals "together, by name" "x y" "$(started)"
    installer remove x
    assertEquals "remove x alone: exit" 1 $?
    installer remove x y
    assertEquals "remove both: exit" 0 $?
    assertEquals "core stays" "core" "$(installed)"
}

test_a_mod_needing_a_newer_core_is_skipped() {
    mod q 'version=1.0.0\ndependencies.core=^2\n'
    publish
    installer install q
    assertContains "$(output)" "q skipped: it needs core@^2, but core would be 1.0.0"
}

test_core_capped_by_an_installed_mod_stops_the_run() {
    mod capped 'version=1.0.0\ndependencies.core=^1.0.0\n'
    publish
    installer install capped b
    sed -i 's/^version=.*/version=2.0.0/' "$WORLD/repo/mods/core/meta"
    mod b 'version=1.1.0\nboot_order=40\n' "$(starts b)"
    publish
    installer update
    assertEquals "exit" 1 $?
    assertContains "$(output)" "core 2.0.0 can't be installed, so nothing was changed: capped 1.0.0 needs core@^1.0.0"
    assertEquals "core kept" 1.0.0 "$(version_of core)"
    assertEquals "b not updated either" 1.0.0 "$(version_of b)"
}

test_core_updates_once_nothing_caps_it() {
    mod capped 'version=1.0.0\ndependencies.core=^1.0.0\n'
    publish
    installer install capped b
    sed -i 's/^version=.*/version=2.0.0/' "$WORLD/repo/mods/core/meta"
    publish
    installer remove capped
    installer update
    assertEquals "exit" 0 $?
    assertEquals 2.0.0 "$(version_of core)"
}

test_the_installed_command_takes_the_newest_core_its_mods_accept() {
    mod capped 'version=1.0.0\ndependencies.core=^1.0.0\n'
    publish
    installer install capped
    core_at 1.1.0
    publish
    core_at 2.0.0
    publish
    webos_mods install b
    assertEquals "exit: $(output)" 0 $?
    assertContains "$(output)" "core 2.0.0 not installed, 1.1.0 instead: capped 1.0.0 needs core@^1.0.0"
    assertEquals "the newest capped accepts" 1.1.0 "$(version_of core)"
    assertEquals "b installed with it" "b capped core" "$(installed)"
}

test_update_moves_core_and_the_mods_that_need_it_together() {
    mod capped 'version=1.0.0\ndependencies.core=^1.0.0\n'
    publish
    installer install capped
    core_at 2.0.0
    mod capped 'version=2.0.0\ndependencies.core=^2.0.0\n'
    publish
    webos_mods install b
    assertEquals "install: exit" 0 $?
    assertContains "install leaves capped as it is, which holds core back" "$(output)" \
        "core 2.0.0 not installed, keeping 1.0.0: capped 1.0.0 needs core@^1.0.0"
    assertEquals "core kept" 1.0.0 "$(version_of core)"
    webos_mods update
    assertEquals "update: exit: $(output)" 0 $?
    assertEquals "core" 2.0.0 "$(version_of core)"
    assertEquals "and capped with it" 2.0.0 "$(version_of capped)"
}

test_a_new_mod_doesnt_hold_the_installed_commands_core_back() {
    installer install b
    core_at 2.0.0
    mod q 'version=1.0.0\ndependencies.core=^1.0.0\n'
    publish
    webos_mods install q
    assertEquals "exit" 0 $?
    assertContains "$(output)" "q skipped: it needs core@^1.0.0, but core would be 2.0.0"
    assertEquals "core updated all the same" 2.0.0 "$(version_of core)"
}

test_updates_that_make_room_for_each_other_go_in_together() {   # one at a time, none could
    mod bar 'version=1.5.0\n'
    mod foo 'version=1.0.0\ndependencies.bar=^1\n'
    mod baz 'version=1.0.0\ndependencies.bar=^1\n'
    publish
    installer install foo baz
    mod bar 'version=2.0.0\n'
    mod foo 'version=2.0.0\ndependencies.bar=^2\n'
    mod baz 'version=2.0.0\ndependencies.bar=^2\n'
    publish
    installer update
    assertEquals "exit: $(output)" 0 $?
    assertEquals "bar" 2.0.0 "$(version_of bar)"
    assertEquals "foo" 2.0.0 "$(version_of foo)"
    assertEquals "baz" 2.0.0 "$(version_of baz)"
}

test_a_version_held_back_goes_in_once_what_held_it_back_moves() {
    mod bar 'version=1.5.0\n'
    mod baz 'version=1.0.0\ndependencies.bar=^1\n'
    publish
    installer install baz
    mod bar 'version=2.0.0\n'
    mod foo 'version=1.0.0\ndependencies.bar=^1\n'
    publish
    mod foo 'version=2.0.0\ndependencies.bar=^2\n'
    publish
    installer install foo
    assertEquals "an older foo" 1.0.0 "$(version_of foo)"
    assertContains "$(output)" "foo 2.0.0 not installed, 1.0.0 instead: it needs bar@^2, but bar would be 1.5.0"
    assertContains "$(output)" "bar 2.0.0 not installed, keeping 1.5.0: baz 1.0.0 needs bar@^1"
    mod baz 'version=2.0.0\ndependencies.bar=^2\n'
    publish
    installer update
    assertEquals "foo moves up with baz" 2.0.0 "$(version_of foo)"
    assertEquals "baz" 2.0.0 "$(version_of baz)"
    assertEquals "bar" 2.0.0 "$(version_of bar)"
}

test_a_mod_takes_its_newest_version_that_suits_the_tv() {
    mod h 'version=1.3.2\nengines.webos=>=4.5\n'
    publish
    mod h 'version=1.5.0\nengines.webos=>=7\n'
    publish
    installer install h
    assertEquals 1.3.2 "$(version_of h)"
    assertContains "$(output)" "h 1.5.0 not installed, 1.3.2 instead: it needs webOS >=7, this TV has 6.5.3"
}

test_a_mod_takes_an_older_version_when_the_newest_needs_another_core() {
    mod q 'version=1.0.0\n'
    publish
    mod q 'version=2.0.0\ndependencies.core=^2\n'
    publish
    installer install q
    assertEquals 1.0.0 "$(version_of q)"
    assertContains "$(output)" "q 2.0.0 not installed, 1.0.0 instead: it needs core@^2, but core would be 1.0.0"
}

test_an_installed_version_never_goes_down() {
    mod p 'version=1.0.0\n'
    publish
    mod p 'version=2.0.0\n'
    publish
    installer install p
    mod x 'version=1.0.0\ndependencies.p=^1\n'
    publish
    installer install x
    assertEquals "p stays" 2.0.0 "$(version_of p)"
    assertContains "$(output)" "x skipped: it needs p@^1, but p would be 2.0.0"
    rm "$WORLD/pub/p-2.0.0.tar.gz"   # withdrawn: only 1.0.0 is listed now
    write_index "$WORLD/pub"
    installer install x
    assertEquals "p still stays" 2.0.0 "$(version_of p)"
}

test_what_a_mod_staying_put_needed_stays_out() {
    mod a 'version=1.0.0\n'
    mod z 'version=1.0.0\ndependencies.a=^1\n'
    publish
    installer install z
    mod extra 'version=1.0.0\n'
    mod a 'version=2.0.0\ndependencies.extra=*\n'
    publish
    installer update a
    assertEquals "a stays, held back by z" 1.0.0 "$(version_of a)"
    assertEquals "and extra, which only a 2.0.0 needed, stays out" "a core z" "$(installed)"
}

test_without_a_search_the_dependency_steps_down_first() {   # foo 2.0.0 with qux 1.0.0 would fit too
    mod bar 'version=1.5.0\n'
    mod foo 'version=1.0.0\ndependencies.bar=^1\n'
    mod qux 'version=1.0.0\n'
    publish
    mod bar 'version=2.0.0\n'
    mod foo 'version=2.0.0\ndependencies.bar=^2\n'
    mod qux 'version=2.0.0\ndependencies.bar=^1\n'
    publish
    installer install foo qux
    assertEquals "exit: $(output)" 0 $?
    assertEquals "foo" 1.0.0 "$(version_of foo)"
    assertEquals "qux" 2.0.0 "$(version_of qux)"
    assertEquals "bar" 1.5.0 "$(version_of bar)"
}

# shellcheck disable=SC1090
. "$SHUNIT2"
