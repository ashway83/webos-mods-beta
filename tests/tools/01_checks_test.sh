#!/usr/bin/env bash
#
# 1. Checks: what tools/build-repo checks before building anything (names, meta,
#    scripts, dependencies and their cycles, and with --base, version bumps), and that the
#    build side's scripts parse.
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

check() {  # check [<option>...]: build-repo on the world's mods into a fresh folder.
           # Returns its exit status; its output is in $WORLD/out
    rm -rf "$WORLD/site"
    "$ROOT/tools/build-repo" --url "file://$WORLD/site" --key "$WORLD/key.pem" "$@" "$WORLD/repo/mods" \
        "$WORLD/site" >"$WORLD/out" 2>&1
}

git_repo() {  # git_repo <args>...: git in the world's repo, without the user's settings
    git -C "$WORLD/repo" -c user.name=test -c user.email=test@example.invalid \
        -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"
}

commit_all() { git_repo add -A && git_repo commit -qm "$1"; }   # commit_all <message>

on_a_branch() {  # on_a_branch: the world's repo as it is becomes main, and a branch off it
                 # is checked out, as for a pull request
    git -C "$WORLD/repo" init -q -b main
    commit_all base
    git_repo checkout -qb change
}

only_commands() {  # only_commands <command>...: $WORLD/bin with just these (those found),
                   # for a PATH without the rest; what runs before a tool is looked for
    local cmd='' path=''
    mkdir -p "$WORLD/bin"
    for cmd in "$@"; do
        if path=$(command -v "$cmd"); then ln -sf "$path" "$WORLD/bin/$cmd"; fi
    done
}

test_the_build_sides_scripts_parse() {
    local file=''
    for file in "$ROOT"/tools/* "$ROOT"/tests/tools/*.sh "$ROOT"/tests/tools/run; do
        bash -n "$file"
        assertTrue "syntax error in ${file#"$ROOT"/}" $?
    done
}

test_this_repos_mods_pass_the_checks() {
    "$ROOT/tools/build-repo" --url "file://$WORLD/site" --key "$WORLD/key.pem" "$ROOT/mods" "$WORLD/site" \
        >"$WORLD/out" 2>&1
    assert_status 0 $?
}

test_a_folder_name_that_isnt_a_mod_name_is_flagged() {
    mod b 'version=1.0.0\n'
    mv "$WORLD/repo/mods/b" "$WORLD/repo/mods/b.old"
    check
    assert_status 1 $?
    assertContains "$(output)" "invalid mod name: 'b.old'"
}

test_a_mod_named_self_is_flagged() {
    mod self 'version=1.0.0\n'
    check
    assert_status 1 $?
    assertContains "$(output)" "self: reserved name, it stands for core"
}

test_a_mod_can_hold_symlinks() {
    mod b 'version=1.0.0\n'
    ln -s /etc "$WORLD/repo/mods/b/etc"
    ln -s meta "$WORLD/repo/mods/b/link"
    check
    assert_status 0 $?
}

test_a_mod_holds_no_special_files_and_isnt_a_symlink() {
    mod b 'version=1.0.0\n'
    mkfifo "$WORLD/repo/mods/b/pipe"
    mod c 'version=1.0.0\n'
    mv "$WORLD/repo/mods/c" "$WORLD/c"
    ln -s "$WORLD/c" "$WORLD/repo/mods/c"
    check
    assert_status 1 $?
    assertContains "$(output)" "b: pipe is a special file; a mod holds files, folders and symlinks"
    assertContains "$(output)" "c: its folder is a symlink, so its archive would hold no files"
}

test_files_the_tv_writes_are_refused() {
    mod b 'version=1.0.0\n'
    : >"$WORLD/repo/mods/b/boot.log"
    mod c 'version=1.0.0\n'
    : >"$WORLD/repo/mods/c/.installed"
    mod d 'version=1.0.0\n'
    ln -s /nonexistent "$WORLD/repo/mods/d/boot.log"   # root would write through it
    check
    assert_status 1 $?
    assertContains "$(output)" "b: holds boot.log, which only the TV writes"
    assertContains "$(output)" "c: holds .installed, which only the TV writes"
    assertContains "a symlink too" "$(output)" "d: holds boot.log, which only the TV writes"
}

test_bad_meta_is_flagged() {
    mod b 'version=1.0\n'
    check
    assert_status 1 $?
    assertContains "$(output)" "b: meta needs version"
}

test_publishing_needs_a_description_and_a_license() {
    mod b 'version=1.0.0\ndescription=\n'
    check
    assert_status 1 $? "no description"
    assertContains "$(output)" "b: meta needs description="
    mod b 'version=1.0.0\nlicense=\n'
    check
    assertContains "no license" "$(output)" "b: meta needs license="
}

test_unknown_meta_keys_are_flagged() {
    mod b 'version=1.0.0\nbootorder=40\n'
    check
    assert_status 1 $?
    assertContains "$(output)" "b: unknown meta key: bootorder"
}

test_a_script_that_doesnt_parse_is_flagged() {
    mod b 'version=1.0.0\n' 'if true; then'
    check
    assert_status 1 $?
    assertContains "$(output)" "b: boot:"
    assertContains "$(output)" ": error: "
}

# shellcheck disable=SC2016 # $x is for the scripts it writes, not for this suite
test_scripts_are_checked_as_dash_scripts() {   # the TV runs them with its sh
    mod b 'version=1.0.0\n' 'if [[ -n $x ]]; then echo b; fi'
    mod c 'version=1.0.0\n'
    printf '#!/bin/bash\n# shellcheck shell=bash\nif [[ -n $x ]]; then echo c; fi\n' >"$WORLD/repo/mods/c/boot"
    check
    assert_status 1 $?
    assertContains "b: [[ ]]" "$(output)" "b: boot:2:4: error: "
    assertContains "c: [[ ]], whatever its first lines say" "$(output)" "c: boot:3:4: error: "
    assertContains "$(output)" "[SC3010]"
}

test_building_needs_openssl() {
    only_commands bash dirname grep gtar tar sha256sum shellcheck
    PATH=$WORLD/bin "$ROOT/tools/build-repo" --url "file://$WORLD/site" --key "$WORLD/key.pem" \
        "$WORLD/repo/mods" "$WORLD/site" >"$WORLD/out" 2>&1
    assert_status 1 $?
    assertContains "$(output)" "needs openssl"
}

test_building_needs_shellcheck() {
    only_commands bash dirname grep gtar tar sha256sum openssl
    PATH=$WORLD/bin "$ROOT/tools/build-repo" --url "file://$WORLD/site" --key "$WORLD/key.pem" \
        "$WORLD/repo/mods" "$WORLD/site" >"$WORLD/out" 2>&1
    assert_status 1 $?
    assertContains "$(output)" "needs shellcheck"
}

test_a_missing_dependency_is_flagged() {
    mod e 'version=1.0.0\ndependencies.ghost=*\n'
    check
    assert_status 1 $?
    assertContains "$(output)" "e depends on ghost, which isn't among the mods"
}

test_a_broken_dependency_is_reported_once() {
    mod b 'version=1.0\n'
    mod c 'version=1.0.0\ndependencies.b=*\n'
    check
    assert_status 1 $?
    assertContains "$(output)" "b: meta needs version"
    assertNotContains "c not faulted for it" "$(output)" "c depends on b"
}

test_a_range_the_mods_dont_satisfy_is_flagged() {
    mod b 'version=2.0.0\n'
    mod p 'version=1.0.0\ndependencies.b=~1.0\n'
    check
    assert_status 1 $?
    assertContains "$(output)" "p needs b@~1.0, but b is at 2.0.0"
}

test_boot_order_isnt_checked_against_dependencies() {   # it only sorts init.d hooks
    mod b 'version=1.0.0\nboot_order=40\n'
    mod early 'version=1.0.0\nboot_order=10\ndependencies.b=*\n'
    check
    assert_status 0 $?
}

test_a_dependency_cycle_is_noted_not_refused() {
    mod a 'version=1.0.0\ndependencies.b=*\n'
    mod b 'version=1.0.0\ndependencies.a=*\n'
    mod x 'version=1.0.0\ndependencies.y=*\n'
    mod y 'version=1.0.0\ndependencies.z=*\n'
    mod z 'version=1.0.0\ndependencies.x=*\n'
    check
    assert_status 0 $?
    assertContains "$(output)" "a and b form a dependency cycle: they install together, a first"
    assertContains "$(output)" "x, y and z form a dependency cycle: they install together, x first"
}

test_a_mod_depending_on_itself_is_flagged() {
    mod a 'version=1.0.0\ndependencies.a=*\n'
    check
    assert_status 1 $?
    assertContains "$(output)" "a depends on itself"
}

test_every_problem_is_reported_before_stopping() {
    mod b 'version=1.0\n'
    mod c 'version=1.0.0\ndependencies.ghost=*\n'
    mod d 'version=1.0.0\n' 'if true; then'
    check
    assert_status 1 $?
    assertContains "$(output)" "b: meta needs version"
    assertContains "$(output)" "c depends on ghost"
    assertContains "$(output)" "d: boot:"
    assertFalse "nothing written" "[ -e '$WORLD/site' ]"
}

test_problems_are_annotations_in_github_actions() {
    mod b 'version=1.0\n'
    GITHUB_ACTIONS=true check
    assertContains "$(output)" "::error::b: meta needs version"
}

test_names_cant_start_workflow_commands() {
    mkdir "$WORLD/repo/mods/$(printf 'x\n::warning::y')" "$WORLD/repo/mods/$(printf 'r\r::warning::z')" \
        "$WORLD/repo/mods/p%0Aq"
    GITHUB_ACTIONS=true check
    assertFalse "a line of its own: $(output)" "grep -q '^::warning::' '$WORLD/out'"
    assertContains "$(output)" "::error::invalid mod name: 'x\n::warning::y'"
    assertContains "$(output)" "::error::invalid mod name: 'r\r::warning::z'"
    assertContains "% escaped" "$(output)" "::error::invalid mod name: 'p%250Aq'"
}

test_core_has_to_be_among_the_mods() {
    mod b 'version=1.0.0\ndependencies.core=^1.0.0\n'
    unmod core
    check
    assert_status 1 $?
    assertContains "$(output)" "core isn't among the mods: a repository needs it, for webos-mods and its helpers"
    assertNotContains "said once, not for each mod" "$(output)" "b depends on core"
}

test_a_changed_mod_needs_a_higher_version() {
    mod b 'version=1.0.0\n' 'echo old'
    mod c 'version=1.9.0\n'
    on_a_branch
    mod b 'version=1.0.0\n' 'echo new'
    mod c 'version=1.10.0\n'
    commit_all change
    check --base main
    assert_status 1 $?
    assertContains "$(output)" "b changed since main, so it needs a version higher than 1.0.0"
    assertNotContains "1.10.0 is higher than 1.9.0" "$(output)" "c changed"
    mod b 'version=0.9.0\n' 'echo new'
    commit_all lower
    check --base main
    assertContains "lower" "$(output)" "b changed since main"
    mod b 'version=1.0.1\n' 'echo new'
    commit_all higher
    check --base main
    assert_status 0 $? higher
}

test_unchanged_new_and_removed_mods_pass_the_version_check() {
    mod b 'version=1.0.0\n'
    mod gone 'version=1.0.0\n'
    on_a_branch
    unmod gone
    mod new 'version=1.0.0\n'
    commit_all change
    check --base main
    assert_status 0 $?
}

test_a_file_moved_between_mods_changes_both() {
    mod b 'version=1.0.0\n'
    mod c 'version=1.0.0\n'
    seq 1 100 >"$WORLD/repo/mods/b/data"   # big enough for git to see a rename
    on_a_branch
    mv "$WORLD/repo/mods/b/data" "$WORLD/repo/mods/c/data"
    commit_all move
    check --base main
    assertContains "$(output)" "b changed since main"
    assertContains "$(output)" "c changed since main"
}

test_an_unknown_base_stops_the_build() {
    on_a_branch
    check --base nonesuch
    assert_status 1 $?
    assertContains "$(output)" "--base: nonesuch isn't a commit in the git repository holding"
}

test_base_needs_git() {
    only_commands bash dirname grep gtar tar sha256sum openssl shellcheck
    PATH=$WORLD/bin "$ROOT/tools/build-repo" --base main --url "file://$WORLD/site" --key "$WORLD/key.pem" \
        "$WORLD/repo/mods" "$WORLD/site" >"$WORLD/out" 2>&1
    assert_status 1 $?
    assertContains "$(output)" "--base needs git"
}

# shellcheck disable=SC1090
. "$SHUNIT2"
