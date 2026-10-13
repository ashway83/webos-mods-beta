#!/bin/ash
#
# core/libmod.sh - helpers shared by webos-mods, the boot hooks and mods.
# Sourced, never run. A mod's scripts can use it too:  . "${0%/*}/../core/libmod.sh"
# Written for busybox ash: POSIX sh plus `local`, and none of the bash-like
# extensions ([[ ]], ${var/a/b}, ${var:1:2}) that busybox builds may leave out.
#
# Copyright (c) 2026 Andriy Sharandakov
#
# This script is licensed under the MIT License.
# See the LICENSE file for details.
#
# GitHub: https://github.com/ashway83/webos-mods
#
# shellcheck shell=dash

webos_version() {  # TV's internal platform version: "6.5.3" from "6.5.3-47". MODS_WEBOS
                   # overrides it; MODS_WEBOS=unknown acts as if it can't be read
    local version=''
    case ${MODS_WEBOS-} in
        unknown) return 0 ;;
        ?*) echo "$MODS_WEBOS"; return 0 ;;
    esac
    version=$(_os_info_release /var/run/nyx/os_info.json)
    if [ -z "$version" ] && command -v nyx-cmd >/dev/null; then
        version=$(nyx-cmd OSInfo query core_os_release 2>/dev/null | sed -n '1s/^[^0-9]*\([0-9.]*\).*/\1/p' || :)
    fi
    echo "$version"
}

_os_info_release() {  # _os_info_release <os_info.json>: its core_os_release, minus the build
    sed -n 's/.*"core_os_release" *: *"\([0-9.]*\).*/\1/p' "$1" 2>/dev/null || :
}

meta() {  # meta <mod dir> <key>: value of a "key=value" line in the mod's meta file
    if [ -f "$1/meta" ]; then sed -n "s/^$2=//p" "$1/meta"; fi
}

dep_names() {  # dep_names <mod dir>: mods it depends on; every mod but core needs core
    if [ "${1##*/}" != core ] && ! grep -q '^dependencies\.core=' "$1/meta" 2>/dev/null; then
        echo core
    fi
    if [ -f "$1/meta" ]; then sed -n 's/^dependencies\.\([^=]*\)=.*/\1/p' "$1/meta"; fi
}

dep_range() {  # dep_range <mod dir> <dependency>: the npm range it asks for (empty = any)
    meta "$1" "dependencies\\.$2"
}

dep_order() {  # dep_order <mods dir> <mod>...: those mods in install order, one group a
               # line: a mod, or the members of a dependency cycle (by name), which go in
               # together, as APT and pacman install cycles. A group goes after the groups
               # its mods depend on; of those free to go, the one with the first name goes
               # first. Mods not named don't count, and boot_order plays no part
    local base="$1" all=' ' graph=' ' grouped=' ' groups='' left='' rest='' placed=' '
    local mod='' group='' member='' deps='' dep='' ready='' next=''
    shift
    for mod in $(printf '%s\n' "$@" | sort -u); do   # what each depends on, read once
        all="$all$mod "
        graph="$graph$mod: $(dep_names "$base/$mod" | tr '\n' ' '); "
    done
    for mod in $all; do   # the groups, each found at its first name
        case $grouped in *" $mod "*) continue ;; esac
        group=$(_dep_cycle "$graph" "$mod" "$all")
        grouped="$grouped$group "
        groups="$groups$group
"
    done
    left=$groups
    while [ -n "$left" ]; do
        next='' rest=''
        while IFS= read -r group; do
            if [ -z "$group" ]; then continue; fi
            ready=''
            if [ -z "$next" ]; then
                ready=1
                for member in $group; do
                    deps=${graph#*" $member: "}
                    for dep in ${deps%%;*}; do
                        case " $group " in *" $dep "*) continue ;; esac   # inside the cycle
                        case $all in *" $dep "*) ;; *) continue ;; esac     # not named
                        case $placed in *" $dep "*) ;; *) ready='' ;; esac
                    done
                done
            fi
            if [ -n "$ready" ]; then next=$group; else rest="$rest$group
"; fi
        done <<GROUPS
$left
GROUPS
        if [ -z "$next" ]; then printf '%s' "$left"; return; fi   # can't happen: some group is free
        echo "$next"
        placed="$placed$next "
        left=$rest
    done
}

_dep_cycle() {  # _dep_cycle <graph> <mod> <set>: <mod> and the mods of <set> in a dependency
                # cycle with it, by name, on one line (<graph> and <set> as in dep_order)
    local reach='' other='' group=''
    reach=$(_dep_reach "$1" "$2" "$3")
    for other in $3; do
        if [ "$other" = "$2" ]; then group="$group $other"; continue; fi
        case $reach in *" $other "*) ;; *) continue ;; esac
        case $(_dep_reach "$1" "$other" "$3") in *" $2 "*) group="$group $other" ;; esac
    done
    echo "${group# }"
}

_dep_reach() {  # _dep_reach <graph> <mod> <set>: the mods of <set> that <mod> leads to
                # through dependencies, space-delimited (<mod> itself only through a cycle)
    local todo="$2 " seen=' ' mod='' deps='' dep=''
    while [ -n "$todo" ]; do
        mod=${todo%% *}
        todo=${todo#* }
        deps=${1#*" $mod: "}
        for dep in ${deps%%;*}; do
            case $3 in *" $dep "*) ;; *) continue ;; esac
            case $seen in *" $dep "*) continue ;; esac
            seen="$seen$dep "
            todo="$todo$dep "
        done
    done
    echo "$seen"
}

boot_order() {  # boot_order <mod dir>: two-digit prefix of its init.d hook, default 50
    local order=''
    order=$(meta "$1" boot_order)
    echo "${order:-50}"
}

webos_ok() {  # webos_ok <mod dir> <webOS version>: in its engines.webos range
              # (true when it has none, or when the version is unknown)
    local range=''
    range=$(meta "$1" 'engines\.webos')
    if [ -z "$range" ] || [ -z "$2" ]; then return 0; fi
    satisfies "$2" "$range"
}

installed_mods() {  # installed_mods <mods dir>: names of the installed mods
    local dir=''
    for dir in "$1"/*/; do
        if [ -d "$dir" ]; then dir=${dir%/}; echo "${dir##*/}"; fi
    done
}

is_mounted() {  # is_mounted <path>: something is mounted on <path>
    grep -qF " $1 " /proc/mounts
}

run_boot() {  # run_boot <mods dir> <mod>: what a mod's init.d hook runs, and what the
              # installer runs to start a mod right away. Runs its boot script unless
              # this webOS is outside engines.webos; outcome goes to the mod's boot.log.
              # Returns 0 if it ran, 1 if skipped, 2 if the script failed.
    local dir="$1/$2" version='' rc=0
    version=$(webos_version)
    if ! webos_ok "$dir" "$version"; then
        echo "not started: webOS $version is outside engines.webos $(meta "$dir" 'engines\.webos')" >"$dir/boot.log"
        return 1
    fi
    /bin/sh "$dir/boot" >"$dir/boot.log" 2>&1 || rc=$?
    if [ "$rc" = 0 ]; then return 0; fi
    echo "boot script failed (exit $rc)" >>"$dir/boot.log"
    return 2
}

# --- npm version ranges -------------------------------------------------------
# The syntax of package.json dependencies (https://github.com/npm/node-semver#ranges):
#   1.2.3  =1.2.3  >1.2  >=1.2.3  <2  <=1.x  ~1.2.3  ^1.2.3  1.x  1.2.*  *  (empty)
#   "1.2.3 - 2.3" (hyphen), "a b" (both must hold), "a || b" (either)
# Versions are plain MAJOR.MINOR.PATCH; prerelease tags (1.2.3-beta) aren't supported.
# Helpers starting with _ are internal; some of them set their caller's locals.

satisfies() {  # satisfies <version> <range>: e.g. satisfies 1.4.2 "^1.2.0 || >=3"
    local rs='' alt='' rest='' tok='' ok=''
    case $2 in *[\<\>=^~]' '*) rs="$(_squeeze "$2")||" ;; *) rs="$2||" ;; esac
    while [ -n "$rs" ]; do
        alt=${rs%%'||'*}
        rs=${rs#*'||'}
        case " $alt " in
            *' - '*)
                if _hyphen "$1" "$(_trim "${alt%% - *}")" "$(_trim "${alt#* - }")"; then return 0; fi ;;
            *)
                ok=1 rest=$alt
                while _next_token; do
                    if ! _comparator "$1" "$tok"; then ok=; break; fi
                done
                if [ -n "$ok" ]; then return 0; fi ;;
        esac
    done
    return 1
}

range_problem() {  # range_problem <range>: print what's wrong with an npm range, if anything
    local rs='' alt='' rest='' tok='' side=''
    case $1 in *[\<\>=^~]' '*) rs="$(_squeeze "$1")||" ;; *) rs="$1||" ;; esac
    while [ -n "$rs" ]; do
        alt=${rs%%'||'*}
        rs=${rs#*'||'}
        case " $alt " in
            *' - '*)
                for side in "$(_trim "${alt%% - *}")" "$(_trim "${alt#* - }")"; do
                    case $side in '' | *' '*) echo "bad hyphen range in '$1'"; return ;; esac
                    _version_ok "$side" || { echo "bad version '$side' in '$1'"; return; }
                done ;;
            *)
                rest=$alt
                while _next_token; do
                    case $tok in
                        '>='* | '<='*) _version_ok "${tok#??}" ;;
                        [\<\>=^~]*) _version_ok "${tok#?}" ;;
                        *) _version_ok "$tok" ;;
                    esac || { echo "bad comparator '$tok' in '$1'"; return; }
                done ;;
        esac
    done
}

_squeeze() {  # _squeeze <range>: drop spaces after operators, as npm does (">= 1.2")
    printf '%s' "$1" | sed 's/\([<>=^~]\) */\1/g'
}

_trim() {  # _trim <text>: without leading and trailing spaces
    local text="${1#"${1%%[! ]*}"}"
    echo "${text%"${text##*[! ]}"}"
}

_next_token() {  # move the next space-separated word of the caller's $rest into $tok
    rest=${rest#"${rest%%[! ]*}"}
    [ -n "$rest" ] || return 1
    tok=${rest%% *}
    rest=${rest#"$tok"}
}

_version_ok() {  # _version_ok <partial version>: 1, 1.2, 1.2.3, 1.x, 1.2.*, *, v1.2.3
    local left="${1#v}" part=''
    case $left in '' | .* | *. | *..* | *.*.*.*) return 1 ;; esac
    while [ -n "$left" ]; do
        part=${left%%.*}
        case $left in *.*) left=${left#*.} ;; *) left= ;; esac
        case $part in
            x | X | '*' | 0) ;;
            [1-9]*) case $part in *[!0-9]*) return 1 ;; esac ;;
            *) return 1 ;;
        esac
    done
}

_parts() {  # _parts <partial version>: set the caller's major minor patch (x where
            # missing or a wildcard) and minor0 patch0 (the same with 0 instead of x)
    local left="${1#v}"
    major=${left%%.*}
    case $left in *.*) left=${left#*.} ;; *) left= ;; esac
    minor=${left%%.*}
    case $left in *.*) left=${left#*.} ;; *) left= ;; esac
    patch=$left
    case $major in '' | x | X | '*') major=x minor=x patch=x ;; esac
    case $minor in '' | x | X | '*') minor=x patch=x ;; esac
    case $patch in '' | x | X | '*') patch=x ;; esac
    case $minor in x) minor0=0 ;; *) minor0=$minor ;; esac
    case $patch in x) patch0=0 ;; *) patch0=$patch ;; esac
}

_vcmp() {  # _vcmp A B: set the caller's $vc to -1, 0 or 1 comparing two full versions
    local left="$1." right="$2." lpart='' rpart=''
    for _ in 1 2 3; do
        lpart=${left%%.*} rpart=${right%%.*}
        left=${left#*.} right=${right#*.}
        if [ "${lpart:-0}" -gt "${rpart:-0}" ]; then vc=1; return; fi
        if [ "${lpart:-0}" -lt "${rpart:-0}" ]; then vc=-1; return; fi
    done
    vc=0
}

_is() {  # _is <version> <op> <full version>: e.g. _is 1.4.2 '<' 2.0.0
    local vc=''
    _vcmp "$1" "$3"
    case $2 in
        '>=') [ "$vc" -ge 0 ] ;;
        '>') [ "$vc" -gt 0 ] ;;
        '<=') [ "$vc" -le 0 ] ;;
        '<') [ "$vc" -lt 0 ] ;;
        *) [ "$vc" -eq 0 ] ;;
    esac
}

_between() {  # _between <version> <low> <high>: low <= version < high
    _is "$1" '>=' "$2" && _is "$1" '<' "$3"
}

_comparator() {  # _comparator <version> <comparator>: one npm comparator, e.g. ^1.2
    local comp="$2" op='' major='' minor='' patch='' minor0='' patch0='' hi='' nx=''
    case $comp in
        '>='* | '<='*) op=${comp%"${comp#??}"} comp=${comp#??} ;;
        [\<\>=^~]*) op=${comp%"${comp#?}"} comp=${comp#?} ;;
    esac
    _parts "$comp"
    case $op in
        '' | =)       # exact, or an x-range like 1.x / 1.2 / *
            if [ "$major" = x ]; then return 0; fi
            if [ "$minor" = x ]; then _between "$1" "$major.0.0" "$((major + 1)).0.0"; return; fi
            if [ "$patch" = x ]; then _between "$1" "$major.$minor.0" "$major.$((minor + 1)).0"; return; fi
            _is "$1" = "$major.$minor.$patch" ;;
        '~')          # patch updates: ~1.2.3 is >=1.2.3 <1.3.0
            if [ "$major" = x ]; then return 0; fi
            if [ "$minor" = x ]; then _between "$1" "$major.0.0" "$((major + 1)).0.0"; return; fi
            _between "$1" "$major.$minor.$patch0" "$major.$((minor + 1)).0" ;;
        '^')          # no change to the leftmost non-zero part: ^1.2.3 is >=1.2.3 <2.0.0
            if [ "$major" = x ]; then return 0; fi
            if [ "$minor" = x ]; then _between "$1" "$major.0.0" "$((major + 1)).0.0"; return; fi
            if [ "$major" != 0 ]; then hi=$((major + 1)).0.0
            elif [ "$minor" != 0 ] || [ "$patch" = x ]; then hi=0.$((minor + 1)).0
            else hi=0.0.$((patch + 1)); fi
            _between "$1" "$major.$minor.$patch0" "$hi" ;;
        *)            # > >= < <=; a partial version counts as all of its x.y.z
            if [ "$major" = x ]; then [ "$op" = '>=' ] || [ "$op" = '<=' ]; return; fi
            if [ "$minor" = x ]; then nx=$((major + 1)).0.0
            elif [ "$patch" = x ]; then nx=$major.$((minor + 1)).0; fi
            case $op in
                '>') if [ -n "$nx" ]; then _is "$1" '>=' "$nx"; else _is "$1" '>' "$major.$minor.$patch"; fi ;;
                '<=') if [ -n "$nx" ]; then _is "$1" '<' "$nx"; else _is "$1" '<=' "$major.$minor.$patch"; fi ;;
                *) _is "$1" "$op" "$major.$minor0.$patch0" ;;
            esac ;;
    esac
}

_hyphen() {  # _hyphen <version> <from> <to>: npm "from - to", inclusive at both ends
    local major='' minor='' patch='' minor0='' patch0=''
    _parts "$2"
    if [ "$major" != x ] && ! _is "$1" '>=' "$major.$minor0.$patch0"; then return 1; fi
    _parts "$3"
    if [ "$major" = x ]; then return 0; fi
    if [ "$minor" = x ]; then _is "$1" '<' "$((major + 1)).0.0"; return; fi
    if [ "$patch" = x ]; then _is "$1" '<' "$major.$((minor + 1)).0"; return; fi
    _is "$1" '<=' "$major.$minor.$patch"
}

meta_problem() {  # meta_problem <mod dir>: print what's wrong with its meta, if anything
    local version='' problem='' dep='' key='' value=''
    if grep -q "$(printf '\r')" "$1/meta" 2>/dev/null; then
        echo "meta must have Unix line endings (LF, not CRLF)"; return
    fi
    version=$(meta "$1" version)
    case $version in *.*.*.* | *[!0-9.]*) version= ;; *.*.*) ;; *) version= ;; esac
    if [ -z "$version" ] || ! _version_ok "$version"; then echo "meta needs version=MAJOR.MINOR.PATCH"; return; fi
    case $(meta "$1" boot_order) in '' | [0-9][0-9]) ;; *) echo "boot_order must be two digits"; return ;; esac
    if grep '^dependencies\.' "$1/meta" | grep -qv '^dependencies\.[A-Za-z0-9_-][A-Za-z0-9_-]*='; then
        echo "dependency names may only use letters, digits, - and _"; return
    fi
    problem=$(range_problem "$(meta "$1" 'engines\.webos')")
    if [ -n "$problem" ]; then echo "engines.webos: $problem"; return; fi
    for dep in $(dep_names "$1"); do
        problem=$(range_problem "$(dep_range "$1" "$dep")")
        if [ -n "$problem" ]; then echo "dependencies.$dep: $problem"; return; fi
    done
    for key in name file sha256 format; do   # a repository's index adds these
        if grep -q "^$key=" "$1/meta"; then echo "meta can't set $key: a repository's index does"; return; fi
    done
    value=$(meta "$1" keywords)
    case ,$value, in
        ,,) ;;   # none
        *,,* | *[!A-Za-z0-9_,-]*)   # an empty word, a comma at either end, or another character
            echo "keywords must be words separated by commas (letters, digits, - and _)"; return ;;
    esac
    case $(meta "$1" homepage) in '' | https://?*) ;; *) echo "homepage must be an https:// URL"; return ;; esac
    value=$(meta "$1" license)
    if [ -n "$value" ] && [ -n "$(printf %s "$value" | tr -d 'A-Za-z0-9.+() -')" ]; then
        echo "license must be an SPDX expression, like MIT or MIT AND GPL-2.0-only"; return
    fi
}

publish_problem() {  # publish_problem <mod dir>: what keeps it out of a repository, if
                     # anything: a meta problem; a line that isn't a comment (# first), a
                     # blank or key=value with a key published mods use, or a key set twice;
                     # a missing description or license. meta_problem, which the TV uses, is
                     # more lenient, so that older commands take mods with newer keys
    local problem='' line='' key=''
    problem=$(meta_problem "$1")
    if [ -n "$problem" ]; then echo "$problem"; return; fi
    line=$(grep -v -e '^#' -e '^[[:space:]]*$' "$1/meta" | grep -v -e '^version=' -e '^description=' \
        -e '^license=' -e '^keywords=' -e '^homepage=' -e '^author=' -e '^boot_order=' \
        -e '^engines\.webos=' -e '^dependencies\.[A-Za-z0-9_-][A-Za-z0-9_-]*=' | head -n 1)
    case $line in
        '') ;;
        *=*) echo "unknown meta key: ${line%%=*} (published mods can use version, description, license, keywords, homepage, author, boot_order, engines.webos, dependencies.<mod>)"; return ;;
        *) echo "meta line isn't key=value or a comment: $line"; return ;;
    esac
    key=$(grep -v -e '^#' -e '^[[:space:]]*$' "$1/meta" | cut -d= -f1 | sort | uniq -d | head -n 1)
    if [ -n "$key" ]; then echo "meta sets $key more than once"; return; fi
    if [ -z "$(meta "$1" description)" ]; then echo "meta needs description=, a line on what the mod does"; return; fi
    if [ -z "$(meta "$1" license)" ]; then echo "meta needs license=, an SPDX expression like MIT"; fi
}
