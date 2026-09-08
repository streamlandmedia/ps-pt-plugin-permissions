#!/bin/sh
# set-plugin-perms.sh
#
# Sets fully open (777) permissions on the Avid Pro Tools plug-in folders.
# Runs as root from a LaunchDaemon, triggered only by a user logging in (the
# companion LaunchAgent touches the file this daemon watches).
#
# There is no folder watcher: permissions are never changed mid-session.
# Ownership is deliberately left untouched.

set -u

LABEL="com.pictureshop.ptpluginperms"
LOG="/var/log/${LABEL}.log"
TRIGGER_DIR="/Library/Application Support/PictureShop/PTPluginPerms"

TARGETS="
/Library/Application Support/Avid/Audio/Plug-Ins
/Library/Application Support/Avid/Audio/Plug-Ins (Unused)
"

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >>"$LOG" 2>/dev/null
}

# Keep the log from growing without bound.
if [ -f "$LOG" ] && [ "$(wc -c <"$LOG" 2>/dev/null || echo 0)" -gt 262144 ]; then
    mv -f "$LOG" "${LOG}.1" 2>/dev/null
fi

# The trigger directory must stay writable by every user so the per-user
# LaunchAgent can poke the daemon at login.
mkdir -p "$TRIGGER_DIR" 2>/dev/null
chmod 1777 "$TRIGGER_DIR" 2>/dev/null

changed=0

# IFS=newline so paths containing spaces survive the loop.
OLD_IFS=$IFS
IFS='
'
for target in $TARGETS; do
    [ -n "$target" ] || continue

    if [ ! -d "$target" ]; then
        log "skip (missing): $target"
        continue
    fi

    # Only touch entries that are not already 777, so a run with nothing to
    # do writes nothing at all.
    count=$(find "$target" ! -perm 777 -print 2>/dev/null | wc -l | tr -d ' ')

    if [ "$count" -gt 0 ]; then
        find "$target" ! -perm 777 -exec chmod 777 {} + 2>/dev/null
        log "chmod 777 on $count item(s): $target"
        changed=$((changed + 1))
    fi

    # Clear any ACLs, which override the mode bits and are the usual reason
    # a 777 folder still refuses writes.
    if ls -lde "$target" 2>/dev/null | grep -q '^ [0-9]*:'; then
        chmod -RN "$target" 2>/dev/null
        log "cleared ACLs: $target"
        changed=$((changed + 1))
    fi
done
IFS=$OLD_IFS

[ "$changed" -eq 0 ] && log "no changes needed"

exit 0
