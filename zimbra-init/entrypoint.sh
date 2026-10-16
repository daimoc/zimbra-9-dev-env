#!/bin/bash
# ============================================================
# Command of the zimbra container (wraps the image's /opt/build.sh -d).
#   First boot (empty /opt/zimbra): patch build.sh, run the image installer;
#     wrap-zmsetup.sh applies fix-packages.sh between package install and
#     zmsetup.
#   Later boots: only /opt/zimbra is persisted, so restore the OS-level state
#     the installer created (users, RPM deps, sudo, rsyslog), then start Zimbra.
# ============================================================
log() { echo "[zt-entrypoint] $*"; }

# --- Resolver: "myhostname" makes zimbra.lan resolve to every local IP ---
if grep -q "myhostname" /etc/nsswitch.conf 2>/dev/null; then
    sed -i 's/^hosts:.*/hosts: files dns/' /etc/nsswitch.conf
    log "Fixed nsswitch: removed myhostname"
fi

awk '!seen[$0]++' /etc/hosts > /tmp/hosts.dedup
if ! cmp -s /etc/hosts /tmp/hosts.dedup; then
    cp /tmp/hosts.dedup /etc/hosts
    log "Deduplicated /etc/hosts"
fi

# ============================================================
# First boot: run the image installer
# ============================================================
if ! grep -qs "zimbra_server_hostname" /opt/zimbra/conf/localconfig.xml \
   || [ ! -x /opt/zimbra/bin/zmcontrol ]; then
    # /opt/zimbra-install/install-autoKeys is build.sh's "not installed yet"
    # marker: without it build.sh skips the install and runs `su - zimbra`
    # against an empty /opt/zimbra ("su: user zimbra does not exist").
    if [ ! -e /opt/zimbra-install/install-autoKeys ]; then
        log "ERROR: /opt/zimbra is not initialized but the installer" \
            "marker is gone (container reused after a failed install?)." \
            "Run 'make destroy && make up' to recreate the container."
        exit 1
    fi
    if grep -q 'gpgcheck=1' /opt/build.sh; then
        sed -i -e 's/gpgcheck=1/gpgcheck=0/' -e '/rpm --import.*public.key/d' /opt/build.sh
        log "Patched build.sh: disabled GPG checking"
    fi
    if ! grep -q 'wrap-zmsetup' /opt/build.sh; then
        sed -i 's|/opt/zimbra/libexec/zmsetup.pl -c|/opt/zt-init/wrap-zmsetup.sh -c|' /opt/build.sh
        log "Patched build.sh: use wrap-zmsetup.sh"
    fi
    exec /bin/bash /opt/build.sh -d
fi

# ============================================================
# Later boots
# ============================================================
log "Zimbra already initialized — skipping installer"

# --- Users and RPM deps lost when the container is recreated ---
# Same IDs as the installer created, so the persisted files match.
if ! id zimbra >/dev/null 2>&1; then
    groupadd -g 995 zimbra 2>/dev/null || true
    useradd -u 998 -g 995 -d /opt/zimbra -s /bin/bash zimbra 2>/dev/null || true
    log "Created zimbra user"
fi
getent group postdrop >/dev/null || groupadd -g 994 postdrop
getent group postfix  >/dev/null || groupadd -g 993 postfix
if ! getent passwd postfix >/dev/null; then
    useradd -u 997 -g postfix -G mail -d /opt/zimbra/postfix -s /sbin/nologin postfix
    log "Created postfix user"
fi
# libaio: MariaDB. libidn: Net::LibIDN (amavisd). sysstat: iostat (zmstat).
for pkg in libaio libidn sysstat; do
    rpm -q "$pkg" >/dev/null 2>&1 || { yum install -y -q "$pkg" && log "Installed $pkg"; }
done

# --- sudo: zm*ctl scripts call sudo; the installer's sudoers file is gone ---
command -v sudo >/dev/null 2>&1 || { yum install -y -q sudo && log "Installed sudo"; }
echo "zimbra ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/zimbra
chmod 440 /etc/sudoers.d/zimbra

# --- Package fixes (idempotent; see fix-packages.sh) ---
/opt/zt-init/fix-packages.sh

# --- rsyslog: Zimbra's rules (zimbra.log, zimbra-stats.log) live in the
# non-persisted /etc/rsyslog.conf ---
if ! grep -q 'zimbra-stats.log' /etc/rsyslog.conf 2>/dev/null; then
    /opt/zimbra/libexec/zmsyslogsetup >/dev/null 2>&1 \
        && log "Restored Zimbra rsyslog config" \
        || log "WARN: zmsyslogsetup failed"
fi
rsyslogd

/opt/zimbra/libexec/zmfixperms >/dev/null 2>&1 || log "WARN: zmfixperms failed"
su - zimbra -c 'zmcontrol start'

# Keep the container alive
while true; do sleep 1000; done
