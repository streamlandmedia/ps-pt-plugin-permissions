# PS Pro Tools Plug-In Permissions

Sets `777` permissions on the Avid Pro Tools plug-in folders, at boot and at
every user login, invisibly in the background. Ownership is never changed.

Targets:

- `/Library/Application Support/Avid/Audio/Plug-Ins`
- `/Library/Application Support/Avid/Audio/Plug-Ins (Unused)`

Supports macOS Monterey (12) through current.

## Security caveat

`777` on these folders lets any local user or process replace plug-in
binaries, which Pro Tools then loads. Only deploy on controlled workstations.

## How it works

`/Library` is root-owned, so the work has to happen as root — a LaunchAgent
runs as the user and cannot do it. Two jobs are installed:

| Job | Runs as | Trigger |
| --- | --- | --- |
| `com.pictureshop.ptpluginperms.daemon` (LaunchDaemon) | root | boot; `login.trigger` changes; plug-in folders change |
| `com.pictureshop.ptpluginperms.agent` (LaunchAgent) | each logged-in user | login |

At login the agent touches
`/Library/Application Support/PictureShop/PTPluginPerms/login.trigger`.
The daemon watches that path and wakes to do the `chmod` as root. The daemon
also watches the plug-in folders themselves, so a new plug-in install gets
fixed without waiting for the next login.

The worker only touches entries that are not already `777`, so a run that
finds nothing wrong changes nothing — that's what stops the folder watch from
retriggering itself in a loop. It also strips ACLs, which are the usual reason
a folder that reads as `777` still refuses writes.

No windows, no dock icon, no notifications. Logs to
`/var/log/com.pictureshop.ptpluginperms.log` (rotated at 256 KB).

## Layout

```
payload/
  usr/local/libexec/pictureshop/set-plugin-perms.sh    worker (root)
  usr/local/libexec/pictureshop/login-trigger.sh       login poke (user)
  usr/local/libexec/pictureshop/uninstall.sh           removal
  Library/LaunchDaemons/...daemon.plist
  Library/LaunchAgents/...agent.plist
scripts/postinstall                                    loads both jobs
build.sh                                               builds the pkg
```

## Build

```sh
./build.sh                                              # unsigned
./build.sh "Developer ID Installer: Co (TEAMID)"        # signed
```

Output: `build/PSPTPluginPermissions-1.0.pkg`

For distribution outside MDM, sign and notarize:

```sh
xcrun notarytool submit build/PSPTPluginPermissions-1.0.pkg \
    --keychain-profile "AC_PASSWORD" --wait
xcrun stapler staple build/PSPTPluginPermissions-1.0.pkg
```

## Install

```sh
sudo installer -pkg build/PSPTPluginPermissions-1.0.pkg -target /
```

The postinstall loads both jobs and applies permissions immediately — no
reboot or logout needed. Under MDM, deploy as a signed pkg; no PPPC profile is
required.

## Uninstall

```sh
sudo /usr/local/libexec/pictureshop/uninstall.sh
```

Stops and removes both jobs, the scripts, the trigger directory, the log, and
the package receipt. Permissions already applied to the plug-in folders are
left alone — reset them by hand if needed:

```sh
sudo chmod -R 755 "/Library/Application Support/Avid/Audio/Plug-Ins"
```

To disable without uninstalling:

```sh
sudo launchctl bootout system/com.pictureshop.ptpluginperms.daemon
```

## Verify

```sh
sudo launchctl print system/com.pictureshop.ptpluginperms.daemon
tail -f /var/log/com.pictureshop.ptpluginperms.log
ls -lde "/Library/Application Support/Avid/Audio/Plug-Ins"
```
