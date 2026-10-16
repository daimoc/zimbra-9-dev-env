#!/usr/bin/env bash
# ============================================================
# End-to-end validation of the Zimbra 9 + SAML testbed.
# Run from the repo root:  ./tests/validate.sh   (or: make test)
# Non-zero exit on any failure.
# ============================================================
set -u
cd "$(dirname "$0")/.."

set -a; source ./.env; set +a

COMPOSE="${COMPOSE:-docker compose}"
PASS=0; FAIL=0; SKIP=0

ok()   { PASS=$((PASS+1)); echo "  PASS  $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }
skip() { SKIP=$((SKIP+1)); echo "  SKIP  $1"; }
sec()  { echo; echo "== $1"; }

zexec()  { $COMPOSE exec -u zimbra zimbra "$@"; }
zexecr() { $COMPOSE exec -u root zimbra "$@"; }

# --- 0. Host prerequisites ----------------------------------
sec "Host prerequisites"
for name in zimbra.lan idp.lan; do
    if getent hosts "$name" >/dev/null 2>&1; then
        ok "host name resolves: $name"
    else
        bad "host name does NOT resolve: $name (add '127.0.0.1 $name' to /etc/hosts, or rely on the container DNS if curl runs in-container)"
    fi
done

# --- 1. Containers ------------------------------------------
sec "Containers"
for c in dns zimbra idp sp; do
    running=$($COMPOSE ps --format '{{.State}}' "$c" 2>/dev/null | head -1)
    [ "$running" = "running" ] && ok "$c running" || bad "$c state: '$running'"
done

if [ $FAIL -gt 0 ]; then
    echo; echo "Containers not up — aborting. Try: make up"
    exit 1
fi

# --- 2. Zimbra accounts & domain -----------------------------
sec "Zimbra accounts"
IFS=',' read -ra MBOXES <<< "$ZIMBRA_MAILBOXES"
for acc in "${MBOXES[@]}"; do
    if zexec /opt/zimbra/bin/zmprov -l ga "$acc" >/dev/null 2>&1; then
        ok "mailbox exists: $acc"
    else
        bad "mailbox missing: $acc"
    fi
done

PUBLIC_URL="https://${ZIMBRA_HOST}:${ZIMBRA_HTTPS_PORT}"
domain=$(zexec /opt/zimbra/bin/zmprov -l gd "$MAIL_DOMAIN" 2>/dev/null)
if echo "$domain" | grep -q "^zimbraPreAuthKey: $(cat sp/.preauth_key 2>/dev/null)\$"; then
    ok "zimbraPreAuthKey on domain matches sp/.preauth_key"
else
    bad "zimbraPreAuthKey missing on $MAIL_DOMAIN or differs from sp/.preauth_key (make init)"
fi
if echo "$domain" | grep -q "^zimbraWebClientLoginURL: ${PUBLIC_URL}/sso/login.php"; then
    ok "zimbraWebClientLoginURL -> SP proxy /sso/login.php"
else
    bad "zimbraWebClientLoginURL does not point to ${PUBLIC_URL}/sso/login.php"
fi

# --- 3. SAML SP proxy (zt-sp) ---------------------------------
sec "SAML SP proxy"
SP_ENTITY="${PUBLIC_URL}/simplesaml/module.php/saml/sp/metadata.php/default-sp"
if curl -sk -m 15 "$SP_ENTITY" | grep -q "entityID=\"${SP_ENTITY}\""; then
    ok "SP metadata served at ${SP_ENTITY}"
else
    bad "SP metadata not served (or wrong entityID) at ${SP_ENTITY}"
fi
# Anonymous webmail visit: proxied to Zimbra, whose login page must hand
# off to the SP (zimbraWebClientLoginURL resolved via the virtual host).
loc=$(curl -sk -m 15 -o /dev/null -w '%{http_code} %{redirect_url}' "${PUBLIC_URL}/")
if [ "$loc" = "302 ${PUBLIC_URL}/sso/login.php" ]; then
    ok "anonymous webmail visit redirected to SSO (/sso/login.php)"
else
    bad "anonymous webmail visit not redirected to SSO (GET / -> ${loc})"
fi

# --- 4. IdP --------------------------------------------------
sec "IdP"
IDP_URL="https://${IDP_HOST}:${IDP_HTTPS_PORT}"
meta=$($COMPOSE exec idp curl -sk "https://${IDP_HOST}:8443/simplesaml/saml2/idp/metadata.php" 2>/dev/null)
if echo "$meta" | grep -q "EntityDescriptor"; then
    ok "IdP metadata served (in-container)"
else
    bad "IdP metadata not served"
fi
if echo "$meta" | grep -q "${IDP_HOST}:${IDP_HTTPS_PORT}"; then
    ok "IdP metadata advertises public host ${IDP_HOST}:${IDP_HTTPS_PORT}"
else
    bad "IdP metadata host mismatch (should advertise ${IDP_HOST}:${IDP_HTTPS_PORT})"
fi
# SP must appear in the IdP's remote SP metadata
spmeta=$($COMPOSE exec idp cat /idpconfig/saml20-sp-remote.php 2>/dev/null)
if echo "$spmeta" | grep -qF "['${SP_ENTITY}']"; then
    ok "IdP knows the SP proxy entity"
else
    bad "IdP sp-remote does not reference the SP proxy entity ${SP_ENTITY}"
fi

# --- 5. SSO handshake (the real test) -------------------------
sec "SAML SSO handshake (SP-initiated)"
# Parse first user from .env (email:password)
IFS=: read -r FIRST_EMAIL FIRST_PASS <<< "$(echo "$IDP_USERS" | tr ',' '\n' | head -1)"
if python3 tests/sso_handshake.py "$FIRST_EMAIL" "$FIRST_PASS" "$FIRST_EMAIL"; then
    ok "SSO login as ${FIRST_EMAIL} -> authenticated Zimbra session"
else
    bad "SSO login as ${FIRST_EMAIL} failed"
fi

# Negative: ghost user exists in IdP but not in Zimbra
GHOST_LINE=$(echo "$IDP_USERS" | tr ',' '\n' | grep ghost@ || true)
if [ -n "$GHOST_LINE" ]; then
    GHOST_EMAIL="${GHOST_LINE%%:*}"; GHOST_PASS="${GHOST_LINE##*:}"
    if python3 tests/sso_handshake.py "$GHOST_EMAIL" "$GHOST_PASS" "$GHOST_EMAIL" --expect-fail; then
        ok "negative SSO: IdP-valid user without Zimbra mailbox rejected"
    else
        bad "negative SSO: ghost user was NOT rejected (no Zimbra account exists!)"
    fi
else
    skip "no ghost user defined in IDP_USERS"
fi

# --- 6. Zimlet install cycle ---------------------------------
sec "Zimlet install cycle"
ZIMLET_NAME=com_zimbra_testbed_hello
if [ ! -f "zimlets/${ZIMLET_NAME}.zip" ]; then
    skip "${ZIMLET_NAME}.zip not built (make build-example-zimlet)"
else
    zexec /opt/zimbra/bin/zmzimletctl -l deploy "/opt/zt-zimlets/${ZIMLET_NAME}.zip" >/tmp/zimlet-install.log 2>&1 \
        && ok "zimlet deployed" || { bad "zimlet deploy failed"; tail -5 /tmp/zimlet-install.log; }
    if zexec /opt/zimbra/bin/zmzimletctl -l listZimlets 2>/dev/null | grep -q "$ZIMLET_NAME"; then
        ok "zimlet listed in listZimlets"
    else
        bad "zimlet not listed after install"
    fi
    # clean up so the test stays repeatable
    if zexec /opt/zimbra/bin/zmzimletctl -l undeploy "$ZIMLET_NAME" >/dev/null 2>&1; then
        if zexec /opt/zimbra/bin/zmzimletctl -l listZimlets 2>/dev/null | grep -q "$ZIMLET_NAME"; then
            bad "zimlet still listed after remove"
        else
            ok "zimlet removed cleanly"
        fi
    else
        bad "zimlet undeploy failed"
    fi
fi

# --- Summary ---------------------------------------------------
echo
echo "=================================================="
echo " RESULT: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "=================================================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
