#!/bin/sh
# uninstall.sh -- removes the Pro Tools plug-in permissions helper.
#
# Run with:  sudo /usr/local/libexec/pictureshop/uninstall.sh
#
# Permissions already applied to the plug-in folders are left as they are;
# this only stops and deletes the helper.

set -u

if [ "$(id -u)" -ne 0 ]; then
    echo "Must run as root: sudo $0" >&2
    exit 1
fi

AGENT_LABEL="com.pictureshop.ptpluginperms.agent"
DAEMON_PLIST="/Library/LaunchDaemons/com.pictureshop.ptpluginperms.daemon.plist"
AGENT_PLIST="/Library/LaunchAgents/com.pictureshop.ptpluginperms.agent.plist"

echo "Stopping daemon..."
launchctl bootout system "$DAEMON_PLIST" 2>/dev/null
launchctl unload "$DAEMON_PLIST" 2>/dev/null

echo "Stopping agent for all logged-in users..."
for uid in $(ps -axo uid,args | awk '/[l]oginwindow.app\/Contents\/MacOS\/loginwindow console/ {print $1}' | sort -u); do
    launchctl bootout "gui/${uid}/${AGENT_LABEL}" 2>/dev/null
done

echo "Removing files..."
rm -f "$DAEMON_PLIST" "$AGENT_PLIST"
rm -rf "/Library/Application Support/PictureShop/PTPluginPerms"
rmdir "/Library/Application Support/PictureShop" 2>/dev/null
rm -f /var/log/com.pictureshop.ptpluginperms.log /var/log/com.pictureshop.ptpluginperms.log.1

# Forget the package receipt so a reinstall is clean.
pkgutil --forget com.pictureshop.ptpluginperms >/dev/null 2>&1

# Delete this script and its directory last.
rm -f /usr/local/libexec/pictureshop/set-plugin-perms.sh \
      /usr/local/libexec/pictureshop/login-trigger.sh
rmdir /usr/local/libexec/pictureshop 2>/dev/null
rm -f "$0"

echo "Done. Helper removed."
exit 0
