# Handoff — PS Pro Tools Plug-In Permissions

**Date:** 2026-09-08
**Repo:** `/Users/nick/Documents/code/ps-pt-plugin-permissions` (not a git repo yet)
**Status:** Feature-complete, builds clean, logic unit-tested. **Never installed on a
real machine.** End-to-end install/login/uninstall verification is the next task.

---

## 1. What was asked for

Verbatim requirement from the user:

> A script which runs on any macOS system (Monterey onwards) at login of any user
> and sets completely open permissions on the following folders:
> `/Library/Application Support/Avid/Audio/Plug-Ins`,
> `/Library/Application Support/Avid/Audio/Plug-Ins (Unused)`.
> The script should be packaged to run invisibly in the background, and can be
> easily removed if there is a problem. No permissions, no ownership.

Interpretation applied (confirm with the user if it matters):

- "Completely open permissions" → `chmod 777`, applied recursively.
- "No permissions, no ownership" → do not gate access on either, i.e. set mode
  `777` **and leave ownership alone**. No `chown` anywhere in the codebase. If the
  user actually meant "also `chown` to something permissive", that is a change.
- ACL stripping (`chmod -RN`) was added beyond the literal ask, because an ACL
  overrides mode bits and is the most common reason a folder that reads as `777`
  still refuses writes. Remove it if the site relies on ACLs there.
- Login is the **only** trigger, by explicit user instruction (2026-09-08): there
  must be no watcher that live-changes permissions. An earlier revision watched
  the plug-in folders and self-healed them mid-session; that was removed. The
  daemon also has `RunAtLoad` false so nothing fires at boot. Do not add either
  back without asking.

## 2. Design and why

`/Library` is root-owned, so the `chmod` must run as root. A LaunchAgent runs as
the logged-in user and therefore **cannot** do this job. A LaunchDaemon runs as
root but `RunAtLoad` fires at boot, **not** at login. Neither alone satisfies
"at login of any user, with root privileges".

Resolution — two jobs, agent pokes daemon:

| Job | Label | Runs as | Fires on |
| --- | --- | --- | --- |
| LaunchDaemon | `com.pictureshop.ptpluginperms.daemon` | root | `login.trigger` modified — nothing else |
| LaunchAgent | `com.pictureshop.ptpluginperms.agent` | each logged-in user | login (`RunAtLoad`) |

Flow: user logs in → agent runs `login-trigger.sh` as that user → touches
`/Library/Application Support/PictureShop/PTPluginPerms/login.trigger` → daemon's
`WatchPaths` sees it → daemon runs `set-plugin-perms.sh` as root → `chmod 777`.

The trigger directory is mode `1777` (sticky, world-writable) so any user can
touch the file; the trigger file itself is `666`. That directory is the only
world-writable thing this project creates outside the target folders.

The daemon's `WatchPaths` contains that trigger file and nothing else. The
plug-in folders are **not** watched, and `RunAtLoad` is false, so the only thing
that ever causes a permission change is a login. Consequence to be aware of: a
plug-in installed mid-session keeps whatever modes its installer wrote until the
user logs out and back in. That is the requested behaviour, not a bug.

### Non-obvious detail: the idempotency guard

`set-plugin-perms.sh` only chmods entries that are **not already** `777`:

```sh
find "$target" ! -perm 777 -exec chmod 777 {} +
```

Keep this. It is what makes a no-op login run write nothing at all, and it is
also the guard that made the removed folder watch safe — `chmod` bumps ctime and
launchd `WatchPaths` uses kqueue vnode events that include `ATTRIB`, so an
unconditional `chmod -R` under a folder watch self-retriggers into an infinite
loop. With folder watching gone that loop is no longer reachable, but if anyone
ever reinstates a folder watch against instructions, this guard is the only thing
standing between them and a runaway daemon. `ThrottleInterval 10` is a backstop,
not the fix.

Same reasoning applies to the ACL branch: it only runs when `ls -lde` actually
shows ACL entries.

Note `-perm 777` on BSD `find` means *exactly* `777`, which is what is wanted
here. GNU-style `-perm /777` semantics differ; macOS `find` is BSD.

## 3. Files

```
build.sh                                              builds + optionally signs the pkg
README.md                                             user/operator-facing docs
HANDOFF.md                                            this file
payload/                                              pkg payload, installs to /
  usr/local/libexec/pictureshop/
    set-plugin-perms.sh                               worker, runs as root
    login-trigger.sh                                  login poke, runs as user
    uninstall.sh                                      full removal, shipped on-disk
  Library/LaunchDaemons/com.pictureshop.ptpluginperms.daemon.plist
  Library/LaunchAgents/com.pictureshop.ptpluginperms.agent.plist
scripts/postinstall                                   pkg postinstall, loads both jobs
build/PSPTPluginPermissions-1.0.pkg                   build output (unsigned)
```

Identifiers and paths that are hardcoded in more than one place — change all of
them together:

- pkg identifier `com.pictureshop.ptpluginperms` — `build.sh`, `uninstall.sh`
  (the `pkgutil --forget`)
- version `1.0` — `build.sh` only
- log path `/var/log/com.pictureshop.ptpluginperms.log` — `set-plugin-perms.sh`,
  `uninstall.sh`, `README.md`
- trigger dir — `set-plugin-perms.sh`, `login-trigger.sh`, `postinstall`,
  daemon plist `WatchPaths`, `uninstall.sh`
- target folders — `set-plugin-perms.sh` (`TARGETS`) only; they are no longer
  referenced in the daemon plist

`postinstall` creates the trigger dir and file **before** bootstrapping the
daemon, deliberately: launchd ignores a `WatchPaths` entry whose parent directory
does not exist at load time. Keep that ordering.

`set-plugin-perms.sh` uses `IFS=$'\n'`-style splitting (literal newline in the
script) over the `TARGETS` list so the `Plug-Ins (Unused)` path with its space
survives. Do not switch to word splitting.

## 4. Build / install / remove

```sh
./build.sh                                            # unsigned
./build.sh "Developer ID Installer: Co (TEAMID)"      # signs via productsign

sudo installer -pkg build/PSPTPluginPermissions-1.0.pkg -target /
sudo /usr/local/libexec/pictureshop/uninstall.sh
```

`postinstall` loads both jobs and, via `launchctl kickstart`, applies permissions
once immediately, so no reboot or logout is needed after install. That kickstart
is the one code path that runs the worker outside a login; it exists so an
installed machine is correct straight away. It loads the agent only into the console
user's `gui/<uid>` session; other already-logged-in fast-user-switched sessions
pick it up at their next login.

Uninstall removes both plists, both scripts, the trigger dir, the log, the pkg
receipt, and finally itself. It intentionally does **not** revert permissions on
the plug-in folders — reverting to the wrong baseline would be worse than leaving
them. README documents the manual reset.

`build.sh` runs `xattr -cr` on the payload. Note the `._*` entries in
`pkgutil --payload-files` output are pkgbuild's normal AppleDouble encoding of
file mode/owner metadata, **not** leftover junk — they are expected and merge
back on install. Don't chase them.

## 5. What is verified, and what is not

Verified:

- Worker logic, against temp directories with a rewritten copy of the script:
  recursive `chmod` to `777`; the `Plug-Ins (Unused)` path with a space; ACL
  detection and strip; and a second consecutive run logging `no changes needed`
  and writing nothing (idempotency).
- `sh -n` clean on all four shell scripts.
- `plutil -lint` clean on both plists.
- `pkgbuild` succeeds; payload contents confirmed via `pkgutil --payload-files`.

**Not** verified — this is the open work:

1. Actual `sudo installer` run. Nothing has been installed on any machine.
2. Login behaviour. The agent→trigger→daemon chain has never fired for real.
   This is the highest-risk unverified piece, and since login is now the *only*
   trigger, it is the whole product — if it does not fire, nothing happens.
3. Real `chmod` on the real target paths. Those folders **do not exist on the dev
   machine** (`/Library/Application Support/Avid/` is absent — this box has no Pro
   Tools). The worker logs `skip (missing)` and exits 0 by design, so a smoke test
   here proves nothing about the real thing. Test on a machine with Pro Tools
   installed.
4. `uninstall.sh` has never been run.
5. Monterey/Ventura specifically. Written to `bootstrap`/`bootout` with a
   `load -w`/`unload` fallback, which covers 12→current, but only ever built and
   linted on macOS 26.5.1 (Darwin 25.5.0).
6. Not signed, not notarized. Fine for local/MDM push; needed for distribution
   outside MDM. Commands are in README.
7. Multi-user / fast user switching not exercised.

### Suggested verification sequence

On a test machine that has Pro Tools:

```sh
sudo installer -pkg PSPTPluginPermissions-1.0.pkg -target /
sudo launchctl print system/com.pictureshop.ptpluginperms.daemon   # loaded?
launchctl print "gui/$(id -u)/com.pictureshop.ptpluginperms.agent" # loaded?
ls -lde "/Library/Application Support/Avid/Audio/Plug-Ins"         # 777, no ACLs?
cat /var/log/com.pictureshop.ptpluginperms.log
```

Then `sudo chmod -R 700` a target folder and confirm **nothing** happens — no
live watcher. Log out, log in as a **different** user, and confirm the folder is
back to `777` and a fresh line appears in the log with a new timestamp. That
single test covers both halves of the requirement: login applies, mid-session
does not.

Then run the uninstaller and confirm both `launchctl print` calls fail and the
files are gone.

## 6. Security position

`777` on `/Library/Application Support/Avid/Audio/Plug-Ins` lets any local user
or process replace plug-in binaries, which Pro Tools then loads into its own
process. That is a local code-execution path, and it is inherent to the request,
not a flaw in the implementation. This was raised with the user, who reaffirmed
the requirement; it is appropriate for controlled facility workstations and
should not be pushed to a general fleet. Do not "improve" this by widening scope
(e.g. recursing higher up `/Library`). If a future reviewer wants it tighter, the
conversation to have with the user is group-based `775` with a shared `protools`
group plus a setgid bit — that was not what was asked for here.

## 7. Open questions for the user

- Confirm "no permissions, no ownership" means what §1 assumes (mode `777`,
  ownership untouched) and not also a `chown`.
- Deployment channel: MDM push, or manually run installer? Determines whether
  signing and notarization are required now.
- Should the plug-in folders be **created** if absent? Current behaviour is to
  skip missing folders and log it. Creating them as `777` would arguably be more
  robust for a fresh Pro Tools install, but invents directories Avid may expect
  to own.
- Is a version-bump/reinstall path needed for fleet updates? `postinstall`
  already boots out the old daemon before bootstrapping, so reinstall is safe,
  but `VERSION` in `build.sh` must be bumped by hand.
