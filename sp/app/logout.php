<?php
// SSO exit (= the domain's zimbraWebClientLogoutURL). Zimbra has already
// dropped its own session; end the SP session and, via SLO, the IdP's.
declare(strict_types=1);

require '/var/www/simplesamlphp/src/_autoload.php';
$cfg = require '/etc/zt-sp/sso.php';

$as = new \SimpleSAML\Auth\Simple($cfg['auth_source']);
$done = $cfg['public_url'] . '/sso/logged-out.html';
if ($as->isAuthenticated()) {
    $as->logout($done);
}
header('Location: ' . $done, true, 302);
