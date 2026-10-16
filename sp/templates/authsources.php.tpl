<?php
// TEMPLATE — rendered by sp/render-config.sh from .env.
// The SAML SP the proxy uses to authenticate webmail users against the IdP.

$config = [
    'default-sp' => [
        'saml:SP',
        // Default SSP 2.x entity ID (= its metadata URL); the IdP's
        // saml20-sp-remote.php must use the same value.
        'entityID' => 'https://__ZIMBRA_HOST__:__ZIMBRA_HTTPS_PORT__/simplesaml/module.php/saml/sp/metadata.php/default-sp',
        'idp' => 'https://__IDP_HOST__:__IDP_HTTPS_PORT__/simplesaml/saml2/idp/metadata.php',
        'NameIDPolicy' => [
            'Format' => 'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress',
            'AllowCreate' => true,
        ],
    ],
];
