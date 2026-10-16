<?php
// TEMPLATE — rendered by render-config.sh from .env. Do not edit by hand.
// Schema: SimpleSAMLphp 2.4.9.3

$config = [
    'instanceid' => 'zimbra-testbed-idp',

    // Public URL (host port), not the in-container 8443 nginx listens on —
    // otherwise SSP builds redirects to idp.lan:8443, which the host maps
    // to the Zimbra container.
    'baseurlpath' => 'https://__IDP_HOST__:__IDP_HTTPS_PORT__/simplesaml/',

    // Random secret (generated once by render-config.sh into SSP_SECRET).
    'secretsalt' => '__SSP_SECRET__',

    'enable.saml20-idp' => true,

    // Where idp.crt / idp.key live (entrypoint materializes them here).
    'certdir' => 'certs/',

    // --- Login page / admin ------------------------------------
    'auth.adminpassword' => '__IDP_ADMIN_PASSWORD__',

    // Show full error messages in the browser while testing.
    'showerrors' => true,

    // --- Session cookies ---------------------------------------
    // Zimbra and the IdP live on different hosts (zimbra.lan vs
    // idp.lan) => the SSO cookies must be cross-site capable.
    'session.cookie.secure' => true,
    'session.cookie.samesite' => 'None',
    'session.cookie.path' => '/simplesaml/',

    // Symfony kernel cache (required by SSP 2.x routing).
    'cachedir' => '/var/cache/simplesamlphp',

    // --- Logging -------------------------------------------------
    'loggingdir' => '/var/www/simplesamlphp/logs',
    'logging.level' => 256, // DEBUG
    'logging.handler' => 'file',
    'logging.logfile' => 'simplesamlphp.log',

    'module.enable' => [
        'admin' => true,
        'exampleauth' => true,
    ],

    'languages' => ['en'],
];
