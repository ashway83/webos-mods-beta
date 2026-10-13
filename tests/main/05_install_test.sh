#!/bin/ash
#
# 5. Install and update: what goes in, in which order, and which hooks it gets.
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
    mod lib1 'version=1.0.0\n'
    mod x 'version=1.0.0\nboot_order=52\ndependencies.lib1=1.x\n' "$(starts x)"
    publish
}

test_install_brings_its_dependencies_and_core() {
    installer install a
    assertEquals "exit" 0 $?
    assertEquals "a b core" "$(installed)"
    assertContains "core goes in first" "$(head -n 1 "$WORLD/out")" "core 1.0.0 installed"
}

test_mods_go_in_after_the_mods_they_depend_on() {
    installer install a x
    assertEquals "dependencies first, then by name" "b a x" "$(started)"
}

test_boot_order_only_orders_the_hooks() {
    mod early 'version=1.0.0\nboot_order=10\ndependencies.late=\n' "$(starts early)"
    mod late 'version=1.0.0\nboot_order=90\n' "$(starts late)"
    publish
    installer install early
    assertEquals "the dependency goes in, and starts, first" "late early" "$(started)"
    assertEquals "the hooks sort by boot_order" "10-mod-early 90-mod-late" "$(hooks)"
}

test_only_mods_with_a_boot_script_get_a_hook() {
    installer install a x
    assertEquals "40-mod-b 52-mod-x 60-mod-a" "$(hooks)"
}

test_a_hook_starts_its_mod_through_core() {
    installer install b
    assertEquals "#!/bin/ash
. \"$WORLD/tv/mods/core/libmod.sh\" && run_boot \"$WORLD/tv/mods\" b" "$(cat "$TV_INITD/40-mod-b")"
    [ -x "$TV_INITD/40-mod-b" ]
    assertTrue "hook is executable" $?
}

test_installing_an_unchanged_mod_does_nothing() {
    installer install a
    : >"$WORLD/tv/mods/a/.marker"
    installer install a
    assertContains "$(output)" "a 1.0.0 is up to date"
    [ -e "$WORLD/tv/mods/a/.marker" ]
    assertTrue "a's folder is untouched" $?
}

test_each_mod_gets_an_install_record() {
    installer install b
    assertEquals "repository" "file://$WORLD/pub" "$(record_of b repository)"
    assertEquals "version" 1.0.0 "$(record_of b version)"
    assertEquals "url" "file://$WORLD/pub/b-1.0.0.tar.gz" "$(record_of b url)"
    assertEquals "sha256" "$(sha256sum "$WORLD/pub/b-1.0.0.tar.gz" | cut -d' ' -f1)" "$(record_of b sha256)"
    case $(record_of b date) in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
        *) fail "date isn't UTC ISO 8601: '$(record_of b date)'" ;;
    esac
    assertFalse "no .sha256 any more" "[ -e '$WORLD/tv/mods/b/.sha256' ]"
}

test_reinstall_replaces_an_unchanged_mod() {
    installer install a
    : >"$WORLD/tv/mods/a/.marker"
    installer reinstall a
    assertContains "$(output)" "a 1.0.0 installed and started"
    [ -e "$WORLD/tv/mods/a/.marker" ]
    assertFalse "a's folder was replaced" $?
}

test_reinstall_self_replaces_core() {
    installer install b
    : >"$WORLD/tv/mods/core/.marker"
    webos_mods reinstall self
    assertEquals "exit: $(output)" 0 $?
    assertContains "$(output)" "core 1.0.0 installed"
    assertFalse "core's folder was replaced" "[ -e '$WORLD/tv/mods/core/.marker' ]"
}

test_reinstall_needs_the_installed_version_in_the_repository() {
    installer install b
    rm "$WORLD/pub/b-1.0.0.tar.gz"
    mod b 'version=2.0.0\nboot_order=40\nengines.webos=>=99\n' "$(starts b)"   # newer, but not for this TV
    publish
    installer reinstall b
    assertEquals "exit: $(output)" 0 $?
    assertContains "$(output)" "b 1.0.0 isn't in the repository any more, so it can't be reinstalled"
    assertEquals "b kept" 1.0.0 "$(version_of b)"
}

test_update_installs_only_what_changed() {
    installer install a
    mod a 'version=1.1.0\nboot_order=60\ndependencies.b=^1.0.0\n' "$(starts a)"
    publish
    installer update
    assertContains "$(output)" "a 1.1.0 installed and started"
    assertContains "$(output)" "b 1.0.0 is up to date"
}

test_update_changes_only_the_mods_named() {
    installer install a x
    mod a 'version=1.1.0\nboot_order=60\ndependencies.b=^1.0.0\n' "$(starts a)"
    mod x 'version=1.1.0\nboot_order=52\ndependencies.lib1=1.x\n' "$(starts x)"
    publish
    installer update x
    assertEquals "exit" 0 $?
    assertEquals "x updated" 1.1.0 "$(version_of x)"
    assertEquals "a not" 1.0.0 "$(version_of a)"
    installer update nope
    assertEquals "not installed: exit" 1 $?
    assertContains "$(output)" "nope is not installed"
}

test_update_moves_the_hook_when_boot_order_changes() {
    installer install b
    mod b 'version=1.1.0\nboot_order=45\n' "$(starts b)"
    publish
    installer update
    assertEquals "45-mod-b" "$(hooks)"
}

test_update_removes_the_hook_when_the_boot_script_goes() {
    installer install b
    mod b 'version=1.1.0\nboot_order=40\n'
    publish
    installer update
    assertContains "$(output)" "b 1.1.0 installed"
    assertEquals "" "$(hooks)"
}

test_update_keeps_mods_dropped_from_the_repository() {
    installer install b
    unmod b
    publish
    installer update
    assertEquals "exit" 0 $?
    assertContains "$(output)" "b isn't in the repository any more; leaving it as is"
    assertEquals 1.0.0 "$(version_of b)"
}

test_install_skips_a_mod_outside_its_webos_range() {
    mod old 'version=1.0.0\nengines.webos=<=5\n'
    publish
    installer install old b
    assertContains "$(output)" "old skipped: it needs webOS <=5, this TV has 6.5.3"
    assertEquals "b core" "$(installed)"
}

test_unknown_webos_skips_only_mods_with_a_webos_range() {
    mod old 'version=1.0.0\nengines.webos=>=4\n'
    publish
    # shellcheck disable=SC2034 # read by installer() and boot() in helpers.sh
    TV_WEBOS=unknown
    installer install old b
    assertContains "$(output)" "old skipped: it needs webOS >=4, and this TV's version is unknown"
    assertEquals "b core" "$(installed)"
}

test_core_isnt_installed_alone_unless_asked_for() {
    mod old 'version=1.0.0\nengines.webos=<=5\n'
    publish
    installer install old
    assertEquals "old skipped: nothing installed" "" "$(installed)"
    assertNotContains "core not even put in" "$(output)" "core 1.0.0 installed"
    installer install core
    assertEquals "exit" 0 $?
    assertEquals "core" "$(installed)"
    assertTrue "with the command" "[ -x '$WORLD/tv/mods/core/bin/webos-mods' ]"
}

test_list_shows_webos_and_versions() {
    installer install a
    installer list
    assertContains "$(output)" "webos-mods 1.0.0"
    assertContains "$(output)" "webOS 6.5.3"
    grep -q '^a  *1\.0\.0' "$WORLD/out"
    assertTrue "a's version is listed" $?
}

test_commands_with_nothing_installed() {
    installer list
    assertEquals "list: exit" 0 $?
    assertContains "$(output)" "nothing installed"
    installer update
    assertEquals "update: exit" 1 $?
    installer remove a
    assertEquals "remove: exit" 1 $?
}

test_MODS_REPOSITORY_replaces_the_official_repository() {
    cp -R "$WORLD/pub" "$WORLD/mirror"
    # shellcheck disable=SC2034 # read by installer() in helpers.sh
    TV_REPOSITORY=file://$WORLD/mirror
    installer install a
    assertEquals "exit: $(output)" 0 $?
    assertEquals "from the mirror" "file://$WORLD/mirror" "$(record_of a repository)"
    mod a 'version=1.1.0\nboot_order=60\ndependencies.b=^1.0.0\n' "$(starts a)"
    publish
    # shellcheck disable=SC2034 # read by installer() in helpers.sh
    TV_REPOSITORY=
    installer update a
    assertEquals "without it, from the official one: the record doesn't decide" 1.1.0 "$(version_of a)"
}

# shellcheck disable=SC1090
. "$SHUNIT2"
