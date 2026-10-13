#!/bin/ash
#
# 12. The hosts example mod, for real: bind-mounting a merged file over the target, on top
#     of any other mount there (such as Homebrew Channel's), and taking off only its own.
#     It's pointed at a throwaway file (MODS_HOSTS_FILE), not /etc/hosts. Skipped where
#     this user can't bind-mount.
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

oneTimeSetUp() {
    local dir=''
    dir=$(mktemp -d "${TMPDIR:-/tmp}/webos-mods-mount.XXXXXX")
    : >"$dir/a"
    : >"$dir/b"
    NO_MOUNT=1
    if mount -o bind "$dir/a" "$dir/b" 2>/dev/null; then umount "$dir/b"; NO_MOUNT=; fi
    rm -rf "$dir"
}

setUp() {
    new_world
    cp -R "$ROOT/mods/hosts" "$WORLD/repo/mods/"
    echo "0.0.0.0 ads.example.com" >>"$WORLD/repo/mods/hosts/blocklist"
    publish
    echo "127.0.0.1 localhost" >"$WORLD/hosts.stock"
    cp "$WORLD/hosts.stock" "$WORLD/etc-hosts"
    MODS_HOSTS_FILE=$WORLD/etc-hosts
    export MODS_HOSTS_FILE
}

tearDown() {
    while is_mounted "$MODS_HOSTS_FILE"; do umount "$MODS_HOSTS_FILE" || break; done
    unset MODS_HOSTS_FILE
    drop_world
}

mounts() { grep -cF " $MODS_HOSTS_FILE " /proc/mounts; }

test_install_adds_the_blocklist_to_the_stock_entries() {
    if [ -n "$NO_MOUNT" ]; then skip_test; return; fi
    installer install hosts
    assertContains "$(cat "$MODS_HOSTS_FILE")" "127.0.0.1 localhost"
    assertContains "$(cat "$MODS_HOSTS_FILE")" "0.0.0.0 ads.example.com"
}

test_booting_again_doesnt_mount_twice() {
    if [ -n "$NO_MOUNT" ]; then skip_test; return; fi
    installer install hosts
    boot
    boot
    assertEquals 1 "$(mounts)"
}

test_update_replaces_the_mount_instead_of_stacking() {
    if [ -n "$NO_MOUNT" ]; then skip_test; return; fi
    installer install hosts
    echo "0.0.0.0 tracker.example.com" >>"$WORLD/repo/mods/hosts/blocklist"
    sed -i 's/^version=.*/version=1.0.1/' "$WORLD/repo/mods/hosts/meta"
    publish
    installer update
    assertEquals 1 "$(mounts)"
    assertContains "$(cat "$MODS_HOSTS_FILE")" "0.0.0.0 tracker.example.com"
}

test_removal_restores_the_stock_file() {
    if [ -n "$NO_MOUNT" ]; then skip_test; return; fi
    installer install hosts
    installer remove hosts
    assertEquals 0 "$(mounts)"
    assertEquals "$(cat "$WORLD/hosts.stock")" "$(cat "$MODS_HOSTS_FILE")"
}

test_it_stacks_on_another_mount_and_takes_off_only_its_own() {   # as on Homebrew Channel's,
    if [ -n "$NO_MOUNT" ]; then skip_test; return; fi             # which blocks system updates
    { cat "$WORLD/hosts.stock"; echo "127.0.0.1 snu.lge.com"; } >"$WORLD/hosts.hbc"
    mount -o bind "$WORLD/hosts.hbc" "$MODS_HOSTS_FILE"
    installer install hosts
    assertContains "applied on top" "$(cat "$MODS_HOSTS_FILE")" "0.0.0.0 ads.example.com"
    assertContains "the entries below kept" "$(cat "$MODS_HOSTS_FILE")" "127.0.0.1 snu.lge.com"
    assertEquals "stacked" 2 "$(mounts)"
    boot
    assertEquals "not again at boot" 2 "$(mounts)"
    installer remove hosts
    assertEquals "only its own taken off" 1 "$(mounts)"
    assertEquals "the one below shows again" "$(cat "$WORLD/hosts.hbc")" "$(cat "$MODS_HOSTS_FILE")"
}

test_removal_leaves_a_mount_that_isnt_its_own() {
    if [ -n "$NO_MOUNT" ]; then skip_test; return; fi
    installer install hosts
    umount "$MODS_HOSTS_FILE"                                # its own gone, as after a reboot,
    mount -o bind "$WORLD/hosts.stock" "$MODS_HOSTS_FILE"    # and another mount there instead
    installer remove hosts
    assertEquals "left alone" 1 "$(mounts)"
}

# shellcheck disable=SC1090
. "$SHUNIT2"
