#!/bin/ash
#
# 3. npm version ranges: core's satisfies and range_problem, checked against answers
#    from npm's own semver package (tests/main/semver-cases.txt, see gen-semver-cases.js).
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

setUp() { :; }
tearDown() { :; }

test_satisfies_agrees_with_npm() {
    local range='' version='' want='' got='' wrong='' count=0
    while IFS=';' read -r range version want; do
        if satisfies "$version" "$range"; then got=1; else got=0; fi
        count=$((count + 1))
        if [ "$got" != "$want" ]; then
            wrong="$wrong
    satisfies $version '$range' gives $got, npm says $want"
        fi
    done <"$ROOT/tests/main/semver-cases.txt"
    assertEquals "cases read" "$(wc -l <"$ROOT/tests/main/semver-cases.txt" | tr -d ' ')" "$count"
    assertNull "disagreements with npm:$wrong" "$wrong"
}

test_every_tested_range_is_valid() {
    local range='' bad=''
    while IFS= read -r range; do
        if [ -n "$(range_problem "$range")" ]; then bad="$bad '$range'"; fi
    done <<RANGES
$(cut -d';' -f1 "$ROOT/tests/main/semver-cases.txt" | sort -u)
RANGES
    assertNull "rejected:$bad" "$bad"
}

test_malformed_ranges_are_rejected() {
    local range=''
    for range in '1.2.3.4' 'a.b.c' '>=abc' '^' '>=' '1..2' '01.2.3' '1.2.3-beta' '1.2.3 - ' '- 2' \
        '>=1.2.3 <' '~1.2.3x'; do
        assertNotNull "should reject '$range'" "$(range_problem "$range")"
    done
}

test_range_problems_say_what_is_wrong() {
    assertEquals "bad hyphen range in '1.2.3 - '" "$(range_problem '1.2.3 - ')"
    assertEquals "bad hyphen range in '1 - 2 3'" "$(range_problem '1 - 2 3')"
    assertEquals "bad version 'abc' in '1.2 - abc'" "$(range_problem '1.2 - abc')"
    assertEquals "bad comparator '<abc' in '>=1.2.3 <abc'" "$(range_problem '>=1.2.3 <abc')"
    assertEquals "after || and a spaced operator" "bad comparator '>=one' in '^1 || >= one'" \
        "$(range_problem '^1 || >= one')"
}

# shellcheck disable=SC1090
. "$SHUNIT2"
