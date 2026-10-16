#!/bin/bash
# IdP startup: materialize config + certs from the mounted ./idp dir,
# then start php-fpm and nginx.
set -euo pipefail

SSP=/var/www/simplesamlphp

# --- Config (mounted read-only from host ./idp/config) --------
mkdir -p "$SSP/config" "$SSP/metadata"
cp -f /idpconfig/config.php             "$SSP/config/config.php"
cp -f /idpconfig/authsources.php        "$SSP/config/authsources.php"
cp -f /idpconfig/saml20-idp-hosted.php  "$SSP/metadata/saml20-idp-hosted.php"
cp -f /idpconfig/saml20-sp-remote.php   "$SSP/metadata/saml20-sp-remote.php"

# --- Certs (generated once on the host, mounted) --------------
mkdir -p /etc/nginx/ssl "$SSP/certs"
cp -f /idpcerts/idp.crt /etc/nginx/ssl/idp.crt
cp -f /idpcerts/idp.key /etc/nginx/ssl/idp.key
cp -f /idpcerts/idp.crt "$SSP/certs/idp.crt"
cp -f /idpcerts/idp.key "$SSP/certs/idp.key"

# Classic /simplesaml/ URL prefix -> SimpleSAMLphp public/ dir
ln -sfn "$SSP/public" /var/www/html/simplesaml

# Writable dirs for the web user
mkdir -p "$SSP/logs" /var/lib/php/sessions /var/cache/simplesamlphp
chown -R www-data:www-data "$SSP" /var/lib/php/sessions /var/cache/simplesamlphp
chmod 600 /etc/nginx/ssl/idp.key

# --- Service start --------------------------------------------
php-fpm8.2 --daemonize
nginx -g 'daemon off;'
