#!/bin/ash
#
# Shared helpers for the TV side's test suites (the build side's have their own, in
# tests/tools/helpers.sh). Each suite sources this file first and shUnit2 last. Every
# test gets a throwaway "world" in $WORLD under /tmp: a dummy repo, the repository
# published from it, and a fake TV (mods dir, a Homebrew Channel dir holding init.d, and
# root's .profile). Nothing outside the world is touched.
#
# Copyright (c) 2026 Andriy Sharandakov
#
# This script is licensed under the MIT License.
# See the LICENSE file for details.
#
# GitHub: https://github.com/ashway83/webos-mods
#
# shellcheck shell=dash

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck disable=SC2034 # the suites source it
SHUNIT2=$ROOT/tests/shunit2   # shUnit2 2.1.8, shipped unmodified with the repo
# shellcheck disable=SC1091
. "$ROOT/mods/core/libmod.sh"   # core's helpers, for the core tests and for assertions

setUp() { new_world; }
tearDown() { drop_world; }

new_world() {  # a fresh world in $WORLD, with core (and webos-mods in it) copied from this repo
    WORLD=$(mktemp -d "${TMPDIR:-/tmp}/webos-mods-test.XXXXXX")
    mkdir -p "$WORLD/repo/mods" "$WORLD/tv/hbc"
    cp -R "$ROOT/mods/core" "$WORLD/repo/mods/"
    MODS_PROFILE=$WORLD/tv/profile   # root's .profile on the fake TV; exported, so that no
    export MODS_PROFILE              # run of core's install script can reach the real one
    TV_WEBOS=6.5.3                 # what the fake TV reports; "unknown" = unreadable
    TV_INITD=$WORLD/tv/hbc/init.d  # Homebrew Channel's hook dir on the fake TV
    TV_REPOSITORY=                 # MODS_REPOSITORY for a run; empty = the stamped one
    TV_ENV=                        # extra VAR=value words for the installer's environment
    TV_COMMAND=                    # how webos_mods runs the command; empty = its installed path
}

drop_world() { rm -rf "$WORLD"; }

skip_test() {  # count the current test as skipped; return from the test right after
    startSkipping
    assertTrue 0
}

mod() {  # mod <name> <meta> [boot] [uninstall] [install]: (re)write a dummy mod in the
         # repo; \n in <meta> separates lines, each script is one shell line ('' = none)
    local dir="$WORLD/repo/mods/$1"
    rm -rf "$dir"
    mkdir -p "$dir"
    printf '%b' "$2" >"$dir/meta"
    if [ -n "${3:-}" ]; then printf '#!/bin/ash\n%s\n' "$3" >"$dir/boot"; fi
    if [ -n "${4:-}" ]; then printf '#!/bin/ash\n%s\n' "$4" >"$dir/uninstall"; fi
    if [ -n "${5:-}" ]; then printf '#!/bin/ash\n%s\n' "$5" >"$dir/install"; fi
}

unmod() { rm -rf "$WORLD/repo/mods/$1"; }   # unmod <name>: drop a mod from the repo

core_at() {  # core_at <version>: the world's core takes that version, to be published
    sed "s/^version=.*/version=$1/" "$WORLD/repo/mods/core/meta" >"$WORLD/meta"
    mv "$WORLD/meta" "$WORLD/repo/mods/core/meta"
}

starts() { echo "echo $1 >>$WORLD/started"; }   # starts <name>: a boot line that logs a start

world_key() {  # world_key: the world's signing key, key.pem, made on first use, and
               # trusted.pem, the public keys its commands trust: that key's, to begin with
    if [ -f "$WORLD/key.pem" ]; then return 0; fi
    openssl ecparam -name prime256v1 -genkey -noout -out "$WORLD/key.pem"
    openssl pkey -in "$WORLD/key.pem" -pubout -out "$WORLD/trusted.pem"
}

trust() {  # trust <public keys> <command> <output>: the command, trusting those keys instead
           # of the ones written in it (CI's core install step does the same with its key)
    awk -v keys="$1" -v q="'" '
        $0 == "KEYS=" q { print; while ((getline line < keys) > 0) print line; skip = 1; next }
        skip && $0 == q { skip = 0 }
        !skip { print }' "$2" >"$3"
}

publish() {  # publish: what CI does with the world's repo, in the format tools/build-repo
             # writes. Each mod's version not published yet goes into the world's
             # repository, $WORLD/pub, as <mod>-<version>.tar.gz, next to the versions
             # published before; core's command is stamped with core's version and the
             # repository's URL, trusts the world's keys (trusted.pem) rather than the
             # official one, and is published as webos-mods-<version> too. A mod whose
             # folder is gone is left out. Then the index, signed with the world's key, and
             # webos-mods, a copy of the newest core's command, are written afresh
    local pub="$WORLD/pub" dir='' name='' version='' file='' newest='' vc='' stem=''
    world_key
    mkdir -p "$pub"
    for file in "$pub"/*.tar.gz; do
        stem=${file##*/}
        stem=${stem%-*}
        if [ -f "$file" ] && [ ! -d "$WORLD/repo/mods/$stem" ]; then rm "$file"; fi
    done
    for dir in "$WORLD/repo/mods"/*/; do
        dir=${dir%/}
        name=${dir##*/}
        version=$(meta "$dir" version)
        if [ -f "$pub/$name-$version.tar.gz" ]; then continue; fi
        rm -rf "$WORLD/pack"
        mkdir -p "$WORLD/pack"
        cp -R "$dir" "$WORLD/pack/$name"
        if [ "$name" = core ]; then
            sed -e "s|@VERSION@|$version|" -e "s|@REPOSITORY@|file://$pub|" "$dir/bin/webos-mods" \
                >"$WORLD/stamped"
            trust "$WORLD/trusted.pem" "$WORLD/stamped" "$WORLD/pack/core/bin/webos-mods"
            cp "$WORLD/pack/core/bin/webos-mods" "$pub/webos-mods-$version"
        fi
        tar -cf - -C "$WORLD/pack" "$name" | gzip >"$pub/$name-$version.tar.gz"
    done
    for file in "$pub"/webos-mods-*; do
        if [ -z "$newest" ]; then newest=$file; continue; fi
        _vcmp "${file##*-}" "${newest##*-}"
        if [ "$vc" -gt 0 ]; then newest=$file; fi
    done
    if [ -n "$newest" ]; then cp "$newest" "$pub/webos-mods"; fi
    write_index "$pub"
}

sign_index() {  # sign_index <repository dir> [<private key>...]: its index.sig, as
                # tools/build-repo writes it: a base64 signature of the index a line, made
                # with each key (the world's, if none is named)
    local dir="$1" key=''
    shift
    if [ $# = 0 ]; then world_key; set -- "$WORLD/key.pem"; fi
    for key in "$@"; do
        openssl dgst -sha256 -sign "$key" "$dir/index" | openssl base64 -A
        echo
    done >"$dir/index.sig"
}

write_index() {  # write_index <repository dir>: its index, listing every archive in it as
                 # tools/build-repo does: format=1, then per archive (by name, then version)
                 # a blank line, name, the meta lines without comments and blank lines, file
                 # and sha256; and its signature, sign_index
    local dir="$1" file='' stem='' name=''
    {
        echo "format=1"
        for file in "$dir"/*.tar.gz; do
            if [ ! -f "$file" ]; then continue; fi
            stem=${file##*/}
            stem=${stem%.tar.gz}
            echo "${stem%-*} $(echo "${stem##*-}" | tr . ' ') ${file##*/}"
        done | sort -k1,1 -k2,2n -k3,3n -k4,4n | while read -r name _ _ _ file; do
            echo
            echo "name=$name"
            tar -xzOf "$dir/$file" "$name/meta" | grep -v -e '^#' -e '^[[:space:]]*$'
            echo "file=$file"
            echo "sha256=$(sha256sum "$dir/$file" | cut -d' ' -f1)"
        done
    } >"$dir/index"
    sign_index "$dir"
}

rehash() {  # rehash <archive>: after a test swaps a published archive, the index lists its
            # new sha256 (the rest of its stanza stays as published)
    local sum=''
    sum=$(sha256sum "$WORLD/pub/$1" | cut -d' ' -f1)
    sed "/^file=$1\$/{n;s/^sha256=.*/sha256=$sum/;}" "$WORLD/pub/index" >"$WORLD/index.new"
    mv "$WORLD/index.new" "$WORLD/pub/index"
    sign_index "$WORLD/pub"
}

installer() {  # installer <args>...: the curl | sh one-liner from the world's repository, on
               # the fake TV. Returns its exit status; its output is in $WORLD/out
    # shellcheck disable=SC2086 # TV_ENV is split into its VAR=value words on purpose
    curl -fsSL "file://$WORLD/pub/webos-mods" | env MODS_REPOSITORY="$TV_REPOSITORY" \
        MODS_PREFIX="$WORLD/tv/mods" MODS_INITD="$TV_INITD" MODS_WEBOS="$TV_WEBOS" $TV_ENV \
        sh -s -- "$@" >"$WORLD/out" 2>&1
}

webos_mods() {  # webos_mods <args>...: the installed command on the fake TV, run through
                # $TV_COMMAND if set. Returns its exit status; its output is in $WORLD/out
    # shellcheck disable=SC2086 # TV_ENV is split into its VAR=value words on purpose
    env MODS_REPOSITORY="$TV_REPOSITORY" MODS_PREFIX="$WORLD/tv/mods" \
        MODS_INITD="$TV_INITD" MODS_WEBOS="$TV_WEBOS" $TV_ENV \
        "${TV_COMMAND:-$WORLD/tv/mods/core/bin/webos-mods}" "$@" >"$WORLD/out" 2>&1
}

boot() {  # reboot the fake TV: run every hook the installer wrote. Calling them in order
          # is Homebrew Channel's job, not ours, so no attempt is made to mimic it
    local hook=''
    rm -f "$WORLD/started"
    for hook in "$TV_INITD"/*; do
        if [ -f "$hook" ]; then MODS_WEBOS="$TV_WEBOS" "$hook"; fi
    done
}

output() { cat "$WORLD/out"; }                                     # the last installer run's output
words() { tr '\n' ' ' | sed 's/ *$//'; }                           # a list on one line
# shellcheck disable=SC2012 # hook names are ours: NN-mod-<checked name>
hooks() { ls "$TV_INITD" 2>/dev/null | words; }                    # hook names, in run order
installed() { installed_mods "$WORLD/tv/mods" | words; }           # installed mods
version_of() { meta "$WORLD/tv/mods/$1" version; }                 # installed version of a mod
started() { if [ -f "$WORLD/started" ]; then words <"$WORLD/started"; fi; }  # mods whose boot ran, in order
boot_log() { cat "$WORLD/tv/mods/$1/boot.log" 2>/dev/null; }       # a mod's boot.log
record_of() { sed -n "s/^$2=//p" "$WORLD/tv/mods/$1/.installed"; } # a value from a mod's install record
