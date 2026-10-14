#!/bin/ash
#
# 1. Environment: our scripts parse, and the tools they and these tests rely on work.
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

test_every_script_parses() {   # the TV side's; tests/tools checks the build side's
    local file=''
    for file in "$ROOT"/mods/*/bin/* "$ROOT"/mods/*/libmod.sh "$ROOT"/mods/*/install "$ROOT"/mods/*/boot \
        "$ROOT"/mods/*/uninstall "$ROOT"/tests/main/*.sh "$ROOT"/tests/main/run; do
        if [ -f "$file" ]; then
            sh -n "$file"
            assertTrue "syntax error in ${file#"$ROOT"/}" $?
        fi
    done
}

test_curl_reads_file_urls() {
    curl -fsS -o /dev/null "file://$ROOT/mods/core/bin/webos-mods"
    assertTrue "curl can't read file:// URLs, which the installer tests use" $?
}

test_openssl_checks_a_signature_as_webos_mods_does() {
    printf 'format=1\n' >"$WORLD/index"
    sign_index "$WORLD"   # with a new ECDSA P-256 key, in base64, as tools/build-repo signs
    printf '%s' "$(head -n 1 "$WORLD/index.sig")" | openssl base64 -d -A >"$WORLD/signature"
    openssl dgst -sha256 -verify "$WORLD/trusted.pem" -signature "$WORLD/signature" "$WORLD/index" >/dev/null
    assertTrue "openssl can't verify an ECDSA P-256 signature, which the index has" $?
    echo changed >>"$WORLD/index"
    openssl dgst -sha256 -verify "$WORLD/trusted.pem" -signature "$WORLD/signature" "$WORLD/index" >/dev/null 2>&1
    assertFalse "openssl verifies a signature of something else" $?
}

test_curl_reaches_github_pages_over_https() {   # where the repository is served from
    if [ -n "${MODS_TEST_OFFLINE:-}" ]; then skip_test; return; fi
    curl -fsS -o /dev/null --max-time 30 https://github.io/   # a redirect, which will do
    assertTrue "curl can't reach https://github.io, which serves the repository (outdated CA certificates?)" $?
}

# shellcheck disable=SC1090
. "$SHUNIT2"
