# Contributing

webos-mods publishes mods for rooted LG webOS TVs. A mod's scripts run as root on the
TV of everyone who installs it, so every mod is held to a simple standard: it does what
its description says, nothing else, and it can be undone. This page says what that
means in practice, how to check a mod before sending it, what reviewers look at, and
how a merged mod reaches TVs.

## Sending a mod

1. Fork the repository and add your mod as `mods/<name>/` (letters, digits, `-` and
   `_`; `self` is taken). The README's [Writing a mod](README.md#writing-a-mod) says how
   a mod is put together: its `meta` and its `install`, `boot` and `uninstall` scripts.
2. Check it, and try it on your own TV (see [Checking a mod](#checking-a-mod)).
3. Open a pull request. CI runs shellcheck, the tests and a trial build of the whole
   repository, which checks every mod; then a maintainer reviews it.
4. Once it's merged, it's published (see [How publishing works](#how-publishing-works)).

To change a mod, edit its folder and raise its `version`.

## What a mod may do

- **Only what its description says.** The `description` in `meta` is what people
  agree to when they install the mod.
- **Ship all its code.** Everything a mod runs comes in its folder, where review sees it
  and the repository's signed index vouches for it. A mod doesn't download and run
  scripts or programs, at install, at boot or later. Data it fetches at run time (a
  blocklist, say) is fine if its description says what and from where, it comes over
  `https://`, and it never runs as code.
- **Keep changes reversible.** A mod changes nothing outside its folder except from its
  `install` and `boot` scripts, and its `uninstall` script undoes all of it. System
  files are replaced with bind mounts, not edited. Never write to the TV's partitions
  themselves (kernel, root file system, tvservice): that bricks TVs.
- **Leave room for others.** Don't touch other mods' folders, core, the hooks
  webos-mods writes, or Homebrew Channel's files. When you bind-mount over a file that
  something else may mount over too (Homebrew Channel does it with `/etc/hosts` when
  it blocks system updates), build on the file as you find it, and take off only your
  own mount.
- **No tracking.** A mod doesn't collect or send anything about the TV or the people
  using it.
- **Be quick at boot.** `boot` runs at every start: keep it short and safe to run
  twice, and start anything long-running in the background.
- **Be redistributable.** Your own work, or parts whose licences allow redistribution,
  stated in `license` as an SPDX expression (`MIT`, or `MIT AND GPL-2.0-only` for a mod
  that bundles GPL parts), with those parts' licence files included. No LG firmware,
  binaries or other files that aren't free to share.

## Versions

- `version` is `MAJOR.MINOR.PATCH`, following [semver](https://semver.org); no
  pre-release tags.
- Any change to a mod's files needs a higher version, and CI checks that against
  `main`. A published version never changes: once merged, it stays in the repository,
  and a fix is a new version.
- Removing a mod's folder stops publishing it: its archives leave the repository at the
  next publish. Copies already installed stay on TVs until people remove them.
- If your mod uses core's helpers (`libmod.sh`), declare the core it was written for,
  e.g. `dependencies.core=^1.0.0`, since a new major version of core may change them.
- `engines.webos` is the range of webOS versions the mod works on, in LG's internal
  numbering (see the README).

## Checking a mod

The build side runs on Linux or a Mac, with bash 4+, GNU tar, git, shellcheck and
openssl (on a Mac: `brew install bash gnu-tar shellcheck`). Its tests, then a trial
build of the repository:

    tests/tools/run
    openssl ecparam -name prime256v1 -genkey -noout -out /tmp/test-key.pem
    tools/build-repo --url file:///tmp/repo --key /tmp/test-key.pem --base main mods /tmp/repo

The trial build checks every mod, as CI does: its name, its `meta`, its scripts
(shellcheck, as dash scripts, since the TV runs them with busybox), its dependencies,
and with `--base main`, that a changed mod has a higher version. It signs the trial
repository with a throwaway key, as the real key only lives in CI.

To try your mod on your TV the way people will get it, copy that repository over with a
copy of the command that trusts your throwaway key (the published command only trusts
the official one), and install into a mods folder of its own, so that your own
installation and boot hooks are left alone:

    openssl pkey -in /tmp/test-key.pem -pubout -out /tmp/test-key.pub
    awk -v keys=/tmp/test-key.pub -v q="'" '
        $0 == "KEYS=" q { print; while ((getline line < keys) > 0) print line; skip = 1; next }
        skip && $0 == q { skip = 0 }
        !skip { print }' /tmp/repo/webos-mods >/tmp/repo/webos-mods-test
    scp -r /tmp/repo root@<TV>:/tmp/
    ssh root@<TV> 'mkdir -p /tmp/try/hbc && MODS_PREFIX=/tmp/try/mods \
        MODS_INITD=/tmp/try/hbc/init.d MODS_PROFILE=/tmp/try/profile \
        sh /tmp/repo/webos-mods-test install <mod>'

Your mod's scripts run for real, so what they do (a bind mount, say) is real until you
remove the mod the same way (`... sh /tmp/repo/webos-mods-test remove <mod>`) or
reboot, which also clears `/tmp`.

## What reviewers check

- The description matches what the scripts do, and nothing runs that it doesn't cover.
- All code is in the mod's folder; any data fetched at run time is described and comes
  over `https://`.
- `uninstall remove` undoes everything `install` and `boot` did outside the folder, and
  a failed `install` leaves nothing behind.
- `boot` is quick, safe to run twice, and puts long-running work in the background.
- Nothing touches other mods, core, Homebrew Channel or the TV's partitions; bind
  mounts build on the file as found and take off only their own.
- `meta`: a version raised for any change, sensible dependency and webOS ranges, and a
  licence that covers everything the mod holds.
- CI is green: shellcheck, the tests, and the trial build's checks.

## How publishing works

After a merge to `main`, CI builds the repository on top of what's published so far:
published archives stay exactly as they are, each new version gets an archive of its
own, and the index that lists them all is signed with the repository's key. GitHub Pages
then serves it at `https://ashway83.github.io/webos-mods/`. TVs pick up a new version
the next time someone runs `webos-mods install` or `webos-mods update` there. A git
tag, `v<version>`, marks each published version of core.

The repository's own code (core, `tools/`, the tests) is under the MIT License (see
`LICENSE`); each mod is under the licence its `meta` states.
