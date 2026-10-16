#!/bin/bash
# Patches for the Zimbra 9 RPMs pulled by the image (repo.zimbra.com 90/rhel8).
# Must run after the packages are installed and before services start:
# called by wrap-zmsetup.sh on first boot and by entrypoint.sh on every boot.
# Idempotent.

# OpenSSL: the bundled OpenSSL 3.0.9 needs the "legacy" provider for the
# installer's keystore (PKCS12) step. See openssl-legacy.cnf.
BUNDLED_CNF=/opt/zimbra/common/etc/ssl/openssl.cnf
if [ -e "$BUNDLED_CNF" ] && ! grep -q "legacy  = legacy_sect" "$BUNDLED_CNF"; then
    cp -f /opt/zt-init/openssl-legacy.cnf "$BUNDLED_CNF"
    echo "[zt-fix] OpenSSL legacy provider enabled"
fi

# Jetty: zimbra-store ships jetty-setuid-java-1.0.4.jar but setuid.mod still
# names 1.0.3 -> mailboxd dies with ClassNotFoundException SetUIDListener.
# setuid.mod is rendered from setuid.mod.in by zmsetup, so patch both.
for f in /opt/zimbra/jetty_base/modules/setuid.mod /opt/zimbra/jetty_base/modules/setuid.mod.in; do
    if grep -q "jetty-setuid-java-1.0.3" "$f" 2>/dev/null; then
        sed -i "s/jetty-setuid-java-1.0.3.jar/jetty-setuid-java-1.0.4.jar/" "$f"
        echo "[zt-fix] Fixed Jetty setuid jar version in $(basename "$f")"
    fi
done

# Jetty: the /zimlet context serves ${jetty.base}/webapps/zimlet and
# ${jetty.base}/../zimlets-deployed. jetty.base is /opt/zimbra/mailboxd, a
# symlink, so every file is an alias, and Jetty 9.4.46 refuses aliases in a
# ResourceCollection: each zimlet file answers 404 (zimlet JS, CSS, images).
# Use the real paths. jetty.xml is regenerated from the .in, so patch both.
for f in /opt/zimbra/jetty_base/etc/jetty.xml.in /opt/zimbra/jetty_base/etc/jetty.xml; do
    if grep -q '<Item><SystemProperty name="jetty.base" default="."/>/\(webapps/zimlet\|../zimlets-deployed\)</Item>' "$f" 2>/dev/null; then
        sed -i \
            -e 's#<Item><SystemProperty name="jetty.base" default="."/>/webapps/zimlet</Item>#<Item>/opt/zimbra/jetty_base/webapps/zimlet</Item>#' \
            -e 's#<Item><SystemProperty name="jetty.base" default="."/>/../zimlets-deployed</Item>#<Item>/opt/zimbra/zimlets-deployed</Item>#' \
            "$f"
        echo "[zt-fix] Zimlet resource paths de-aliased in $(basename "$f")"
    fi
done

# Apache: httpd.conf loads libphp7.so but zimbra-php 8 ships libphp.so ->
# apache (and the spell service) fail to start.
HTTPD_CONF=/opt/zimbra/conf/httpd.conf
if grep -qE "^#?LoadModule php7_module" "$HTTPD_CONF" 2>/dev/null; then
    sed -i -E "s|^#?LoadModule php7_module .*|LoadModule php_module /opt/zimbra/common/lib/apache2/modules/libphp.so|" "$HTTPD_CONF"
    echo "[zt-fix] httpd.conf: php7 module -> PHP 8 libphp.so"
fi

# mailboxd: zimbra-openjdk is 17, but the Zextras OpenZAL extensions
# (zimbradrive, openchat) call ClassLoader.defineClass by reflection -> the
# SOAP servlet dies at startup (InaccessibleObjectException), every /service
# request answers 404 and the login page 500.
if [ -x /opt/zimbra/bin/zmlocalconfig ] && id zimbra >/dev/null 2>&1; then
    opts="$(su - zimbra -c '/opt/zimbra/bin/zmlocalconfig -m nokey mailboxd_java_options' 2>/dev/null)"
    if [ -n "$opts" ] && ! grep -q -- "--add-opens java.base/java.lang=" <<<"$opts"; then
        su - zimbra -c "/opt/zimbra/bin/zmlocalconfig -e mailboxd_java_options='$opts --add-opens java.base/java.lang=ALL-UNNAMED'" \
            && echo "[zt-fix] mailboxd_java_options: added --add-opens java.base/java.lang"
    fi
fi
exit 0
