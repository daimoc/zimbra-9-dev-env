<?php
// TEMPLATE — rendered by sp/render-config.sh from .env.
// Settings for the /sso/ scripts (php-fpm clears env vars, so they live here).
return [
    // Must equal the domain's zimbraPreAuthKey (set by zimbra-init/init.sh).
    'preauth_key' => '__ZIMBRA_PREAUTH_KEY__',
    'auth_source' => 'default-sp',
    // SAML attribute holding the Zimbra account name.
    'account_attribute' => 'mail',
    'public_url' => 'https://__ZIMBRA_HOST__:__ZIMBRA_HTTPS_PORT__',
];
