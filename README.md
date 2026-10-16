# Zimbra 9 dev Zimlet lab — SAML SSO with a local SimpleSAMLphp IdP

A reproducible `docker compose` environment for developing and testing Zimlet
code against a real **Zimbra 9** server, with Webmail login via **SAML SSO**
against a **local test IdP** holding static test accounts.

```
        +---------------------------+  proxy   +---------------------------+
browser |  SAML SP proxy (zt-sp)    | -------> |  Zimbra 9 (all-in-one)    |
  <---> |  zimbra.lan:8444          | preauth  |  internal only (zt-net)   |
        |  /simplesaml/  /sso/      |          +---------------------------+
        +---------------------------+
                     ^  SAML (browser redirects / POST)
                     v
        +---------------------------+
        |  SimpleSAMLphp IdP        |
        |  idp.lan:8445             |
        |  static users (alice,...) |
        +---------------------------+
                        dnsmasq (10.9.0.2) on a fixed-subnet bridge network
```

Zimbra FOSS has no SAML receiver (the native `samlextn.jar` is a Network
Edition feature), so a **SAML SP proxy** sits in front of the webmail: it
does the SAML exchange with the IdP, then logs the user into Zimbra with
Zimbra's built-in **domain preauth**.

## Quick start

Create your `.env` from the sample and adjust it if needed:

```bash
cp env.sample .env
```

Then:

```bash
make up          # render configs, build IdP image, start stack, run first-boot init
make test        # full end-to-end validation (SSO handshake, accounts, zimlet cycle)
```

First boot of Zimbra takes **10-20 minutes**. `make up` waits for it.

After that:

```bash
# Webmail (accept the self-signed cert once per browser):
#   https://zimbra.lan:8444/
# Login is redirected to the IdP. Test accounts (from .env):
#   alice@example.local / alice-pass
#   bob@example.local   / bob-pass
# Admin console: https://zimbra.lan:8444/admin (admin / Zimbra2021)
```

## Zimlet workflow

1. Build your Zimlet (e.g. `make build-example-zimlet` produces
   `zimlets/com_zimbra_testbed_hello.zip` from `zimlets/example-zimlet/`).
2. Drop the `.zip` in `./zimlets/`.
3. `make install-zimlet NAME=com_zimbra_testbed_hello`
   (`zmzimletctl -l deploy`: installs, enables and grants it to the `default`
   COS, then flushes the zimlet cache; reload Webmail to see it).
4. `make remove-zimlet NAME=...`, `make zimlets` to list.
5. Log into Webmail as `alice` and see your Zimlet. The example zimlet shows
   a "Testbed" panel item and a content balloon on the string `TESTBED-OK`
   in message text.

## Layout

| Path | Purpose |
|---|---|
| `env.sample` → `.env` | **Single source of truth** (`.env` is git-ignored): hostnames, domain, subnet, ports, admin password, test users |
| `docker-compose.yml` | dns / zimbra / idp / sp services |
| `idp/` | IdP image (Dockerfile, also used by `sp`), config templates, render script, generated certs |
| `sp/` | SAML SP proxy: SSP SP config templates, nginx site, `/sso/` login/logout scripts, render script, generated cert + preauth key |
| `zimbra-init/` | Container entrypoint, package fixes (`fix-packages.sh`) + init script (domain, mailboxes, preauth / SSO settings) |
| `scripts/` | `render-config.sh`: IdP + SP config, secrets and certs from `.env` |
| `zimlets/` | Your Zimlet `.zip` files (mounted into the container) |
| `tests/` | Validation suite: `validate.sh` + `sso_handshake.py` |
| `zimbra-storage/` | Zimbra state (git-ignored, survives `make down`) |

## What `make up` / init does

1. `scripts/render-config.sh` renders the IdP config from `idp/templates/`
   + `.env` (static users from `IDP_USERS`) and the SP proxy config from
   `sp/templates/`. It generates once the self-signed certs, the SSP secrets
   and the shared **preauth key** (`sp/.preauth_key`).
2. `.env` and `sp/.preauth_key` are mounted read-only into the Zimbra
   container (`/opt/zt-env/`), where `init.sh` reads them.
3. Starts dnsmasq + Zimbra + IdP + SP proxy on a fixed-subnet bridge network
   (Zimbra needs a stable, resolvable hostname). The SP proxy owns the
   public webmail port; Zimbra's HTTPS is only reachable through it.
4. Runs `zimbra-init/init.sh` **inside the Zimbra container** (idempotent):
   - waits for all Zimbra services
   - creates the `example.local` domain with `zimbraVirtualHostName
     zimbra.lan`, and removes that virtual host from the installer's
     bootstrap domain (`lan`) so the lookup is unambiguous
   - creates the test mailboxes from `ZIMBRA_MAILBOXES`
   - sets on the domain: `zimbraPreAuthKey`, `zimbraWebClientLoginURL` /
     `zimbraWebClientLogoutURL` (→ the proxy's `/sso/`), and
     `zimbraPublicService*` (→ `https://zimbra.lan:8444`)
   - puts Zimbra's nginx in `both` mode (HTTPS on 443) with plain HTTP to
     mailboxd, then restarts the proxy and mailboxd

## SAML flow (SP-initiated)

1. Browser opens `https://zimbra.lan:8444/` → the proxy forwards to Zimbra,
   whose login page redirects to `zimbraWebClientLoginURL` =
   `https://zimbra.lan:8444/sso/login.php`.
2. `login.php` has no SAML session yet → SSP sends an AuthnRequest to the
   IdP, which shows its login form (static users).
3. On success the IdP posts a signed SAML Response (NameID = email, `mail`
   attribute) to the SP's ACS
   `/simplesaml/module.php/saml/sp/saml2-acs.php/default-sp`; SSP verifies
   it and returns to `login.php`.
4. `login.php` signs a preauth URL for the `mail` value
   (`HMAC-SHA1(key, "account|name|0|timestamp")`) and redirects to
   `/service/preauth`; Zimbra checks it and sets `ZM_AUTH_TOKEN`.
5. Logout: Zimbra → `zimbraWebClientLogoutURL` (`/sso/logout.php`) → SAML
   single logout at the IdP → `/sso/logged-out.html`.
6. `tests/sso_handshake.py` replays steps 1-4 with no browser and proves
   the session with a SOAP `GetInfoRequest`. It also runs the **negative
   case**: `ghost@example.local` authenticates at the IdP but has no Zimbra
   mailbox, so Zimbra's preauth must reject it (HTTP 400).

## Testing manually

`make test` covers the critical path automatically. Use this for interactive
checks — everything below runs from the **host**. Add these lines to your
host's `/etc/hosts` for host-side resolution:

```
127.0.0.1  zimbra.lan
127.0.0.1  idp.lan
```

(The SSO URLs use the host ports 8444/8445, so the names must point at the
host, not at the container IPs.)

**1. Stack health**

```bash
docker compose ps          # dns, zimbra, idp, sp — all "healthy"
make saml-check            # SP metadata + domain SSO attributes
```

**2. IdP standalone**

```bash
# Metadata is served (entity id + signing cert):
curl -k https://idp.lan:8445/simplesaml/saml2/idp/metadata.php | head -20
# Login form directly (bypasses Zimbra):
curl -k "https://idp.lan:8445/simplesaml/module/core/userpass.php" | grep -i form
```

**3. SSO login in a browser** (accept the self-signed certs once)

1. Open `https://zimbra.lan:8444/` — you are redirected via
   `/sso/login.php` to the IdP login form on `https://idp.lan:8445/`.
   If you see the **Zimbra** login form instead, SSO is not wired up
   (`make saml-check` + Troubleshooting).
2. Log in as `alice@example.local` / `alice-pass` → you land in Webmail as
   alice. The same works for `bob@example.local` / `bob-pass`.
3. **Negative case:** log in as `ghost@example.local` / `ghost-pass`. The IdP
   accepts it, but Zimbra has no such mailbox and must reject the login
   (preauth answers "authentication failed").
4. Use Webmail's *Sign out*: you end on `/sso/logged-out.html`, and the
   next visit asks for IdP credentials again.

**4. Admin console**

`https://zimbra.lan:8444/admin` with `admin@localhost` / the admin
password from `.env`. Verify domain `example.local` and the test accounts
under *Domains → example.local → Accounts*.

**5. Accounts & SAML attributes from the shell**

```bash
docker compose exec -u zimbra zimbra /opt/zimbra/bin/zmprov gaa
docker compose exec -u zimbra zimbra /opt/zimbra/bin/zmprov ga alice@example.local
docker compose exec -u zimbra zimbra /opt/zimbra/bin/zmprov -l gd example.local \
  zimbraWebClientLoginURL zimbraWebClientLogoutURL zimbraPublicServicePort
```

**6. IMAP (proves the mailbox is real, independent of SAML)**

```bash
python3 - <<'EOF'
import imaplib
m = imaplib.IMAP4_SSL("zimbra.lan", 1093)
m.login("alice@example.local", "alice-pass")   # values from .env
print(m.select("INBOX"))
EOF
```

**7. Mail between test users** — in Webmail as alice, send a message to
bob@example.local (mail stays on the server, no outbound MX). Open it as bob.
Useful to test mail-reading features in a Zimlet.

**8. Zimlet cycle by hand**

```bash
make build-example-zimlet                                   # build the sample
make install-zimlet NAME=com_zimbra_testbed_hello
docker compose exec -u zimbra zimbra /opt/zimbra/bin/zmzimletctl -l listZimlets
make remove-zimlet NAME=com_zimbra_testbed_hello
```

In Webmail as alice: the sample zimlet adds a "Testbed" panel item, and a
balloon appears when you open a message containing `TESTBED-OK` — so send
alice a mail with that string (step 7) and check it.

## Notes & decisions

- **Local password login is left enabled** (no `zimbraAuthFallbackToLocal
  FALSE`) so a broken SAML config can't lock you out: open
  `https://zimbra.lan:8444/?ignoreLoginURL=1` to get Zimbra's own form.
- The SSO entry URL is stored in `zimbraWebClientLoginURL`; Zimbra's login
  page redirects there automatically. It finds the domain by virtual host,
  so exactly one domain may own `zimbra.lan`.
- The preauth key is a shared secret between `sp/` and Zimbra: anyone with
  it can log in as any account. It stays in git-ignored `sp/.preauth_key`.
- The `sp` service runs the IdP image with a different entrypoint
  (`sp/entrypoint.sh`) — one SimpleSAMLphp build for both roles.
- Mail stays internal (no outbound MX): sending between alice/bob works,
  which is handy for testing.

## Troubleshooting

```bash
make saml-check        # SP metadata, domain preauth / login / logout URLs
docker compose logs idp sp
docker compose exec sp tail -50 /var/www/simplesamlphp/logs/simplesamlphp.log
docker compose exec -u zimbra zimbra tail -100 /opt/zimbra/log/mailbox.log
# grep mailbox.log for: preauth, authentication failed
```

- **Zimbra login form instead of the IdP** → `zimbraWebClientLoginURL` not
  applied: check that only `example.local` has `zimbraVirtualHostname
  zimbra.lan`, then `zmmailboxdctl restart` (the webclient caches the
  domain lookup).
- **"authentication failed" after IdP login** → no such mailbox (expected
  for `ghost`), or `zimbraPreAuthKey` ≠ `sp/.preauth_key` (`make test`
  checks it; `make init` re-applies it).
- **Redirects to port 8443** → something built a URL from an in-container
  port; check `baseurlpath` in the rendered SSP configs.
- **Cert errors in the browser** → expected (self-signed, one for
  `zimbra.lan`, one for `idp.lan`). Trust both once.
- **Zimbra never comes up** → watch `docker compose logs zimbra`; first boot
  is slow, RAM-hungry (≥ 4 GB recommended).
- **Port clashes** → change `ZIMBRA_HTTPS_PORT` / `IDP_HTTPS_PORT` in `.env`
  (they are also baked into the SAML URLs, so re-run `make up` and
  `make init`).

## Destroying the environment

```bash
make destroy   # removes containers AND zimbra-storage/ + IdP certs
```


## AI-assisted development

This project was developed with the assistance of AI models, primarily Qwen models provided by the ILAAS platform, with occasional contributions from Claude Opus. These tools were used to support implementation, troubleshooting, and documentation. All generated contributions remain subject to developer review and validation.

## License

[MIT](LICENSE)
