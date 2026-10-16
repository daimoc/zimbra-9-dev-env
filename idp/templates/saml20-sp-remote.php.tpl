<?php
// TEMPLATE — rendered by render-config.sh from .env.
// The SAML SP proxy in front of the Zimbra webmail (./sp), as seen by the IdP.
// Entity ID / endpoints are SimpleSAMLphp 2.x defaults for the 'default-sp'
// auth source and must match sp/templates/authsources.php.tpl.

$metadata['https://__ZIMBRA_HOST__:__ZIMBRA_HTTPS_PORT__/simplesaml/module.php/saml/sp/metadata.php/default-sp'] = [
    'AssertionConsumerService' => [
        [
            'Binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST',
            'Location' => 'https://__ZIMBRA_HOST__:__ZIMBRA_HTTPS_PORT__/simplesaml/module.php/saml/sp/saml2-acs.php/default-sp',
            'index' => 0,
            'isDefault' => true,
        ],
    ],
    'SingleLogoutService' => [
        [
            'Binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect',
            'Location' => 'https://__ZIMBRA_HOST__:__ZIMBRA_HTTPS_PORT__/simplesaml/module.php/saml/sp/saml2-logout.php/default-sp',
        ],
    ],

    'NameIDFormat' => 'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress',

    // Build the NameID from the 'mail' attribute (= the Zimbra account).
    'authproc' => [
        10 => [
            'class' => 'saml:AttributeNameID',
            'identifyingAttribute' => 'mail',
            'Format' => 'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress',
        ],
    ],

    // Which auth source (authsources.php) to use for this SP.
    'auth' => 'static',
];
