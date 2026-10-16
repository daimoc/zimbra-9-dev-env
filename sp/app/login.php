<?php
// SSO entry (= the domain's zimbraWebClientLoginURL).
// 1. Require a SAML session with the IdP (redirects there if needed).
// 2. Turn the asserted email into a Zimbra session via domain preauth:
//    preauth = HMAC-SHA1(key, "account|name|expires|timestamp")
//    https://wiki.zimbra.com/wiki/Preauth
declare(strict_types=1);

require '/var/www/simplesamlphp/src/_autoload.php';
$cfg = require '/etc/zt-sp/sso.php';

$as = new \SimpleSAML\Auth\Simple($cfg['auth_source']);
// Explicit ReturnTo: /sso/ is outside baseurlpath, so SSP would otherwise
// derive it from the in-container port (8443) instead of the public one.
$as->requireAuth(['ReturnTo' => $cfg['public_url'] . '/sso/login.php']);

$attrs = $as->getAttributes();
$account = $attrs[$cfg['account_attribute']][0] ?? '';
if ($account === '') {
    http_response_code(403);
    exit("SSO: the IdP did not release the '{$cfg['account_attribute']}' attribute.");
}

$timestamp = (string) (int) round(microtime(true) * 1000);
$expires = '0'; // use the account's default auth token lifetime
$preauth = hash_hmac('sha1', "{$account}|name|{$expires}|{$timestamp}", $cfg['preauth_key']);

// Zimbra answers with an error page (no redirect, so no loop) when the
// account doesn't exist — that's how an IdP-only user gets rejected.
header('Location: /service/preauth?' . http_build_query([
    'account' => $account,
    'by' => 'name',
    'timestamp' => $timestamp,
    'expires' => $expires,
    'preauth' => $preauth,
]), true, 302);
