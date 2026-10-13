#!/bin/ash
#
# 11. Finding mods: search lists what the repository has (all of it, or the mods whose
#     name, description or keywords hold a word), with the newest version that suits
#     the TV, marking what's installed, what can be updated and what needs another
#     webOS; info shows a mod's details and every version. Both only read: no lock, no
#     self-update, nothing changes on the TV.
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
    mod b 'version=1.0.0\ndescription=Blocks ads with a hosts file\nkeywords=dns,privacy\n'
    mod a 'version=1.0.0\ndescription=An aerial screensaver\ndependencies.b=^1.0.0\n'
    publish
}

line_of() { grep "^$1 " "$WORLD/out" | tr -s ' '; }   # line_of <mod>: its line, spaces squeezed
names() { cut -d' ' -f1 "$WORLD/out" | words; }       # the mods search listed

test_search_lists_every_mod_without_a_word() {
    installer search
    assertEquals "exit: $(output)" 0 $?
    assertEquals "by name" "a b core" "$(names)"
    assertEquals "a 1.0.0 An aerial screensaver" "$(line_of a)"
    assertEquals "b 1.0.0 Blocks ads with a hosts file" "$(line_of b)"
    assertFalse "nothing written on the TV" "[ -e '$WORLD/tv/mods' ]"
}

test_search_matches_names_descriptions_and_keywords_in_any_case() {
    installer search ADS
    assertEquals "exit" 0 $?
    assertEquals "a description, in any case" "b" "$(names)"
    installer search privacy
    assertEquals "a keyword" "b" "$(names)"
    installer search cor
    assertEquals "a name" "core" "$(names)"
    installer search nothing-like-it
    assertEquals "no match: exit" 0 $?
    assertEquals "no match" ">> no mod matches 'nothing-like-it'" "$(output)"
}

test_search_marks_installed_mods_and_updates() {
    installer install a
    mod b 'version=1.1.0\ndescription=Blocks ads with a hosts file\nkeywords=dns,privacy\n'
    publish
    installer search
    assertEquals "a 1.0.0 An aerial screensaver [installed]" "$(line_of a)"
    assertEquals "b 1.1.0 Blocks ads with a hosts file [installed 1.0.0, update available]" "$(line_of b)"
}

test_search_shows_the_newest_version_that_suits_the_tv() {
    mod b 'version=2.0.0\ndescription=Blocks ads, for new TVs\nengines.webos=>=99\n'
    mod old 'version=1.0.0\ndescription=For old TVs\nengines.webos=<=5\n'
    publish
    installer search
    assertEquals "b 1.0.0 Blocks ads with a hosts file" "$(line_of b)"
    assertEquals "none suits" "old 1.0.0 For old TVs [needs webOS <=5]" "$(line_of old)"
    # shellcheck disable=SC2034 # read by installer() in helpers.sh
    TV_WEBOS=unknown
    installer search
    assertEquals "unknown webOS, as install takes it" "old 1.0.0 For old TVs [needs webOS <=5]" "$(line_of old)"
}

test_search_shows_an_installed_version_this_webos_no_longer_takes() {
    mod b 'version=1.1.0\ndescription=Blocks ads, newer\nengines.webos=>=6\n'
    mod old 'version=1.0.0\ndescription=For old TVs\nengines.webos=<=5\n'
    publish
    installer install b
    # shellcheck disable=SC2034 # read by installer() in helpers.sh
    TV_WEBOS=5.0.0
    installer install old
    TV_WEBOS=6.5.3
    installer search
    assertEquals "the newest that suits" "b 1.1.0 Blocks ads, newer [installed]" "$(line_of b)"
    assertEquals "none suits" "old 1.0.0 For old TVs [installed 1.0.0, needs webOS <=5]" "$(line_of old)"
    # shellcheck disable=SC2034 # read by installer() in helpers.sh
    TV_WEBOS=5.0.0
    installer search
    assertEquals "an older one suits" "b 1.0.0 Blocks ads with a hosts file [installed 1.1.0]" "$(line_of b)"
}

test_info_shows_a_mods_details_and_versions() {
    installer install b
    mod b 'version=1.1.0\ndescription=Blocks ads with a hosts file\nlicense=MIT\nhomepage=https://example.org/b\nkeywords=dns,privacy\nauthor=Someone\ndependencies.core=^1.0.0\ndependencies.lib=\nengines.webos=>=4.5\n'
    publish
    mod b 'version=2.0.0\ndescription=Blocks ads, for new TVs\nengines.webos=>=99\n'
    publish
    installer info b
    assertEquals "exit" 0 $?
    assertEquals "the newest that suits, and every version" "name: b
version: 1.1.0
description: Blocks ads with a hosts file
license: MIT
homepage: https://example.org/b
keywords: dns, privacy
author: Someone
dependencies: core@^1.0.0, lib@*
webOS: >=4.5
versions: 2.0.0 (needs webOS >=99), 1.1.0, 1.0.0 (installed)
repository: file://$WORLD/pub" "$(output)"
}

test_info_says_when_the_installed_version_isnt_listed() {
    installer install b
    rm "$WORLD/pub/b-1.0.0.tar.gz"
    mod b 'version=1.1.0\ndescription=Blocks ads with a hosts file\n'
    publish
    installer info b
    assertEquals "exit" 0 $?
    assertTrue "versions: $(output)" "grep -qx 'versions: 1.1.0' '$WORLD/out'"
    assertTrue "installed" "grep -qx 'installed: 1.0.0, which the repository no longer lists' '$WORLD/out'"
}

test_info_needs_a_mod_the_repository_lists() {
    installer info nosuch
    assertEquals "exit" 1 $?
    assertContains "$(output)" "nosuch: no such mod in file://$WORLD/pub"
    installer install b
    unmod b
    publish
    installer info b
    assertEquals "dropped: exit" 1 $?
    assertContains "$(output)" "b isn't in the repository any more"
}

test_search_and_info_check_their_arguments() {
    installer search a b
    assertEquals "two words: exit" 1 $?
    assertContains "$(output)" "usage: webos-mods search [<word>]"
    installer info
    assertEquals "no mod: exit" 1 $?
    assertContains "$(output)" "usage: webos-mods info <mod>"
    installer info a b
    assertEquals "two mods: exit" 1 $?
    installer info ../x
    assertEquals "an invalid name: exit" 1 $?
    assertContains "$(output)" "invalid mod name: '../x'"
    installer info self
    assertEquals "self: exit" 0 $?
    assertEquals "self stands for core" "name: core" "$(head -n 1 "$WORLD/out")"
}

test_search_and_info_change_nothing() {
    installer install b
    core_at 1.1.0
    publish
    webos_mods search
    assertEquals "exit" 0 $?
    assertNotContains "the installed copy, without a self-update" "$(output)" "running webos-mods"
    assertContains "$(line_of core)" "[installed 1.0.0, update available]"
    installer info core   # the piped copy, whose core isn't the installed one: staged only
    assertEquals "info: exit" 0 $?
    assertContains "$(output)" "versions: 1.1.0, 1.0.0 (installed)"
    assertEquals "core as it was" 1.0.0 "$(version_of core)"
    assertEquals "b and core" "b core" "$(installed)"
}

# shellcheck disable=SC1090
. "$SHUNIT2"
