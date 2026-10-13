# webos-mods

Mods for rooted LG webOS TVs (Homebrew Channel), managed on the TV by the `webos-mods`
command, which a `curl | sh` one-liner from the official repository installs. This
file records the design decisions made with the maintainer while building it. Keep it
current: when a decision changes, update it here.

## Layout

- `mods/core/bin/webos-mods`: the program, piped into `sh` the first time and installed
  with core as the `webos-mods` command. `tools/build-repo` stamps `@VERSION@` (core's
  version) and `@REPOSITORY@` (the official repository's URL) when it publishes core.
  All logic lives in functions and `main "$@"` is the last line, so a truncated
  download runs nothing. Keep it that way.
- `mods/<name>/`: one folder per mod (`meta`, optional `install`, `boot`, `uninstall`,
  plus its own files), installed to `/media/developer/mods/<name>/`.
- `mods/core/libmod.sh`: helpers shared by webos-mods, the boot hooks and mods.
- `mods/core/install`, `mods/core/uninstall`: put the command on root's `PATH`, and
  take it off again (see core).
- `mods/hosts/`: example mod; bind-mounts `/etc/hosts` as it finds it (stock, or
  Homebrew Channel's copy when that blocks system updates) plus `blocklist` over
  `/etc/hosts`, behind a marker line, and takes off only its own mount
  (`MODS_HOSTS_FILE` retargets it for tests).
- `CONTRIBUTING.md`: for mod authors: what a mod may do, checking a mod (with a
  throwaway key, and on a TV), what reviewers check, how publishing works. `LICENSE`:
  MIT, for the repository's own code; each mod states its own licence.
- `.github/workflows/ci.yml`: on every pull request and push to `main`, shellcheck, both
  sides' tests, a trial build (the repo checks, and the version check), and core
  installed from it into a fake TV; after a push to `main`, publishes the repository to
  `gh-pages`, signed with the `publishing` environment's key, and tags a new core
  version. See "Planned: mod repositories", step 5, and Signing.
- `tools/build-repo`: checks a folder of mods (names, contents, meta, scripts with
  shellcheck, dependencies and their cycles; with `--base`, version bumps), then builds a
  repository from it, on top of the one published so far, and signs its index (see
  "Planned: mod repositories", and Signing). Bash 4+, shellcheck and openssl, for CI and
  developer machines only, never a TV. Run from a checkout: it checks mods with this
  checkout's `libmod.sh`.
- `tests/main/`: the TV side's shUnit2 suites (the command, core, hooks, mods), with
  their helpers, runner and the ranges suite's data; `tests/tools/`: the build side's,
  for what's in `tools/` (the repository builder and its checks), with their own
  helpers and runner; `tests/shunit2`, which both use. See Testing.

## Hard constraints

- Shebangs: `#!/bin/ash` for every script that runs on the TV (webos-mods, core's and
  mods' scripts, the hooks webos-mods writes, the tests and the scripts they write);
  `#!/usr/bin/env bash` for the build side, `tools/build-repo` and its tests
  (`tests/tools/`), which need bash 4+ and never run on a TV (whose `/bin/bash` is
  busybox). `.github/` holds only the workflow, which runs these. CI links `/bin/ash`
  to busybox, since the tests run the installed command and the TV runner directly.
- File names (decided 2026-10-12): scripts that are run rather than sourced have no
  extension. Commands run by their shebang and are executable (mode 755): `webos-mods`,
  the hooks it writes, `tools/build-repo`, and the runners `tests/main/run` and
  `tests/tools/run`. The mods' `install`, `boot` and `uninstall` run through `sh`.
  Sourced files keep `.sh` (`libmod.sh`, the helpers), and so do the test suites
  (`NN_name_test.sh`, shUnit2's naming). So `*.sh` doesn't catch every script: CI's
  shellcheck step and both syntax-check tests list the commands by name (or `tools/*`).
- Everything that runs on the TV targets **busybox ash**: POSIX sh plus `local`. No
  bash-like extensions that busybox builds may lack (`[[ ]]`, `${var/a/b}`,
  `${var:1:2}`), no arrays. Stick to plain applet options like those already used
  (BRE `sed`, `grep -qF/-v/-x`, `sort`, `cut`, `tar -xzf`).
- In functions, declare variables `local` and initialise them (`webos-mods` runs with
  `set -eu`), empty ones as `x=''`. Assign command substitutions separately
  (`local x=''` then `x=$(...)`), not in `local`, which would hide their exit status
  (shellcheck SC2155). A few
  core helpers (`_next_token`, `_parts`, `_vcmp`) deliberately set their caller's
  locals; this is documented where they're defined.
- Never expand untrusted text unquoted (globbing): validate names first (`check_name`,
  `meta_problem`) and tokenise ranges the way `_next_token` does.
- Messages: `>> ` progress on stdout, `!! ` warnings and errors on stderr. Tests assert
  on message text, so change both together.

## Design decisions (made with the maintainer; don't change them silently)

### Distribution and the command
- First use: `curl -fsSL https://ashway83.github.io/webos-mods/webos-mods | sh -s -- install <mod>...`.
  Pin a version with `webos-mods-<version>` instead of `webos-mods`. There is no
  separate install script: the same program ships inside core, so that first run
  installs it as the command.
- Commands, always required (no default `install`): `install <mod>...`,
  `reinstall <mod>...`, `remove <mod>...` (no download), `update [<mod>...]` (all
  installed mods, or only those named and what they need; a name that isn't installed
  is an error), `list` (this version, the TV's webOS, the mods), `search [<word>]`,
  `info <mod>` (see below), `help`. No arguments prints the help on stderr with exit
  status 1; `help`, `-h` and `--help` print it on stdout with exit status 0; anything
  else fails with `unknown command`.
- `search` and `info` (step 3, 2026-10-13) read the repository and change nothing:
  no lock, no self-update. Like install, they use this command's own core for the
  helpers, staged (downloaded, checked, not installed) when it isn't the installed
  one, so they work with nothing installed. A version "suits the TV" as install
  takes it: no `engines.webos`, or one holding the TV's known version.
  - `search [<word>]`: a line per mod whose name, description or keywords hold the
    word, ignoring case (all mods without one), by name: name, the newest version that
    suits the TV (or the newest, when none does), description, then marks in brackets:
    `[installed]`, `[installed 1.0.0, update available]`, `[installed 1.1.0]` (newer
    than any that suits), `[needs webOS <range>]` (none suits; may follow an installed
    mark). No match: `>> no mod matches '<word>'`, exit status 0. More than one word is
    a usage error.
  - `info <mod>`: `key: value` lines: `name`, then from the newest version that suits
    the TV (or the newest) `version`, `description`, `license`, `homepage`,
    `keywords`, `author`, `dependencies` (the declared ones, as `mod@range`, `*` for
    any), `webOS` (its range), each only when set; then `versions` (newest first,
    marked `(installed)` and `(needs webOS <range>)`), `installed: <version>, which the
    repository no longer lists` when that's so, and `repository`. A mod the repository
    doesn't list stops the run (`isn't in the repository any more` when installed).
- Exit status (decided 2026-10-11): it says whether what was asked for happened. 1
  when something failed and so didn't happen: an error that stops the run (core held
  back included, since nothing changes then), or a mod's install script failing (the
  attempt is undone). A failure the run carries on after is a warning with exit
  status 0: a mod's uninstall script (the removal or update goes ahead), its boot
  script right after install (the mod is installed; the hook tries again at the next
  boot), core's line in `.profile`. Mods skipped or held back by their webOS or
  dependency ranges are normal outcomes too: warnings, exit status 0.
- `self` stands for `core` wherever a mod name is accepted (`update self`,
  `remove self`); it's swapped right after the arguments are read, and no mod may be
  called `self` (`check_name`, `tools/build-repo`). Refusals name both:
  `core (self) is needed by: ...`.
- One repository (step 2; one since 2026-10-13, several are postponed to version 2.0,
  see there): the official one, stamped in when core is published, or `MODS_REPOSITORY`
  in its place (a mirror, tests). Every mod comes from it, core and the command
  included. The URL is `https://` or `file://`, in letters, digits and
  `. _ ~ : / % + @ -` (no glob or quote characters); anything else stops the run. Every
  run that reads it fetches its index afresh (no cache); an index that can't be read,
  or is of another format, stops the run. Stanzas with an invalid name, version or
  dependency name are left out with a warning. Where a mod was installed from isn't
  read back: once `MODS_REPOSITORY` is unset, a mod installed from a mirror updates
  from the official repository.
- Versions (decided 2026-10-13): every mod in a run starts at its newest version that
  suits the TV's webOS, never below its installed one (no automatic downgrades). Then,
  until nothing changes, a version steps down to the next older one where another
  mod's range refuses it (checked first, so a clash moves the dependency, not the
  dependent) or its own dependencies won't be met; what a changing mod depends on joins
  the run, and what nothing changing needs leaves it. A mod that runs out of versions
  is held back. Versions only step down within a run, so it ends; nothing is
  remembered between runs, so a version passed over goes in once nothing holds it
  back. The repository's newest versions fit together (`tools/build-repo` checks
  that), so usually nothing steps down. Messages: `foo 2.0.0 not installed, 1.0.0
  instead: <why>`, `bar 2.0.0 not installed, keeping 1.5.0: <why>`, `q skipped: <why>`.
- Downloads: everything that changes is downloaded and checked before anything changes:
  the sha256 the index gives; the archive holds only its mod's folder (files, folders
  and symlinks; no `..`, nothing beneath a symlink, no `.installed` or `boot.log`); its
  meta passes `meta_problem` and has the version the index says. Any failure stops the
  run.
- Signing (step 7, decided 2026-10-13): nothing in the index is used unless its
  signature verifies; the index holds every archive's sha256, so it vouches for them, as
  APT signs `Release` rather than each package. CI signs the index with an ECDSA P-256
  key into `index.sig`, a base64 signature (SHA-256) a line. The private key is the
  `SIGNING_KEY` secret of the GitHub Environment `publishing`, which only the publish
  job on `main` can read, and is kept nowhere else (decided 2026-10-13). GitHub can't
  give a secret back, so a lost key, or one needed elsewhere, means a new key: a key
  change (below). Its public key is
  written in `webos-mods` itself, `KEYS` (a PEM block each), committed like the code
  rather than stamped or derived when building, since a piped first install has no core
  yet. Every run that reads the index (install, update, search, info, the self-update)
  checks it with `openssl dgst -sha256 -verify` before anything else, and any line
  that verifies with any key will do. Otherwise the run stops, and says why, briefly:
  `can't verify the signature of <url>/index: openssl not found` (also on a TV without
  openssl), `couldn't download index.sig`, or `it's invalid, or made with another key`.
  Signatures don't expire: whoever serves an old, validly signed index can only withhold
  updates, as nothing is downgraded and only published versions go in; so no
  `valid-until` and no re-signing schedule. It protects against tampered hosting,
  mirrors and transport, not a bad merge or a compromised GitHub account (signing is
  CI's; review covers merges); the first install trusts the one-liner's TLS. A mirror
  (`MODS_REPOSITORY`) copies `index.sig` too.
  - A key change: commit the new public key next to the old (a new core version, whose
    command trusts both), sign with both (`--key` twice, a second secret) while
    commands that only trust the old key are in use, then drop the old one. A TV whose
    command only trusts a key no longer used needs the one-liner again.
  - Trial builds and tests sign with throwaway keys, and no flag says so:
    `tools/build-repo` signs with whatever key it's given, without checking it against
    the command's. The real key can't sign a pull request's trial build: GitHub passes
    no secrets to pull requests from forks (how outside mods arrive), and the
    environment keeps it from PR branches; on pushes to `main`, the publish job's check
    is the test of the shipped key against it. The TV side's test worlds and CI's core install step have their copy
    of the command trust their key (`trust` in `tests/main/helpers.sh`: `KEYS`' lines
    replaced). The publish job, before pushing, has the newest published command read
    the new index (`search` in a fake TV), so a wrong secret stops the publish.
- Self-update, only in `install`, `reinstall` and `update` (decided 2026-10-11; step 4,
  2026-10-13): the installed command chooses core's version like any mod's (see
  Versions), never below its own, so core is the newest version that every installed
  mod accepts at the version it will have after the run. `update` thus moves core and
  the mods that need the new core together, while `install` leaves the other installed
  mods as they are, and they may hold core back (`core 2.0.0 not installed, 1.5.0
  instead: hosts 1.0.0 needs core@^1`). Mods that aren't installed yet don't hold core
  back; they're skipped. If the chosen core is newer than the command, that core is
  downloaded and checked like any mod (the index's sha256, the archive checks), and
  its `bin/webos-mods` runs instead, with the same command and mods and
  `MODS_NO_SELFUPDATE=1`, saying `running webos-mods 1.5.0 instead of the installed
  1.2.0`; this copy lets go of the lock first, for that run to take, and exits with its
  status. If that core can't be had (a download, the checksum, the archive checks, or
  no `bin/webos-mods` in it), this copy says why, warns `couldn't get core 1.5.0;
  running the installed 1.2.0`, and carries on with core at its own version (decided
  2026-10-13). The other commands always run the installed copy: it matches the
  installed core (lockstep), and `list`, `remove` and `help` need no network. No
  self-update with `MODS_NO_SELFUPDATE=1` (code spells it `selfupdate`) or in an
  unpublished copy. Where updates come from is never read from a saved record. A piped
  copy never self-updates: it's the version the user picked. The one-liner's
  `webos-mods` copy plays no part in it.
- Only the installed command self-updates. It recognises itself, through symlinks too
  (`readlink -f`), as `core/bin/webos-mods` next to core's `.installed`. Its helpers
  are its own core's, the installed one, which it plans with; the run it switches to
  loads its own.
- One run at a time changes a mods dir: `install`, `reinstall`, `update` and `remove`
  hold `<mods dir>/.lock` (a folder, as `mkdir` is atomic) from before they read what
  they may change until they exit; `list`, `search`, `info` and `help` don't. The
  lock's `holder` file
  names the run's pid and boot id (`/proc/sys/kernel/random/boot_id`). Another run
  stops while that process lives in this boot; a lock whose process is gone, or from
  before a reboot (pids start again), is taken over with a warning; a lock without a
  holder yet belongs to a run that's just starting, and the message says how to remove
  it if it isn't. An empty mods dir goes when the lock does, at exit.
- Install record: each installed mod has a `.installed` file (`repository`, `version`,
  `url`, `sha256`, `date` in UTC ISO 8601, as `key=value` lines). A mod is up to date
  when the version chosen is the one installed (published versions never change);
  `reinstall` installs it again, if the repository still lists that version. The record
  is for people: the command decides nothing from what it holds (since 2026-10-13, with
  one repository).
- Mods dir: `MODS_PREFIX` when set, for every run, the installed command included;
  otherwise `/media/developer/mods` (decided 2026-10-11). It must be an absolute path,
  since hooks embed it; anything else stops the run. The first install that puts core
  in says where the command is, and that new login shells have it on `PATH`. So a
  command installed elsewhere needs `MODS_PREFIX` on every run. A test install in
  another dir still uses
  the shared hook dir and root's `.profile` unless `MODS_INITD` and `MODS_PROFILE`
  are set too; accepted, no warning. Known risk, accepted by the maintainer:
  `/media/developer` is writable by every user and has no sticky bit, so a non-root
  app could rename or replace the mods folder, whose `boot` scripts root runs at
  every start.

### meta: package.json fields as `key=value` lines
- `version=MAJOR.MINOR.PATCH`: required, no prerelease tags.
- `description` (one line) and `license` (an SPDX expression, e.g. `MIT AND
  GPL-2.0-only` for bundled parts): required to publish (`publish_problem`, which
  `tools/build-repo` applies). Optional: `keywords` (words separated by commas: letters,
  digits, `-`, `_`), `homepage` (`https://` only), `author`. `meta_problem` checks
  their format when present, refuses CRLF line endings, and refuses the keys a
  repository's index adds (`name`, `file`, `sha256`, `format`).
- To publish, a meta holds only known keys, each once (decided 2026-10-13,
  `publish_problem`): `version`, `description`, `license`, `keywords`, `homepage`,
  `author`, `boot_order`, `engines.webos`, `dependencies.<mod>`, plus comments (`#` at
  the start of a line) and blank lines, so a typo like `dependency.core=` can't pass
  unnoticed. `meta_problem`, which the TV uses, stays lenient, so older commands take
  mods with newer keys. A new field goes into `publish_problem`'s list.
- `dependencies.<mod>=<npm range>`: empty means any version.
- `engines.webos=<npm range>`: the TV's webOS in LG's internal numbering, read from
  `core_os_release` in `/var/run/nyx/os_info.json` (fallback: `nyx-cmd OSInfo query
  core_os_release`). webOS 4.5 = 4.5-4.9, webOS 22 = 7.x, 23 = 8.x, 24 = 9.x. LG's
  Re:New programme moves 2022+ TVs across major versions.
- `boot_order=NN` (default 50): only the sort order of the mod's init.d hook (the
  hook name's prefix), so it matters only for mods with a `boot` script. The mod's
  developer sets it; nothing derives it from dependencies or checks it against them
  (decided 2026-10-13).
- Ranges use npm's semver syntax; decided against inventing one. Core's `satisfies` and
  `range_problem` implement `^ ~ x-ranges`, comparators, hyphen ranges, AND (space) and
  OR (`||`). They matched npm's semver on all 13,248 pairs of a one-off comparison;
  `tests/main/semver-cases.txt` (generated by `tests/main/gen-semver-cases.js`) keeps
  1,836 cases.

### core
- Implicit dependency of every mod, accepting any version unless the mod declares
  `dependencies.core`.
- Core follows semver and may drop or change helpers in a new major version. Mods that
  don't pin core may then break, hooks included, since hooks call
  `run_boot <mods dir> <mod>`; that's the mod developer's responsibility, so a mod
  that uses core's helpers should declare e.g. `dependencies.core=^1.0.0`. Hooks are
  written only when their mod is installed or updated, never rewritten in bulk.
- Core works on every TV today: it has no `engines.webos` and no `boot` script. That's
  a current fact, not a rule, so nothing enforces it (decided 2026-10-13).
- Lockstep: a given `webos-mods` only works with its own version of core (`VERSION`);
  if the repository doesn't list it, the run stops. Core
  takes that version even below the installed one (a pinned older copy), unlike other
  mods. It stages and loads that core first; if an installed mod's range excludes it,
  the run stops before changing anything. A mod that isn't installed yet can't hold
  core back; it's skipped. Because the command ships in core, it's installed, updated
  and removed with core. An unpublished copy (tests) takes the repository's newest
  core. The installed command, when it installs or updates, may choose a newer core and
  switch to that core's command (see Self-update), which then keeps to its own.
- Core is installed and updated before any other mod. It stays when the last mod is
  removed, until it's named itself (`remove core`/`self`). `install core` installs it
  on its own; otherwise a core that isn't installed yet only goes in with another mod,
  and goes again if every mod it came with failed to install, so a failed first
  install still leaves nothing behind. A core that was already there, or was asked
  for, stays.
- `PATH`: core's `install` script appends one marked line to root's `~/.profile`
  (`MODS_PROFILE` in tests), at the end because `.profile` may set `PATH` itself:
  `PATH="$PATH:<mods dir>/core/bin"  # webos-mods`. It replaces an earlier marked line;
  core's `uninstall remove` deletes it, `uninstall update` leaves it. Both only warn if
  the file can't be written. Only login shells read it; hooks call scripts by path.

### Dependency checks: install time only
- Which version of each mod goes in: see Versions, under Distribution and the command.
  Held back means the installed copy stays, or a new mod isn't installed.
- `install` changes only the named mods and the dependencies they need; `update` covers
  every installed mod, or the named ones.
- Order (decided 2026-10-13): mods go in after the mods they depend on, and come out
  before them (`dep_order` in `libmod.sh`, which `tools/build-repo` uses too). Of
  the mods free to go, the first by name goes first; `boot_order` plays no part.
- Dependency cycles are accepted, as APT/dpkg and pacman accept them (decided
  2026-10-13): a cycle's members go in together, by name, and come out together.
  `tools/build-repo` notes each cycle among the repository's mods and refuses a mod
  that depends on itself (Debian's lintian calls that a likely typo).

### Boot
- Only mods with a `boot` script get a hook, `/var/lib/webosbrew/init.d/<boot_order>-mod-<name>`,
  containing `#!/bin/ash` and `. <mods>/core/libmod.sh && run_boot <mods> <name>`.
- `run_boot` checks only `engines.webos` (an unknown version still starts), runs `boot`,
  and writes `boot.log` (`not started: ...` or `boot script failed (exit N)`). No
  boot-time dependency checks: judged too complicated for a questionable win; failures
  just get logged.
- The installer also runs `boot` once right after installing a mod.

### Lifecycle scripts (Debian-style reasons)
- Fresh install: `install install`, then `boot`.
- Update: old `uninstall update <new>`, new `install update <old>`, then `boot`.
- Removal: `uninstall remove`. The installer deletes the mod's folder and hook itself;
  `uninstall` only undoes effects outside the folder.
- A failing `install` is undone thoroughly. Fresh install: `uninstall remove`, files
  deleted. Update: the old folder is kept aside as `.<name>.old` until the new
  `install` succeeds; on failure the new version's `uninstall update <old>` runs, the
  old folder goes back, the old `install update <new>` runs, and the old version is
  restarted. Later mods in the run that need the failed one are skipped, and the run
  exits 1. A failing `uninstall` is a warning (`!!`), and the removal or update carries
  on.

### Removal
- Refused while another installed mod depends on the target (core included). Several
  targets are removed dependents first (`dep_order` reversed), core last. Core goes
  only when named.

## Planned: mod repositories (decided 2026-10-12; steps 1 to 5 done)

Why: third-party mods won't live in this repo, so they can't ship in its releases.
Distribution moves from "a release bundles every mod" to repositories of mods with
their own versions, as with APT, opkg and Kodi; prior art for the purpose: Magisk
modules. Once implemented, fold this into the sections above. "(default)" marks a
detail chosen without a question; change it freely.
- Installer: our own, with our own index format. Considered and not chosen: the TV's
  own `opkg` (0.3.6 with libsolv; `-f` for an isolated config).
- Repository: a static folder over `https://` (or `file://`): `index`,
  `<mod>-<version>.tar.gz`, later `index.sig`. Published files never change: a
  version is built once and then copied along, never rebuilt, and the pull-request
  check makes a changed mod take a new version. All versions stay listed, until their
  mod's folder is removed. The exceptions: `webos-mods`, a copy of the
  newest core's command at a stable path for the one-liner, next to immutable
  `webos-mods-<version>` copies for pinning. Pages and raw GitHub serve a fresh file a
  few minutes late (caching).
- Index format: stanzas separated by blank lines, `key=value` lines (like APT's
  `Packages`): a mod's `meta` plus `name`, `file` (relative to the index, or a full
  `https://` URL), `sha256`. First line `format=1`. New `meta` fields, package.json
  names: `description` and `license` (both required to publish), `keywords`,
  `homepage`, `author`. `license` is an SPDX expression, so a mod bundling components
  under other licences says so (`MIT AND GPL-2.0-only`) and may carry their licence
  files. Read with awk/sed (no JSON parser in busybox).
  `format=1` is the version of the index's layout, as npm's `lockfileVersion` is for
  `package-lock.json` (decided 2026-10-13). It goes up only for a change an older
  reader would misread (how stanzas are separated, what `file` or `sha256` mean, how
  values are written), never for new keys, which readers ignore, as `meta_problem`
  ignores keys it doesn't know. A reader refuses a repository whose format it doesn't
  know, and says so (`uses index format 2; update webos-mods`). The official index's
  format should hardly ever change: the self-update reads it, so a bump cuts older
  commands off from updating themselves, and their TVs need the one-liner again.
- Commands: `list` (installed, no network); `search [<word>]` (available mods,
  matching name, description and keywords; marks installed and outdated ones; all
  without a word); `info <mod>` (description, versions, dependencies, webOS range,
  homepage, repository). The index is fetched fresh on every run that needs it, no
  local cache (default). `repo add|remove|list`: postponed to version 2.0. Step 3,
  done 2026-10-13: `search` and `info`, as described under Distribution and the
  command.
- Versions: per mod, the newest version that suits this TV's webOS, whose
  dependencies are installed or planned in a version they accept, and that installed
  mods accept; chosen in dependency order, never revisited (no backtracking), and an
  installed mod is never downgraded automatically. Messages say why an older version
  was chosen (`hosts 1.3.2 installed, not 1.5.0: 1.5.0 needs core@^2`). The same
  goes for core: the self-update runs the newest core whose version every installed
  mod accepts, instead of stopping (step 4, done 2026-10-13: each installed mod at the
  version it will have after the run, so a major core and the mods that need it update
  together; see Self-update). Pre-releases stay out of the official index
  (test from a branch or a `file://` copy); versions stay `MAJOR.MINOR.PATCH`.
- Repository: the official one is built in: its GitHub Pages URL,
  `https://ashway83.github.io/webos-mods/`, stamped at publish time (a fork's build
  points at the fork). `MODS_REPOSITORY` replaces it for tests and mirrors, replacing
  `MODS_URL`; `https://` and `file://` only. `.installed` gets `repository` and
  `version` in place of `release`. Third-party repositories were planned from the
  start; they're postponed to version 2.0 (see there).
- Hosting and the one-liner: the official repository is a publishing branch in this
  repo (`gh-pages`, no shared history with `main`), served by GitHub Pages:
  `curl -fsSL https://ashway83.github.io/webos-mods/webos-mods | sh -s -- install <mod>`
  (`webos-mods-<version>` to pin). GitHub Releases are dropped; a git tag marks each
  published core version, for history and a changelog.
- Publishing: mod sources live in `mods/<name>/`; publishing is merging a pull request.
  On a pull request: the repo checks (new fields included; in `tools/build-repo`
  since step 5), shellcheck, the suites, "a changed mod has a new version" (its files
  differ from `main`'s, so its version must be higher; a git diff, no archive
  comparison), and core installed from the trial build into a fake TV (decided
  2026-10-13): the published command, stamped by `tools/build-repo`, reads the real index
  and archives, parsing every mod's stanza (any warning fails the step), while no mod's
  scripts run but core's, which writes into the fake TV. Mods' own scripts are written
  for webOS and would run as root on the runner (the hosts mod would bind-mount its
  `/etc/hosts`), so each mod's behaviour is tested by its own suite, as the hosts mod's
  is, and by review. On a merge: `tools/build-repo --from <the gh-pages checkout>` builds
  every mod whose `<name>-<version>` isn't published yet into a fresh folder, which is
  committed as the branch's new content; working from what's published rather than the
  diff makes re-runs harmless; a `concurrency:` group serialises runs.
  CONTRIBUTING.md (what a mod may do, since its scripts run as root; what reviewers
  check; version and licence rules; how publishing works) is written with this work
  (done 2026-10-13; its rules on what a mod may do are drafts for the maintainer).
- Core keeps the command (decided): core's semver describes `libmod.sh`'s helpers,
  the API mods use; a change only to the command, even a breaking one to its command
  line, is a minor or patch bump. Lockstep stays built in; the self-update means "a
  newer core in the official index", and runs that core's command after checking the
  package's sha256 (which closes the unchecked-download gap; done in step 4).
  Splitting stays possible later (a newer core drops the command while a new mod takes
  it over).
- Signing, second step: room for `index.sig` from the start; then the index is signed
  (it holds every package's sha256, as APT signs `Release`) with an ECDSA P-256 key
  kept as a CI secret, verified with `openssl dgst -sha256 -verify` (the maintainer's
  TV has `/usr/bin/openssl` 1.1.1t; no Ed25519, `gpg`, `minisign`, `signify` or
  `usign`; older webOS still to check). This protects against tampered hosting and
  mirrors, not a bad merge (review covers that). The official public key ships in
  core; key rotation accepts two keys during a changeover. Step 7, done 2026-10-13: see
  Signing, under Distribution and the command.
- Step 1 done (2026-10-12, reworked with the maintainer the same day):
  `tools/build-repo [--from <published repository>] [--url <URL>] <mods dir>
  <output dir>`, and the new `meta` fields. The output folder, which must be empty, gets
  the published archives of every mod that still has a folder (all versions; a removed
  mod's archives are left behind), plus new archives for versions not published yet;
  then the stable `webos-mods` copy and the index are written afresh. CI checks out the
  publishing branch as `--from` and pushes the output as its new content. A published
  version is never rebuilt, so archives needn't be reproducible: they keep their files'
  times, and are only normalised for safety, since root unpacks them on the TV keeping
  owner and permissions: owner 0 (not the CI runner's uid) and no group or other write
  (`--mode=go-w`). It stamps core's command with `@VERSION@` (core's version) and
  `@REPOSITORY@` (the URL; the command gets that placeholder in step 2). Bash 4+
  (`pipefail`, associative arrays, `sort -V`), GNU tar as `tar` or `gtar`. Its tests are
  the build side's 01 checks and 02 repository suites; since it never runs on a TV,
  step 2's test worlds will build their repositories with a small POSIX helper in
  `tests/main/helpers.sh`, writing the same format.
- Step 5 done (2026-10-12): `.github/package.sh`, `.github/check-mods.sh` and
  `release.yml` are gone. check-mods' checks moved into `tools/build-repo`, which
  reports every problem before stopping (in GitHub Actions also as `::error::`
  annotations) and builds nothing then. Its new `--base <git ref>`: each mod whose
  files changed in `<ref>...HEAD` (a moved file counts for both mods) needs a version
  higher than it had at `<ref>`, the way Helm's chart-testing checks charts. Core has
  to be among the mods, and `--url` is required (since 2026-10-13; until then a folder
  without core built a third-party repository). `ci.yml`'s test job (full history)
  runs shellcheck, both sides' tests and a trial build, with `--base origin/<base
  branch>` on a pull request and, on a push to `main`, `--base <the last published
  commit>`, which `gh-pages`' newest commit names (`Publish <sha>`; decided
  2026-10-13; until then the commit before the push, which forgot a failed check at the
  next push). The maintainer may push directly (default). The publish job, after a push to `main`, publishes
  only main's current tip (default; a run for an older commit would leave out mods
  added since): it builds on a worktree of `gh-pages` (created as an orphan branch on
  the first run), replaces the branch's content with the output plus `.nojekyll`,
  commits as github-actions[bot] with the source commit in the message, and pushes
  without force; then it tags the source commit `v<core version>` unless that tag
  exists (a lightweight tag, default). The stamped URL is
  `https://<owner>.github.io/<repo>` from the workflow's context (default). The
  maintainer enables Pages once (deploy from the `gh-pages` branch).
- Review of `tools/build-repo` (decided 2026-10-13). Added:
  - A mod holds files, folders and symlinks (symlinks allowed, decided 2026-10-13). A
    special file, a mod folder that's itself a symlink (its archive would hold no
    files), and `.installed` or `boot.log` of any kind, which the TV writes in a mod's
    folder as root, are problems, so pull requests carrying them fail.
  - Publishing's stricter meta rules (see meta).
  - No `boot_order` rule any more: it only sorts hooks. A dependency cycle gets a note
    naming its mods and the one that goes in first (by `dep_order`, the TV's order);
    a mod that depends on itself is a problem.
  - Mods' scripts are checked with shellcheck as dash scripts (`--shell=dash`,
    whatever their first lines say, since the TV runs them with its `sh`). This
    replaces the `sh -n` parse check, which let bash-only syntax through, so
    shellcheck is a build-time dependency.
  - Problem messages show line breaks in names as `\n`, and annotations escape `%`, so
    no folder name can start a GitHub workflow command.
  - `help`, `-h` and `--help` print the usage on stdout (exit 0); no arguments, or not
    two folders, print it on stderr (exit 1); unknown options and missing values name
    the problem. `--base` checks that git is installed. An output path that's a file is
    reported as such.
  Done with step 2 (decided 2026-10-13):
  - Stamping: `--url` allows only the characters the command accepts in a repository
    URL (letters, digits, `. _ ~ : / % + @ -`), which can't break the `sed`
    replacement or the single-quoted string, and the build stops if the stamped
    command still holds an `@PLACEHOLDER@`. No parse check of the stamped command:
    it's the unstamped one, already checked with shellcheck, plus two values that
    can't change its syntax once the URL is checked.
  Done after the implementation (2026-10-13): the version check on a push compares
  with the last published commit, not the commit before the push, which let a change
  whose check failed be forgotten by the next push, then skipped as "published already".
  Left as is: archives taken over with `--from` aren't checked against the old index
  (they were checked when published).
- Step 2 decisions (2026-10-13):
  - Repository: the official one by default, `MODS_REPOSITORY` in its place. (Step 2
    first read a list, `MODS_REPOSITORIES`; several repositories are postponed to
    version 2.0.)
  - Self-update: from the repository's stable `webos-mods` copy, comparing plain
    versions. Step 4 made it pick the newest core every installed mod accepts and
    check its sha256 against the index.
  - Unpacking: an archive must hold only its mod's folder (`<name>/...`): files,
    folders and symlinks, no `..`, nothing beneath a symlink (which would write
    through it), and no `.installed` or `boot.log`; otherwise it isn't unpacked.
  - Unchanged: the same version installed (published versions never change).
    Downloads are checked against the index's sha256;
    `.installed` holds `repository`, `version`, `url`, `sha256` and `date`.
  - Choosing versions: start at the newest, step down where forced (decided 2026-10-13;
    see Versions).
- Step 2 done (2026-10-13): the command reads the repository (see Distribution and the
  command: One repository, Versions, Downloads, Self-update, Install record); `MODS_URL`,
  `SHA256SUMS`, `releases/latest` and the release-tag comparison are gone, and so is
  core's reinstall with every release. The TV side's test worlds publish a repository
  with `publish` (`tests/main/helpers.sh`), which writes `tools/build-repo`'s format in
  POSIX sh. CI installs core from the trial build into a fake TV (see Publishing),
  which tests the command against `tools/build-repo`'s real output, not the helper's;
  simulated on the maintainer's TV. Left for later: the "revisit after the
  implementation" items above. No installs existed, so no migration.

## Postponed to version 2.0: several repositories (decided 2026-10-13)

Version 1 reads one repository. Step 2 had implemented a list of them, which was taken
out again; what was planned or built, to pick up for 2.0:
- Third-party repositories: `repo add <url> [<key file>]`, `repo remove <url>`,
  `repo list`, stored in `<mods dir>/.repositories` (one `<url> [<key file>]` per
  line); `MODS_REPOSITORIES`, a list, in its place for tests and mirrors. Adding a
  repository trusts its mods with root, so it's explicit.
- Which repository a mod comes from: a new install from the first that has it, so
  official mods can't be shadowed; an installed mod keeps updating from the one in its
  install record (`repository=` in `.installed`, which version 1 already writes, for
  people). A repository other than the official one that can't be read, or whose
  index is of another format, is left out with a warning.
- Dependencies may cross repositories. Open: cycles across repositories, which no
  build can see.
- `tools/build-repo` for third-party repositories: a folder without core, whose
  dependencies on mods it lacks get a note rather than an error, and which needs no
  `--url`.
- Signing: a third-party repository's public key comes with `repo add`.

## Environment overrides

| Variable | Purpose |
| --- | --- |
| `MODS_REPOSITORY` | The repository's URL (`https://` or `file://`; letters, digits and `. _ ~ : / % + @ -`), instead of the official one stamped in. For mirrors and tests; anything invalid stops the run |
| `MODS_PREFIX` | The mods dir, for every run (an absolute path; default `/media/developer/mods`); a test install elsewhere still shares `MODS_INITD` and `MODS_PROFILE` unless they're set too |
| `MODS_INITD` | Hook dir (tests). Homebrew Channel counts as present if the dir holding it exists |
| `MODS_NO_SELFUPDATE=1` | The installed command keeps to its own core, instead of switching to a newer core's command |
| `MODS_PROFILE` | Replaces root's `~/.profile`, where core puts the command on `PATH` (tests) |
| `MODS_WEBOS=x.y.z` | Overrides the detected webOS; also an escape hatch past `engines.webos` |
| `MODS_WEBOS=unknown` | Test-only: acts as if the version can't be read |
| `MODS_HOSTS_FILE` | Target of the hosts mod (tests) |
| `MODS_TEST_OFFLINE=1` | Skips the one test that needs internet access |

## Testing

- Two runners, each running its suites in order, or only those whose file names contain
  a given word: `tests/main/run [word...]` for the TV side (the command, core,
  hooks, mods: as root, on the TV or in CI under busybox), and `tests/tools/run
  [word...]` for the build side (what runs in CI and on developer machines, never a TV;
  no root needed). The build runner, its suites and their helpers are bash; it checks
  for bash 4+, GNU tar (as `tar` or `gtar`), git, shellcheck and openssl (LibreSSL, as
  on a Mac, will do) up front and stops without them, so nothing skips. Each side has its own folder (decided 2026-10-12:
  `tests/main/`, and `tests/tools/`, named after `tools/`, as `repo` would clash with
  the `repo` command and this git repo) with its own helpers, which its suites source
  first: `tests/main/helpers.sh` (ash) and `tests/tools/helpers.sh` (bash); neither
  uses the other's. Only shUnit2 is shared.
- shUnit2 2.1.8 ships with the repo as `tests/shunit2`, unmodified (Apache 2.0, licence
  header kept); the tests use only that copy, never one on `PATH`. To upgrade, replace
  the file with a tagged release from https://github.com/kward/shunit2.
- TV-side suites, in order: 01 environment, 02 core, 03 ranges, 04 safety, 05 install,
  06 dependencies, 07 scripts, 08 boot, 09 remove, 10 command, 11 search (search and
  info), 12 hosts mod. Build-side
  suites: 01 checks (what `tools/build-repo` checks, and that the build side's
  scripts parse), 02 repository (what it builds). Add new tests to the suite and
  position where they belong logically.
- Shell options: the build runner, like `tools/build-repo`, runs with
  `set -euo pipefail`; the build suites with `set -u` only (decided 2026-10-12). Not
  `-e`: shUnit2 2.1.8 doesn't support it (its assertions run conditions that may be
  false as plain commands, so the first one ends the suite, and the report still counts
  every test as run), and the tests run failing commands on purpose before asserting on
  `$?`. `pipefail` would do nothing there, as no test checks a pipeline's status. None
  of these options changes when bash sets `$?` (next point).
- In the build side's bash suites, check exit statuses with `assert_status <expected>
  $?` (`tests/tools/helpers.sh`), which also shows the run's output when wrong, and
  never put `$?` after a command substitution in the same command. Bash (every version
  in its default mode, like ksh93 and zsh) makes a command substitution's status `$?`
  as soon as it ends, so `assertEquals "exit: $(output)" 0 $?` tests `cat`'s status and
  always passes. dash and busybox ash keep the previous command's status until the
  command ends, which POSIX.1-2024 made the rule (Austin Group interpretation 1150,
  2019: `$?` comes only from pipelines run in the current shell environment, and a
  command substitution runs in a subshell); bash follows it from 5.3 on, in POSIX mode
  only. Three TV-side asserts (in 08 and 10) rely on it, which holds under busybox.
- TV side: each test runs in a throwaway world under `/tmp` (dummy repo, the repository
  published from it in `$WORLD/pub`, a fake TV with its own `.profile`, exported as
  `MODS_PROFILE`). Helpers live in `tests/main/helpers.sh` (`new_world`, `mod`,
  `publish`, `write_index`, `sign_index`, `rehash`, `installer`, `webos_mods`, `boot`,
  ...). `publish` adds the mods' versions not published yet, copying on top as CI does,
  so a test that changes a mod gives it a new version. A world signs its index with its
  own key (`key.pem`, made on first use), and the commands it publishes trust the keys
  in its `trusted.pem` instead of the official one (`trust`); a test that changes the
  index signs it again (`write_index` and `rehash` do), unless the signature is what
  it tests. `installer` runs the real one-liner through `curl file://`; `webos_mods`
  runs the installed command; both read the world's repository, stamped into its
  command (`TV_REPOSITORY` sets `MODS_REPOSITORY` instead). Build side: a world is
  just a dummy repo with a copy of core, and a signing key, `key.pem`
  (`tests/tools/helpers.sh`: `new_world`, `mod`, `output`, `assert_status`, ...).
- Scope (decided): test our code, not Homebrew Channel or webOS. For example, the suite
  doesn't use `run-parts`; `boot` runs our hooks directly.
- Platforms (decided): the TV side's tests run as root on Linux only (CI under busybox,
  and the TV). Not on macOS: no skips or alternate branches for it (no `/proc/mounts`,
  BSD tools). The build side's run in CI and on developer machines, a Mac included
  (`brew install bash gnu-tar shellcheck`).
- On the TV, from the folder holding `webos-mods` (the tar options leave out macOS
  metadata, which busybox tar warns about):
  `COPYFILE_DISABLE=1 tar --no-xattrs --exclude .DS_Store --exclude .git -cf - webos-mods | ssh root@TV 'tar -xf - -C /tmp && /tmp/webos-mods/tests/main/run'`
- Repo checks and a trial build (bash 4+, GNU tar, shellcheck and openssl; the output
  folder must be empty or absent), signed with a throwaway key:
  `openssl ecparam -name prime256v1 -genkey -noout -out /tmp/trial-key.pem`, then
  `tools/build-repo --url https://ashway83.github.io/webos-mods --key /tmp/trial-key.pem mods /tmp/repo`,
  plus `--base main` for the version check.
- Check new tests by breaking the code they cover and confirming they fail.

## Status

- TV side: all 164 tests pass on the maintainer's TV with shUnit2 2.1.8 and BusyBox
  1.29.3 (2026-10-13, after step 7); one skips there, the nyx-cmd fallback, which a
  real TV never reaches. Breaking any of 32 behaviours of the repository-based command,
  5 of the dependency order, 29 of search and info, 16 of the step 4 self-update, or 7
  of the signature check fails one there (the self-update's own `set -e` in its
  subshell only guards failures no test can cause, such as a disk error while
  unpacking). The TV's OpenSSL 1.1.1t verifies signatures made with OpenSSL 3.6 and
  LibreSSL 3.3. Build side: all 48 pass on the maintainer's Mac (bash 5.2, GNU tar 1.35
  as `gtar`, git 2.54, shellcheck 0.10, OpenSSL 3.6, and LibreSSL 3.3 too), none
  skipped, and breaking any of 63 behaviours of `tools/build-repo` and
  `publish_problem`, or 8 of its signing, fails one (2026-10-13). CI's core install
  step ran on the TV against a real trial build, signed (after step 7). The TV side's
  suites haven't run under CI's busybox (Ubuntu's) yet; the TV's own `tar` is GNU tar,
  so busybox tar's listings are untested.
- Never run yet: `ci.yml` on GitHub. Its steps' scripts ran locally against a bare
  repository standing in for GitHub: the first publish, a re-run, a new mod version, a
  run for an older commit, the tag, and the version check on a push.
- Maintainer's TV: webOS 6 (`core_os_release` 6.5.3-47, kisscurl-koli), aarch64, GNU
  tar 1.17.
- Not handled yet: a commit interrupted by power loss or a full disk.
- The official signing key (made 2026-10-13): its public key is in `KEYS`, and the
  private key waits in `~/webos-mods-signing-key.pem` on the maintainer's Mac (mode
  600, outside the repo) until it becomes the `publishing` environment's `SIGNING_KEY`
  (with deployment branches limited to `main`); then that file is deleted. A build
  signed with it was read by the shipped command on the TV, and refused once changed.
- Git (2026-10-13): this folder is a git repository, `main`, with a `.gitignore` for
  `.DS_Store` (Finder's files would count as changes to the mods holding them); the
  maintainer's test folders `out/` and `out2/` are kept out in `.git/info/exclude`.
  Remote `beta`: `https://github.com/ashway83/webos-mods-beta` (public, as free-plan
  Pages and environments need), to test CI, publishing and Pages before going live as
  `webos-mods`; its `publishing` environment (main only) holds the official key, as
  the live one will (decided 2026-10-13: the beta runs exactly what goes live).

## Open questions for the maintainer

- Keep `MODS_WEBOS=unknown` (test-only) or drop it together with its three tests?
  (Suggested 2026-10-13: keep; it's the only way the tests reach the unknown-webOS
  branches of install, boot and search.)
- `test_curl_reaches_github_over_https` checks the TV's curl and CA certificates rather
  than our code; keep it? (Suggested: keep, aimed at `github.io`, which the one-liner
  and the command use.)
- Mod repositories are decided (see "Planned: mod repositories"); steps 1 to 5 and 7
  are done (2026-10-13), and CONTRIBUTING.md; left: folding the plan into the sections
  above, and going live.
- The `hosts` mod's `blocklist` is empty; it's only an example so far. Suggested
  2026-10-13, to check against the TV's DNS traffic first: LG's ad servers
  (`ad.lgsmartad.com`, `info.lgsmartad.com`, and their `us.`/`eu.` variants), telemetry
  (`ngfts.lge.com`, `aic-ngfts.lge.com`), the viewing-data partner (`alphonso.tv`); not
  the update servers, which Homebrew Channel blocks itself when asked to.

## Working with the maintainer

- Prefers established conventions over invented ones (npm semver, package.json fields,
  Debian maintainer-script reasons).
- Prefers simple designs; rejected boot-time dependency checks and bulk hook rewriting
  as not worth their complexity.
- When asked a question, answer it before changing code, and confirm design changes.
