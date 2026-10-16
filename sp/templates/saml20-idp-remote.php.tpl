<?php
// TEMPLATE — rendered by sp/render-config.sh from .env.
// The testbed IdP as seen by the SP proxy.

$metadata['https://__IDP_HOST__:__IDP_HTTPS_PORT__/simplesaml/saml2/idp/metadata.php'] = [
    'SingleSignOnService' => [
        [
            'Binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect',
            'Location' => 'https://__IDP_HOST__:__IDP_HTTPS_PORT__/simplesaml/saml2/idp/SSOService.php',
        ],
    ],
    'SingleLogoutService' => [
        [
            'Binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect',
            'Location' => 'https://__IDP_HOST__:__IDP_HTTPS_PORT__/simplesaml/saml2/idp/SingleLogoutService.php',
        ],
    ],
    // IdP signing cert (= ./idp/certs/idp.crt), copied into certdir.
    'certificate' => 'idp.crt',
];
