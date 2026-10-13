#!/bin/ash
#
# 10. The webos-mods command: its command line (a command is required, help, "self"),
#     the installed copy (MODS_PREFIX, its line in root's .profile), and how it updates
#     itself when it installs or updates: it runs the webos-mods of the newer core it
#     chose, checked like any mod, unless that core can't be had, or MODS_NO_SELFUPDATE=1.
#     The other commands stay with the installed copy. (Which core it chooses: suite 06.)
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

first_line() { head -n 1 "$WORLD/out"; }
switched() { grep -q "^>> running webos-mods $1 instead of the installed" "$WORLD/out"; }  # it ran $1

test_a_command_is_required() {
    installer b
    assertEquals "exit" 1 $?
    assertContains "$(output)" "unknown command: b"
    installer
    assertEquals "no arguments: exit" 1 $?
    assertContains "no arguments: help" "$(output)" "usage: webos-mods <command> [<mod>...]"
    assertEquals "nothing installed" "" "$(installed)"
}

test_help_lists_the_commands() {
    installer help
    assertEquals "exit" 0 $?
    assertContains "$(output)" "webos-mods 1.0.0: mods for a rooted LG webOS TV"
    assertContains "$(output)" "update [<mod>...]"
    assertContains "$(output)" "search [<word>]"
    assertContains "$(output)" "info <mod>"
    installer --help
    assertEquals "--help: exit" 0 $?
    curl -fsSL "file://$WORLD/pub/webos-mods" | sh -s -- help 2>/dev/null >"$WORLD/out"
    assertContains "help goes to stdout" "$(output)" "usage:"
    curl -fsSL "file://$WORLD/pub/webos-mods" | sh -s -- 2>/dev/null >"$WORLD/out"
    assertEquals "without a command, to stderr" "" "$(output)"
}

test_self_stands_for_core() {
    installer install a
    installer remove self
    assertEquals "refused: exit" 1 $?
    assertContains "$(output)" "core (self) is needed by: a b"
    installer remove a b self
    assertEquals "exit" 0 $?
    assertContains "$(output)" "core removed"
    assertEquals "" "$(installed)"
}

test_update_self_updates_only_core() {
    installer install a
    core_at 1.1.0
    mod a 'version=1.1.0\nboot_order=60\ndependencies.b=^1.0.0\n' "$(starts a)"
    publish
    installer update self
    assertEquals "exit" 0 $?
    assertEquals "core updated" 1.1.0 "$(version_of core)"
    assertEquals "a not updated" 1.0.0 "$(version_of a)"
}

test_install_puts_the_command_on_PATH() {
    printf 'export PS1=x\nPATH=/usr/bin:/bin\n' >"$MODS_PROFILE"
    installer install b
    assertTrue "installed and executable" "[ -x '$WORLD/tv/mods/core/bin/webos-mods' ]"
    assertEquals "one line at the end, the rest kept" "export PS1=x
PATH=/usr/bin:/bin
PATH=\"\$PATH:$WORLD/tv/mods/core/bin\"  # webos-mods" "$(cat "$MODS_PROFILE")"
    core_at 1.1.0
    publish
    installer update
    assertEquals "core updated" 1.1.0 "$(version_of core)"
    assertEquals "after updating core, still one line" 1 "$(grep -c '  # webos-mods$' "$MODS_PROFILE")"
}

test_the_first_install_says_where_the_command_is() {
    installer install b
    assertContains "$(output)" \
        ">> webos-mods is now a command: $WORLD/tv/mods/core/bin/webos-mods (on PATH in new login shells)"
    installer install a
    assertNotContains "only the first time" "$(output)" "is now a command"
}

test_removing_core_takes_the_command_off_PATH() {
    printf 'export PS1=x\n' >"$MODS_PROFILE"
    installer install b
    installer remove b
    assertContains "core stays, and the line" "$(cat "$MODS_PROFILE")" "# webos-mods"
    installer remove self
    assertEquals "export PS1=x" "$(cat "$MODS_PROFILE")"
}

test_core_uninstall_drops_the_PATH_line_only_on_removal() {
    installer install b
    sh "$WORLD/tv/mods/core/uninstall" update 1.0.0
    assertContains "kept on update" "$(cat "$MODS_PROFILE")" "  # webos-mods"
    sh "$WORLD/tv/mods/core/uninstall" remove
    assertNotContains "dropped on removal" "$(cat "$MODS_PROFILE")" "  # webos-mods"
}

test_the_installed_command_reads_MODS_PREFIX() {
    installer install b
    webos_mods list
    assertEquals "exit" 0 $?
    grep -q '^b  *1\.0\.0' "$WORLD/out"
    assertTrue "b is listed: $(output)" $?
    # shellcheck disable=SC2034 # read by webos_mods() in helpers.sh
    TV_ENV="MODS_PREFIX=$WORLD/elsewhere"
    webos_mods list
    assertContains "another mods dir" "$(output)" "nothing installed"
}

test_the_installed_command_stops_too_if_its_core_isnt_published() {
    installer install b
    rm "$WORLD/pub/core-1.0.0.tar.gz"
    write_index "$WORLD/pub"
    # shellcheck disable=SC2034 # read by webos_mods() in helpers.sh
    TV_ENV="MODS_PREFIX=$WORLD/elsewhere"   # a mods dir without core
    webos_mods install b
    assertEquals "exit" 1 $?
    assertContains "$(output)" "core 1.0.0 isn't in file://$WORLD/pub"
    assertFalse "nothing installed there" "[ -e '$WORLD/elsewhere' ]"
}

test_list_and_remove_run_the_installed_copy() {
    installer install b
    core_at 1.1.0
    publish
    webos_mods list
    assertEquals "list: the installed copy" "webos-mods 1.0.0" "$(first_line)"
    # shellcheck disable=SC2034 # read by webos_mods() in helpers.sh
    TV_REPOSITORY=file://$WORLD/nowhere
    webos_mods list
    assertNotContains "nothing to fetch, so no warning" "$(output)" "couldn't"
    webos_mods remove b
    assertEquals "remove: exit" 0 $?
    assertNotContains "remove: no warning" "$(output)" "couldn't"
    assertEquals "core" "$(installed)"
}

test_install_and_update_switch_to_a_newer_core() {
    installer install b
    core_at 1.1.0
    publish
    webos_mods install a
    assertEquals "install: exit" 0 $?
    assertTrue "install: switched to 1.1.0: $(output)" "switched 1.1.0"
    assertEquals "that copy installed a, and its core" "a b core" "$(installed)"
    assertEquals 1.1.0 "$(version_of core)"
    core_at 1.2.0
    mod b 'version=1.1.0\nboot_order=40\n' "$(starts b)"
    publish
    webos_mods update
    assertEquals "update: exit" 0 $?
    assertTrue "update: switched to 1.2.0: $(output)" "switched 1.2.0"
    assertEquals "core, and the command, now 1.2.0" 1.2.0 "$(version_of core)"
    assertEquals "and every installed mod updated" 1.1.0 "$(version_of b)"
}

test_a_core_that_cant_be_had_leaves_this_copy_to_carry_on() {
    installer install b
    core_at 1.1.0
    mod b 'version=1.1.0\nboot_order=40\n' "$(starts b)"
    publish
    echo tampered >"$WORLD/pub/core-1.1.0.tar.gz"   # the index keeps its published sha256
    webos_mods update
    assertEquals "exit" 0 $?
    assertContains "$(output)" "core 1.1.0: checksum mismatch (file://$WORLD/pub/core-1.1.0.tar.gz)"
    assertContains "$(output)" "!! couldn't get core 1.1.0; running the installed 1.0.0"
    assertFalse "not switched" "switched 1.1.0"
    assertEquals "its own core stays" 1.0.0 "$(version_of core)"
    assertEquals "the rest goes ahead" 1.1.0 "$(version_of b)"
}

test_a_core_without_webos_mods_leaves_this_copy_to_carry_on() {
    installer install b
    core_at 1.1.0
    publish
    mkdir "$WORLD/x"
    tar -xzf "$WORLD/pub/core-1.1.0.tar.gz" -C "$WORLD/x"
    rm "$WORLD/x/core/bin/webos-mods"
    tar -cf - -C "$WORLD/x" core | gzip >"$WORLD/pub/core-1.1.0.tar.gz"
    rehash core-1.1.0.tar.gz
    webos_mods update
    assertEquals "exit" 0 $?
    assertContains "$(output)" "core 1.1.0 holds no webos-mods"
    assertContains "$(output)" "!! couldn't get core 1.1.0; running the installed 1.0.0"
    assertEquals "its own core stays" 1.0.0 "$(version_of core)"
}

test_without_a_newer_core_it_runs_itself() {
    installer install b
    core_at 1.1.0
    publish
    installer update
    cp "$WORLD/pub/webos-mods-1.0.0" "$WORLD/pub/webos-mods"   # the one-liner's copy plays no part
    webos_mods update
    assertEquals "exit" 0 $?
    assertNotContains "not switched" "$(output)" "running webos-mods"
    assertNotContains "no warning" "$(output)" "!!"
    assertEquals "core stays" 1.1.0 "$(version_of core)"
}

test_MODS_NO_SELFUPDATE_keeps_the_installed_copy() {
    installer install b
    core_at 1.1.0
    publish
    # shellcheck disable=SC2034 # read by webos_mods() in helpers.sh
    TV_ENV=MODS_NO_SELFUPDATE=1
    webos_mods update
    assertEquals "exit" 0 $?
    assertFalse "not switched" "switched 1.1.0"
    assertEquals "its own core stays" 1.0.0 "$(version_of core)"
}

pinned() {  # pinned <version> <args>...: the one-liner with that version's copy, on the fake TV
    local version="$1"
    shift
    curl -fsSL "file://$WORLD/pub/webos-mods-$version" | env MODS_PREFIX="$WORLD/tv/mods" \
        MODS_INITD="$TV_INITD" MODS_WEBOS="$TV_WEBOS" sh -s -- "$@" >"$WORLD/out" 2>&1
}

test_a_piped_copy_never_updates_itself() {
    installer install b
    core_at 1.1.0
    publish
    pinned 1.0.0 update
    assertEquals "exit" 0 $?
    assertFalse "not switched" "switched 1.1.0"
    assertEquals "the piped copy's own core" 1.0.0 "$(version_of core)"
}

test_a_pinned_older_copy_installs_its_own_core() {   # lockstep, even below the installed one
    core_at 1.1.0
    publish
    installer install b
    assertEquals "the newest" 1.1.0 "$(version_of core)"
    pinned 1.0.0 install b
    assertEquals "exit" 0 $?
    assertEquals "its own" 1.0.0 "$(version_of core)"
}

test_a_symlink_to_the_command_is_recognised() {
    installer install b
    core_at 1.1.0
    publish
    mkdir "$WORLD/links"
    ln -s "$WORLD/tv/mods/core/bin/webos-mods" "$WORLD/links/wm"
    # shellcheck disable=SC2034 # read by webos_mods() in helpers.sh
    TV_COMMAND=$WORLD/links/wm
    webos_mods update
    assertTrue "it updated itself: $(output)" "switched 1.1.0"
}

# shellcheck disable=SC1090
. "$SHUNIT2"
