#!/bin/bash
# SP proxy startup. Runs in the IdP image (same SimpleSAMLphp build), with
# ./sp mounted at /sp: materialize SP config + certs, swap in the proxy's
# nginx site, then start php-fpm and nginx.
set -euo pipefail

SSP=/var/www/simplesamlphp

# --- SimpleSAMLphp SP config (rendered on the host) -----------
mkdir -p "$SSP/config" "$SSP/metadata" "$SSP/certs" /etc/zt-sp
cp -f /sp/config/config.php            "$SSP/config/config.php"
cp -f /sp/config/authsources.php       "$SSP/config/authsources.php"
cp -f /sp/config/saml20-idp-remote.php "$SSP/metadata/saml20-idp-remote.php"
# The image may carry IdP-side metadata; the SP must not load it.
rm -f "$SSP/metadata/saml20-idp-hosted.php" "$SSP/metadata/saml20-sp-remote.php"
cp -f /sp/config/sso.php /etc/zt-sp/sso.php

# IdP signing cert, referenced by saml20-idp-remote.php ('certificate').
cp -f /idpcerts/idp.crt "$SSP/certs/idp.crt"

# --- TLS for the public webmail host --------------------------
mkdir -p /etc/nginx/ssl
cp -f /sp/certs/sp.crt /etc/nginx/ssl/sp.crt
cp -f /sp/certs/sp.key /etc/nginx/ssl/sp.key
chmod 600 /etc/nginx/ssl/sp.key

# --- nginx: replace the image's IdP site with the proxy site --
rm -f /etc/nginx/sites-enabled/*
cp -f /sp/sp-nginx.conf /etc/nginx/sites-enabled/sp.conf

# --- Web roots -------------------------------------------------
ln -sfn "$SSP/public" /var/www/html/simplesaml
ln -sfn /sp/app /var/www/html/sso

mkdir -p "$SSP/logs" /var/lib/php/sessions /var/cache/simplesamlphp
chown -R www-data:www-data "$SSP" /var/lib/php/sessions /var/cache/simplesamlphp
chown root:www-data /etc/zt-sp/sso.php && chmod 640 /etc/zt-sp/sso.php

# --- Service start --------------------------------------------
php-fpm8.2 --daemonize
nginx -g 'daemon off;'
