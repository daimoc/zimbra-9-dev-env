#!/bin/bash
# Wrapper for zmsetup.pl, called by the image's /opt/build.sh (patched by
# entrypoint.sh) once the Zimbra packages are installed:
#   - kill the slapd started by the RPM post-install so zmsetup.pl can start
#     LDAP fresh (no stale pid/socket),
#   - apply fix-packages.sh before zmsetup.pl starts the services.

# Wait for slapd to appear (from RPM post-install)
for i in $(seq 1 30); do
    if [ -f /opt/zimbra/data/ldap/state/run/slapd.pid ]; then
        break
    fi
    sleep 1
done

# Remove stale PID file and socket
rm -f /opt/zimbra/data/ldap/state/run/slapd.pid
rm -f /opt/zimbra/data/ldap/state/run/slapd.args
rm -f /opt/zimbra/data/ldap/state/run/ldapi

# Kill slapd via /proc
for _c in /proc/[0-9]*/comm; do
    if [ -f "$_c" ]; then
        pname=$(cat "$_c" 2>/dev/null)
        if [ "$pname" = "slapd" ]; then
            pid=$(echo "$_c" | grep -o '[0-9]*')
            kill -9 "$pid" 2>/dev/null
        fi
    fi
done 2>/dev/null

# Also check /proc/*/exe
for _e in /proc/[0-9]*/exe; do
    if [ -L "$_e" ]; then
        target=$(readlink "$_e" 2>/dev/null)
        if echo "$target" | grep -q slapd; then
            pid=$(echo "$_e" | grep -o '[0-9]*')
            kill -9 "$pid" 2>/dev/null
        fi
    fi
done 2>/dev/null

sleep 3

# Packages are installed; patch them before zmsetup starts the services.
/opt/zt-init/fix-packages.sh

# Now run zmsetup.pl
exec /opt/zimbra/libexec/zmsetup.pl "$@"
