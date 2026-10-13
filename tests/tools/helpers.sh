#!/usr/bin/env bash
#
# Shared helpers for the build side's test suites (the TV side's have their own, in
# tests/main/helpers.sh). Each suite sources this file first and shUnit2 last. Every test
# gets a throwaway "world" in $WORLD under /tmp: a dummy repo holding a copy of this
# repo's core. Nothing outside the world is touched.
#
# Copyright (c) 2026 Andriy Sharandakov
#
# This script is licensed under the MIT License.
# See the LICENSE file for details.
#
# GitHub: https://github.com/ashway83/webos-mods

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck disable=SC2034 # the suites source it
SHUNIT2=$ROOT/tests/shunit2   # shUnit2 2.1.8, shipped unmodified with the repo

setUp() { new_world; }
tearDown() { drop_world; }

new_world() {  # a fresh world in $WORLD: a dummy repo holding a copy of this repo's core,
               # and a key to sign repositories with, key.pem
    WORLD=$(mktemp -d "${TMPDIR:-/tmp}/webos-mods-build-test.XXXXXX")
    mkdir -p "$WORLD/repo/mods"
    cp -R "$ROOT/mods/core" "$WORLD/repo/mods/"
    openssl ecparam -name prime256v1 -genkey -noout -out "$WORLD/key.pem"
}

drop_world() { rm -rf "$WORLD"; }

mod() {  # mod <name> <meta> [<boot>]: (re)write a dummy mod in the repo; \n in <meta>
         # separates lines, and <boot> is one shell line ('' = none). A description and a
         # license, which publishing needs, are added unless <meta> sets them (even empty)
    local dir="$WORLD/repo/mods/$1"
    rm -rf "$dir"
    mkdir -p "$dir"
    printf '%b' "$2" >"$dir/meta"
    if ! grep -q '^description=' "$dir/meta"; then echo "description=Test mod $1" >>"$dir/meta"; fi
    if ! grep -q '^license=' "$dir/meta"; then echo "license=MIT" >>"$dir/meta"; fi
    if [[ -n ${3-} ]]; then printf '#!/bin/ash\n%s\n' "$3" >"$dir/boot"; fi
}

unmod() { rm -rf "$WORLD/repo/mods/$1"; }   # unmod <name>: drop a mod from the repo

output() { cat "$WORLD/out"; }             # the last run's output
words() { tr '\n' ' ' | sed 's/ *$//'; }   # a list on one line

assert_status() {  # assert_status <expected> <status> [<label>]: a run's exit status, with
                   # its output shown if wrong. Pass $? straight in: bash makes a command
                   # substitution's status $? as soon as it ends, so in
                   # assertEquals "$(output)" 0 $? it would be cat's (see CLAUDE.md, Testing)
    assertEquals "${3:-exit}: $(output)" "$1" "$2"
}
