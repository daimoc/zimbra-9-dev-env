<?php
// TEMPLATE — rendered by sp/render-config.sh from .env. Do not edit by hand.
// SAML SP proxy in front of the Zimbra webmail. Schema: SimpleSAMLphp 2.4.9.3

$config = [
    'instanceid' => 'zimbra-testbed-sp',

    // Public URL of the proxy (host port), not the in-container 8443.
    'baseurlpath' => 'https://__ZIMBRA_HOST__:__ZIMBRA_HTTPS_PORT__/simplesaml/',

    'secretsalt' => '__SP_SECRET__',

    // Remote IdP cert (idp.crt) is materialized here by the entrypoint.
    'certdir' => 'certs/',

    'auth.adminpassword' => '__IDP_ADMIN_PASSWORD__',
    'showerrors' => true,

    // --- Session cookies ---------------------------------------
    // Path '/' so the /sso/*.php scripts (outside /simplesaml/) see the
    // session. SameSite=None: the IdP POSTs the SAMLResponse cross-site.
    // Distinct name so it never collides with anything Zimbra sets.
    'session.cookie.secure' => true,
    'session.cookie.samesite' => 'None',
    'session.cookie.path' => '/',
    'session.phpsession.cookiename' => 'ZT_SP_SESSION',
    'session.authtoken.cookiename' => 'ZT_SP_AUTHTOKEN',

    // Symfony kernel cache (required by SSP 2.x routing).
    'cachedir' => '/var/cache/simplesamlphp',

    // --- Logging -------------------------------------------------
    'loggingdir' => '/var/www/simplesamlphp/logs',
    'logging.level' => 256, // DEBUG
    'logging.handler' => 'file',
    'logging.logfile' => 'simplesamlphp.log',

    'module.enable' => [
        'admin' => true,
        'saml' => true,
    ],

    'languages' => ['en'],
];
