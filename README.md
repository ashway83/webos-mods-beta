# webos-mods

Mods for a rooted LG webOS TV (Homebrew Channel). The first time, run on the TV as root:

    curl -fsSL https://ashway83.github.io/webos-mods/webos-mods | sh -s -- install hosts

That also installs the `webos-mods` command, and adds it to `PATH` in root's
`~/.profile` for new login shells. Afterwards:

    webos-mods install <mod>...     install mods, or update them if a newer version suits
    webos-mods reinstall <mod>...   install them again, even if up to date
    webos-mods remove <mod>...      run their uninstall scripts and delete them
    webos-mods update [<mod>...]    update installed mods (all of them if none are named)
    webos-mods list                 show this version, the TV's webOS and the installed mods
    webos-mods search [<word>]      show the mods available (all, or those matching a word)
    webos-mods info <mod>           show a mod's details and every version available
    webos-mods help                 show the commands

Mods come from the official repository, `https://ashway83.github.io/webos-mods/`, which
lists every published version of every mod. `search` shows, for each mod whose name,
description or keywords hold the word (in any case), the newest version that suits
your TV and its description, and marks the mods that are installed, can be updated, or
need another webOS:

    hosts            1.1.0    Adds a blocklist to /etc/hosts [installed 1.0.0, update available]

Install and update leave mods that are up to date alone; `reinstall` installs them
again. `self` stands for core, which holds the
command: `webos-mods update self` updates just that, and the command stays when the
last mod goes until `webos-mods remove self`.

When installing or updating, the command updates itself: it takes the newest core that
every installed mod accepts (at the version that mod will have afterwards, so `update`
moves core and the mods that need a new core together) and, if that's newer than
itself, runs that core's `webos-mods` instead and says so. That core is downloaded and
checked like any mod; if that fails, the installed copy carries on and says so. The
other commands always run the installed copy; `list` and `remove` need no network.
`MODS_NO_SELFUPDATE=1` turns the self-update off. To pin a version, pipe
`webos-mods-<version>` instead of `webos-mods`: each copy works with its own version
of core. Mods go to `/media/developer/mods`;
`MODS_PREFIX=<absolute dir>` puts them elsewhere, and then has to be set for every run,
the command's too. `MODS_REPOSITORY=<URL>` replaces the official repository, for a
mirror or tests.

The repository's index is signed, and lists every archive's sha256. The command uses
nothing in it unless the signature (`index.sig`) verifies with the public key written in
the command, so a tampered mirror or download is refused. Otherwise it stops and says
why, e.g. `can't verify the signature of <url>/index: openssl not found`; the TV needs
`openssl`. A mirror copies `index.sig` along with the rest.

## Writing a mod

Create `mods/<name>/` (letters, digits, `-`, `_`; `self` is taken). The folder is
installed to `/media/developer/mods/<name>/` on the TV. It holds files, folders and
symlinks (no device files or pipes), and not `boot.log` or `.installed`, which the TV
writes there.

- `meta` - package.json fields as `key=value` lines. `version` is required, and to
  publish, a `description` and a `license`:

      version=1.2.0
      description=Blocks ads by adding a blocklist to /etc/hosts
      license=MIT
      keywords=ads,dns
      homepage=https://github.com/you/your-mod
      dependencies.hosts=^1.0.0
      dependencies.core=^1.1.0
      engines.webos=>=4.5 <8
      boot_order=60

  `license` is an SPDX expression: a mod that bundles parts under other licences says
  so (`MIT AND GPL-2.0-only`) and can carry their licence files. `keywords` are words
  separated by commas, for search; `homepage` must be `https://`; `author` is optional.
  To publish, use only these keys, each once; lines starting with `#` are comments.

  Ranges use npm's syntax: `^1.2.3`, `~1.2`, `1.x`, `>=1.2 <2`, `1.0 - 1.4`, `a || b`.
  Versions are plain MAJOR.MINOR.PATCH, without prerelease tags. `engines.webos` uses
  LG's internal numbering from `core_os_release` in `/var/run/nyx/os_info.json`:
  webOS 4.5 = 4.5-4.9, webOS 22 = 7.x, 23 = 8.x, 24 = 9.x. Core is an implied
  dependency of every mod, with any version unless you declare a range (see below).
  `boot_order` (default 50) only matters for a mod with a `boot` script: its Homebrew
  Channel hook is `/var/lib/webosbrew/init.d/<boot_order>-mod-<name>`, and hooks start
  in name order. It doesn't affect the install order: mods go in after the mods they
  depend on.
- `install` - optional; one-time setup outside the mod's folder (a default config
  elsewhere, a persistent setting). Runs once when the mod is put in place, before its
  first `boot`: `install install` on a fresh install, `install update <version>` when it
  replaces another version (usually older; newer when a failed update is being undone).
  If it fails, the attempt is undone: see below.
- `boot` - optional. A mod with one gets a hook, which runs `boot` at every startup if
  the TV's webOS is within `engines.webos`; it also runs once right after install. Keep
  it quick and idempotent, and background anything long-running. `D=${0%/*}` gives you
  the mod's folder; output goes to `boot.log` there.
- `uninstall` - optional; undo whatever `install` and `boot` did outside the mod's
  folder (unmount, restore patched files, stop processes). `uninstall remove` when the
  mod goes away, `uninstall update <version>` when another version takes over, so data
  you keep outside the folder can survive updates. It runs before the folder is
  deleted, so it can use the mod's own files, and it should cope with a half-done
  `install`. The installer deletes the folder and the hook itself.

### Lifecycle

    fresh install   install install, then boot
    update          old uninstall update <new>, new install update <old>, then boot
    removal         uninstall remove, then the folder and hook are deleted

The old folder is kept aside until the new version's `install` succeeds. If `install`
fails, the attempt is undone: a fresh install gets `uninstall remove` and its files
deleted; an update gets the new version's `uninstall update <old>`, then the old version
is put back with `install update <new>` and started again. Mods that needed the failed
one are skipped, and the run ends with an error. A failing `uninstall` gets a warning, and
the removal or update carries on and counts as done (exit status 0). The same goes for
mods skipped or held back by their ranges: warnings, not errors.

## How dependencies are checked

Only at install time. Every mod in a run starts at its newest version that suits the
TV's webOS, never below its installed version. Then a version steps down to the next
older one wherever

1. another mod that will be installed afterwards refuses it, or
2. what it depends on won't be installed afterwards in a version its range accepts.

When a mod and one of its dependencies clash, the dependency steps down first, so
`install foo` keeps an installed dependency at a version foo accepts. The checks repeat
until nothing changes. A mod that runs out of versions is held back: an installed copy
stays as it is, and a new mod isn't installed. The output says why a newer version
didn't go in, e.g. `foo 2.0.0 not installed, 1.0.0 instead: it needs bar@^2, but bar
would be 1.5.0`. Core is the exception: it's always the version of the command that
runs (the installed command picks the newest core it can and switches to that core's
command, see above), and a mod that isn't installed yet can't hold it back; it's
skipped instead. Nothing is remembered between runs: a version passed over goes in
once nothing holds it back.

`install` changes only the mods you name and the dependencies they need; `update` brings
every installed mod up to date, or only the ones you name. Mods go in after the mods
they depend on, and come out before them. Mods that depend on each other (a cycle) go
in and come out together, by name, as with APT and pacman. A mod can't be removed while
another installed mod depends on it.

At boot, hooks don't look at dependencies. If a webOS upgrade takes a mod outside its
`engines.webos`, its hook skips it and says so in its `boot.log`; mods that depend on it
may then fail and log their own errors. `list` shows both.

## core

`mods/core/libmod.sh` holds the helpers shared by the installer, the hooks and mods
(`. "${0%/*}/../core/libmod.sh"` from a mod's scripts), including an npm-compatible
`satisfies <version> <range>`. It follows semver: a version that drops or changes a
helper is a new major version. If your mod uses core's helpers, declare the core it
was written for, e.g. `dependencies.core=^1.4.0`. A mod that declares nothing accepts
any core: it normally works, but a backward-incompatible core version can break it,
its boot hook included (the hook calls core's `run_boot`). Pin core if that matters.

Core also holds the `webos-mods` command itself (`bin/webos-mods`), and `install` and
`uninstall` scripts that add it to and remove it from `PATH` in root's `~/.profile`. A
given `webos-mods` only ever works with its own version of core. It installs that core
before anything else, and if an installed mod needs another one, it stops before
changing anything and names that mod (`update` usually resolves it). Core stays when
the last mod is removed; `webos-mods remove self` removes it, and the command with it.

## Shell and tests

Everything that runs on the TV is written for busybox ash: POSIX sh plus `local`, without
busybox's optional bash-like extensions (`[[ ]]`, `${var/a/b}`, `${var:1:2}`).

`tests/main/` holds the shUnit2 suites for what runs on the TV, run in this order by
`tests/main/run` (as root):

1. environment: every script parses, and curl does what webos-mods needs
2. core: the helpers in `mods/core/libmod.sh`
3. ranges: npm range matching, against ~1,800 answers from npm's own semver package
4. safety: refusing to run, broken or tampered downloads, bad input
5. install: what goes in, in which order, with which hooks; updates
6. dependencies: the two checks, what gets pulled in or left out, core's lockstep
7. scripts: when install and uninstall run, what they're told, undoing a failed install
8. boot: what the installer's hooks do when started: the webOS guard, logging
9. remove: what can be removed, in which order, and what's left afterwards
10. command: the command line, the installed command's `PATH` line, and self-update
11. search: what `search` and `info` show, and that they change nothing
12. hosts mod: the example mod's bind mount, pointed at a temp file

`tests/tools/` holds the build side's suites, for what runs in CI and on developer
machines, run by `tests/tools/run` (no root needed; it needs bash 4+, GNU tar,
as `tar` or `gtar`, git, shellcheck and openssl, so on a Mac
`brew install bash gnu-tar shellcheck`):

1. checks: what `tools/build-repo` checks before it builds, and that the build side's
   scripts parse
2. repository: what `tools/build-repo` builds

Each test works in a throwaway folder under `/tmp` with a dummy repo, the repository
published from it and a fake TV, so nothing else is touched. shUnit2 2.1.8 ships with the repo as
`tests/shunit2`, so there's nothing to install.

CI runs the TV side's suites under busybox, and the build side's with bash and GNU tar,
on every pull request and push to `main`. To run the TV side's on the TV, from the
folder holding `webos-mods` (the first line leaves out macOS metadata that busybox tar
would warn about):

    COPYFILE_DISABLE=1 tar --no-xattrs --exclude .DS_Store --exclude .git -cf - webos-mods |
        ssh root@TV 'tar -xf - -C /tmp && /tmp/webos-mods/tests/main/run'

`tests/main/run boot hosts` runs only the suites whose names contain those words, and
`MODS_TEST_OFFLINE=1` skips the one check that needs internet access.

## Publishing

Mods are published from `main`: merging a pull request publishes the mods it adds or
changes. On every pull request and push to `main`, CI runs shellcheck, both sides'
tests, and `tools/build-repo`, which checks every mod and reports all it finds: its
name and `meta` (a description and a license included), that its scripts are clean
for shellcheck as dash scripts (the TV runs them with its `sh`), that
the mods it depends on are in the repo in a version its range accepts (a cycle gets a
note; a mod can't depend on itself), and that a mod whose files changed has a higher
version than before. Then the command it builds installs core from that build into a
fake TV, reading every mod's stanza the way a TV would; mods' own scripts aren't run in
CI, only tested by their own suites. After a push to `main`, CI builds the repository
on top of the `gh-pages` branch and commits it there: published archives stay exactly
as they are, each new version gets one, and the `index` lists them all. It signs the
index with the key held by the repository's `publishing` environment, whose public key
is written in `webos-mods`, and first checks that the newest published command accepts
it. GitHub Pages serves the branch at `https://ashway83.github.io/webos-mods/`, and a
git tag `v<version>` marks each published core version. To run the checks locally
(bash 4+, GNU tar, git, shellcheck and openssl), sign with a throwaway key:

    openssl ecparam -name prime256v1 -genkey -noout -out /tmp/trial-key.pem
    tools/build-repo --url https://ashway83.github.io/webos-mods --key /tmp/trial-key.pem \
        --base main mods /tmp/repo
