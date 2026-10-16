<?php
// TEMPLATE — rendered by render-config.sh from .env.
// Hosted IdP configuration (SimpleSAMLphp 2.4).

// Array key = IdP entity ID (stable, public URL).
$metadata['https://__IDP_HOST__:__IDP_HTTPS_PORT__/simplesaml/saml2/idp/metadata.php'] = [
    // Single-tenant test IdP: apply to whatever host serves it.
    'host' => '__DEFAULT__',

    // Certs live in /var/www/simplesamlphp/certs/ (idp.crt / idp.key).
    'certificate' => 'idp.crt',
    'privatekey' => 'idp.key',

    // Which auth source (authsources.php) backs this IdP.
    'auth' => 'static',

    // Sign the response and the assertion; Zimbra verifies the IdP cert.
    'signResponse' => true,
    'signAssertion' => true,

    // Don't require the SP (Zimbra) to sign its AuthnRequest.
    'validateSignRequest' => false,

    // Release these attributes to the SP (map to themselves by default).
    'attributes' => [
        'uid' => ['uid'],
        'mail' => ['mail'],
        'displayName' => ['displayname'],
    ],
];
