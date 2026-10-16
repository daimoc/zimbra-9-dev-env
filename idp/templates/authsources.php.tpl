<?php
// TEMPLATE — rendered by render-config.sh from .env.
//
// Static test users for the local SAML IdP (SimpleSAMLphp 2.x).
//
// Uses exampleauth:UserPass. Each entry is "username:password" => [attributes].
// The attributes are released to the SP (see saml20-idp-hosted.php 'attributes').
// We set uid/mail/displayName to the full Zimbra email so Zimbra can map the
// SAML attributes straight onto the account's LDAP uid/mail.

$config = [
    'static' => [
        'exampleauth:UserPass',
        'users' => [__IDP_USERS_PHP__
        ],
    ],
];
