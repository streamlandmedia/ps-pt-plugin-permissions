#!/bin/sh
# login-trigger.sh
#
# Runs as the logged-in user from a LaunchAgent at every login. It cannot
# change permissions under /Library itself, so it just touches a file that
# the root LaunchDaemon is watching. Touching the file wakes the daemon,
# which does the actual work as root.

set -u

TRIGGER_DIR="/Library/Application Support/PictureShop/PTPluginPerms"
TRIGGER="${TRIGGER_DIR}/login.trigger"

mkdir -p "$TRIGGER_DIR" 2>/dev/null
: >"$TRIGGER" 2>/dev/null || touch "$TRIGGER" 2>/dev/null
chmod 666 "$TRIGGER" 2>/dev/null

exit 0
