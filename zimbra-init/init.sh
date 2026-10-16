#!/bin/bash
# ============================================================
# Zimbra testbed first-boot initialization.
# Runs INSIDE the zimbra container as root:
#   docker compose exec -u root zimbra /opt/zt-init/init.sh
# Idempotent: safe to re-run after a volume wipe or config drift.
# Config: ./.env and ./sp/.preauth_key, mounted read-only at /opt/zt-env
# (OUTSIDE /opt/zimbra on purpose).
# ============================================================
set -uo pipefail

BIN=/opt/zimbra/bin
set -a; source /opt/zt-env/.env; set +a
ZIMBRA_PREAUTH_KEY="$(cat /opt/zt-env/preauth_key 2>/dev/null)"

log()  { echo "[zimbra-init] $*"; }
fail() { log "ERROR: $*"; exit 1; }

# --- 0. Wait for Zimbra services -----------------------------
log "Waiting for Zimbra services to come up (can take several minutes on first boot)..."
up=0
for i in $(seq 1 240); do
    if su - zimbra -c "${BIN}/zmcontrol status" >/tmp/zimbra-init-status.txt 2>&1; then
        up=1
        break
    fi
    sleep 5
done
[ "$up" = 1 ] || { log "Zimbra services did not come up in time:"; cat /tmp/zimbra-init-status.txt 2>/dev/null; fail "zimbra not up"; }
log "Zimbra services are up."

# --- 0b. Defensive: all-in-one must be the LDAP master --------
# If a half-finished setup left ldap_is_master=false, slapd refuses to start
# ("ldap_url and ldap_master_url cannot be the same on an ldap replica").
# Force master on this single-node testbed. Idempotent.
if su - zimbra -c "${BIN}/zmlocalconfig -s" 2>/dev/null | grep -q "^ldap_is_master = false"; then
    log "ldap_is_master was false; forcing true for single-node and restarting services..."
    su - zimbra -c "${BIN}/zmlocalconfig -e ldap_is_master=true" >/dev/null 2>&1
    su - zimbra -c "${BIN}/zmcontrol stop" >/dev/null 2>&1
    for i in $(seq 1 60); do
        if su - zimbra -c "${BIN}/zmcontrol start" >/tmp/zimbra-init-status.txt 2>&1; then break; fi
        sleep 5
    done
    su - zimbra -c "${BIN}/zmcontrol status" >/tmp/zimbra-init-status.txt 2>&1 \
        || { cat /tmp/zimbra-init-status.txt; fail "services still down after ldap_is_master fix"; }
fi

# zmprov in LDAP mode (-l): no SOAP/admin auth needed inside the container.
ZP=(${BIN}/zmprov -l)
"${ZP[@]}" gs "$(hostname)" zimbraId >/dev/null 2>&1 || fail "LDAP not answering (zmprov -l gs)"

# --- 1. Mail domain -------------------------------------------
if "${ZP[@]}" gd "${MAIL_DOMAIN}" >/dev/null 2>&1; then
    log "Domain ${MAIL_DOMAIN} already exists."
else
    log "Creating domain ${MAIL_DOMAIN}..."
    "${ZP[@]}" createDomain "${MAIL_DOMAIN}" || fail "could not create domain ${MAIL_DOMAIN}"
fi
if "${ZP[@]}" gd "${MAIL_DOMAIN}" >/dev/null 2>&1; then
    "${ZP[@]}" md "${MAIL_DOMAIN}" zimbraVirtualHostName "${ZIMBRA_HOST}" \
        || log "WARN: zimbraVirtualHostName rejected"
fi
# The installer's bootstrap domain (derived from the hostname, e.g. "lan")
# also claims ${ZIMBRA_HOST}; with two owners the virtual-host lookup fails
# and the login page never applies MAIL_DOMAIN's zimbraWebClientLoginURL.
for d in $("${ZP[@]}" gad 2>/dev/null); do
    [ "$d" = "${MAIL_DOMAIN}" ] && continue
    if "${ZP[@]}" gd "$d" zimbraVirtualHostname 2>/dev/null | grep -qx "zimbraVirtualHostname: ${ZIMBRA_HOST}"; then
        log "Removing virtual host ${ZIMBRA_HOST} from domain ${d}"
        "${ZP[@]}" md "$d" -zimbraVirtualHostname "${ZIMBRA_HOST}" \
            || log "WARN: could not remove ${ZIMBRA_HOST} from ${d}"
    fi
done

# --- 2. Test mailboxes ----------------------------------------
IFS=',' read -ra MAILBOXES <<< "${ZIMBRA_MAILBOXES}"
for acc in "${MAILBOXES[@]}"; do
    localpart="${acc%%@*}"
    if "${ZP[@]}" ga "$acc" >/dev/null 2>&1; then
        log "Account ${acc} already exists."
        continue
    fi
    log "Creating mailbox ${acc}..."
    # In LDAP mode, attrs are space-separated (no =), and quota is in bytes
    "${ZP[@]}" ca "$acc" "${localpart}-pass" zimbraMailQuota 1073741824 \
        givenName "$localpart" sn "$localpart" \
        || fail "could not create account ${acc}"
done

# --- 3. SSO via the SAML SP proxy (zt-sp) + domain preauth -----
# Zimbra FOSS has no SAML receiver. The SP proxy in front of the webmail
# does the SAML exchange, then logs the user in with a preauth URL signed
# with this key (./sp/.preauth_key).
PUBLIC_URL="https://${ZIMBRA_HOST}:${ZIMBRA_HTTPS_PORT}"
[ -n "${ZIMBRA_PREAUTH_KEY:-}" ] || fail "ZIMBRA_PREAUTH_KEY not set (run 'make config' first)"
"${ZP[@]}" md "${MAIL_DOMAIN}" \
    zimbraPreAuthKey "${ZIMBRA_PREAUTH_KEY}" \
    zimbraWebClientLoginURL "${PUBLIC_URL}/sso/login.php" \
    zimbraWebClientLogoutURL "${PUBLIC_URL}/sso/logout.php" \
    zimbraPublicServiceHostname "${ZIMBRA_HOST}" \
    zimbraPublicServicePort "${ZIMBRA_HTTPS_PORT}" \
    zimbraPublicServiceProtocol https \
    || fail "could not set SSO attributes on ${MAIL_DOMAIN}"
log "SSO: login -> ${PUBLIC_URL}/sso/login.php, logout -> ${PUBLIC_URL}/sso/logout.php"

# The login lands via a cross-site POST (IdP -> SP ACS) and redirects;
# Strict SameSite would drop ZM_AUTH_TOKEN on that chain.
su - zimbra -c "${BIN}/zmlocalconfig -e zimbra_same_site_cookie=''" \
    || log "WARN: zmlocalconfig zimbra_same_site_cookie failed"

# --- 4. Proxy: serve HTTPS on 443, talk plain HTTP to mailboxd --
# The image installs the proxy in http-only mode (no 443 listener), while the
# mailbox only listens on 8080 (http). Serve both on the proxy and disable
# SSL-to-upstream so nginx proxies to 8080 instead of a nonexistent 8443.
"${ZP[@]}" ms "$(hostname)" zimbraReverseProxyMailMode both \
    zimbraReverseProxySSLToUpstreamEnabled FALSE \
    || log "WARN: proxy mode settings rejected"
# The installer sets MODE=https, where mailboxd binds 8080 on 127.0.0.1 only:
# nginx (upstream zimbra.lan:8080) gets "connection refused" and answers 404.
# "both" binds 8080 on all interfaces (applied by the restart in step 5).
# zmtlsctl only accepts "both" once the proxy is in "both" mode (above).
su - zimbra -c "${BIN}/zmtlsctl both" >/dev/null \
    || fail "zmtlsctl both failed (mailboxd would not be reachable from nginx)"
su - zimbra -c "/opt/zimbra/libexec/zmproxyconfgen && ${BIN}/zmproxyctl restart" \
    || log "WARN: proxy restart failed (non-fatal)"

# --- 4b. Packaging fixes (JVM --add-opens, jetty paths, ...) ----
/opt/zt-init/fix-packages.sh

# --- 5. Restart services so everything picks up ---------------
# Not `zmmailboxdctl restart`: its stop may time out on a busy JVM, and the
# start then fails while the old JVM is still exiting.
su - zimbra -c "${BIN}/zmmailboxdctl stop"
for i in $(seq 1 30); do
    su - zimbra -c "${BIN}/zmmailboxdctl status" >/dev/null 2>&1 || break
    sleep 2
done
su - zimbra -c "${BIN}/zmmailboxdctl start" || log "WARN: zmmailboxdctl start failed (non-fatal)"

log "Init complete."
log "  SSO entry:  https://${ZIMBRA_HOST}:${ZIMBRA_HTTPS_PORT}/sso/login.php"
log "  Webmail:    https://${ZIMBRA_HOST}:${ZIMBRA_HTTPS_PORT}/"
exit 0
