#!/usr/bin/env bash
# Render the IdP and SAML SP proxy configs from templates + .env, and make
# sure their secrets and self-signed certs exist. Idempotent — run by
# `make config` on every `make up`.
#   idp/templates/*.tpl -> idp/config/     (mounted into zt-idp)
#   sp/templates/*.tpl  -> sp/config/      (mounted into zt-sp)
# Templates use __VAR__ placeholders, replaced by the variable of that name
# (from .env or set below); unknown names are left untouched.
set -euo pipefail
cd "$(dirname "$0")/.."

set -a; source ./.env; set +a

secret() { # secret <file>: print the persisted secret, generating it once
    [ -f "$1" ] || openssl rand -hex 32 > "$1"
    cat "$1"
}

cert() { # cert <dir> <name> <cn>: self-signed cert, generated once
    [ -f "$1/$2.crt" ] && [ -f "$1/$2.key" ] && return
    mkdir -p "$1"
    openssl req -x509 -newkey rsa:2048 -sha256 -days 825 -nodes \
        -keyout "$1/$2.key" -out "$1/$2.crt" \
        -subj "/CN=$3/O=Zimbra Testbed" -addext "subjectAltName=DNS:$3"
    echo "Generated self-signed cert $1/$2.crt"
}

render() { # render <template> <output>
    perl -pe 's/__([A-Z][A-Z0-9_]*)__/exists $ENV{$1} ? $ENV{$1} : $&/ge' "$1" > "$2"
}

export SSP_SECRET="$(secret idp/.ssp_secret)"
export SP_SECRET="$(secret sp/.ssp_secret)"
# Shared with Zimbra: init.sh sets it as the domain's zimbraPreAuthKey.
export ZIMBRA_PREAUTH_KEY="$(secret sp/.preauth_key)"

# IdP users for exampleauth:UserPass: 'email:password' => [attributes]. The
# full email is the username, uid and mail (Zimbra maps it to the account).
IDP_USERS_PHP=""
IFS=',' read -ra USERS <<< "$IDP_USERS"
for u in "${USERS[@]}"; do
    IFS=':' read -r email pass <<< "$u"
    IDP_USERS_PHP+=$(printf "\n            '%s:%s' => [\n                'uid' => '%s',\n                'mail' => '%s',\n                'displayName' => '%s',\n            ]," \
        "$email" "$pass" "$email" "$email" "${email%%@*}")
done
export IDP_USERS_PHP

for side in idp sp; do
    mkdir -p "$side/config"
    for tpl in "$side"/templates/*.tpl; do
        out="$side/config/$(basename "$tpl" .tpl)"
        render "$tpl" "$out"
    done
done

cert idp/certs idp "$IDP_HOST"
cert sp/certs  sp  "$ZIMBRA_HOST"

if command -v php >/dev/null 2>&1; then
    for f in idp/config/*.php sp/config/*.php sp/app/*.php; do php -l "$f" >/dev/null; done
fi

echo "Rendered idp/config/ and sp/config/"
