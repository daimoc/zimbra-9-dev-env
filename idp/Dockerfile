# SimpleSAMLphp 2.4 SAML IdP — nginx + php-fpm (Debian bookworm / PHP 8.2).
# Config + certs are injected at startup from the mounted ./idp dirs.
FROM debian:bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
        nginx \
        php-fpm php-cli php-xml php-curl php-mbstring php-zip php-gd \
        ca-certificates openssl curl unzip git \
    && rm -rf /var/lib/apt/lists/*

# SimpleSAMLphp 2.4.9.3 (supports PHP 8.2; 2.5 needs PHP 8.3)
RUN mkdir -p /var/www \
    && cd /var/www \
    && curl -fsSL https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
    && COMPOSER_ALLOW_SUPERUSER=1 COMPOSER_MEMORY_LIMIT=-1 \
       composer create-project --no-dev --ignore-platform-req=php \
       simplesamlphp/simplesamlphp simplesamlphp 2.4.9.3 \
    && chown -R www-data:www-data /var/www/simplesamlphp

# PHP-FPM listens on a unix socket
RUN sed -ri 's|^listen = .*|listen = /run/php/php-fpm.sock|' /etc/php/*/fpm/pool.d/*.conf

# nginx: serve SimpleSAMLphp over HTTPS (self-signed cert mounted at startup)
RUN rm -f /etc/nginx/sites-enabled/default
COPY idp-nginx.conf /etc/nginx/sites-available/idp.conf
RUN ln -s /etc/nginx/sites-available/idp.conf /etc/nginx/sites-enabled/idp.conf

# Startup: materialize config + certs, start php-fpm and nginx
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8443
ENTRYPOINT ["/entrypoint.sh"]
