#!/usr/bin/env python3
"""
SP-initiated SAML SSO handshake against the Zimbra testbed, no browser.

Flow (SAML SP proxy in front of the webmail, see ./sp):
  1. GET  https://<zimbra>/sso/login.php  (= zimbraWebClientLoginURL)
     -> SP AuthnRequest -> the IdP's login form
  2. POST the static credentials to the login form
  3. Parse the auto-submit form the IdP returns (SAMLResponse -> SP ACS)
  4. POST SAMLResponse to the SP ACS; it redirects back to login.php,
     which redirects to Zimbra's /service/preauth (sets ZM_AUTH_TOKEN)
  5. Verify the resulting cookie grants a Zimbra session for the expected
     account (SOAP GetInfoRequest).

Usage:
  sso_handshake.py <username> <password> <expected-email> [--expect-fail]

Exit code: 0 when the outcome matches expectation, 1 otherwise.
"""
import html
import http.cookiejar
import re
import ssl
import sys
import urllib.parse
import urllib.request
import os

IDP = f"https://{os.environ['IDP_HOST']}:{os.environ['IDP_HTTPS_PORT']}"
SP = f"https://{os.environ['ZIMBRA_HOST']}:{os.environ['ZIMBRA_HTTPS_PORT']}"
SSO_ENTRY = f"{SP}/sso/login.php"

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE


def main() -> int:
    args = [a for a in sys.argv[1:] if a != "--expect-fail"]
    expect_fail = "--expect-fail" in sys.argv
    if len(args) != 3:
        print("usage: sso_handshake.py <username> <password> <expected-email> [--expect-fail]")
        return 2
    user, pw, expected = args

    cj = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(cj),
        urllib.request.HTTPSHandler(context=ctx),
    )
    opener.addheaders = [("Referer", f"{IDP}/")]

    def fetch(url, data=None, referer=None):
        req = urllib.request.Request(url, data=data)
        if referer:
            req.add_header("Referer", referer)
        try:
            return opener.open(req, timeout=30).read().decode("utf-8", "replace")
        except urllib.error.HTTPError as e:
            return e.read().decode("utf-8", "replace")

    def parse_form(page):
        m = re.search(r"<form[^>]*action=[\"']([^\"']+)[\"']", page)
        if not m:
            return None, {}
        action = m.group(1)
        fields = {}
        for im in re.finditer(r"<input[^>]*>", page):
            tag = im.group(0)
            nm = re.search(r"name=[\"']([^\"']+)[\"']", tag)
            if nm:
                vm = re.search(r"value=[\"']([^\"']*)[\"']", tag)
                fields[nm.group(1)] = html.unescape(vm.group(1)) if vm else ""
        return action, fields

    def resolve(action):
        if action.startswith("http"):
            return action
        return urllib.parse.urljoin(IDP + "/", action)

    def soap_getinfo():
        # Pass ZM_AUTH_TOKEN in the SOAP context: cookie-only auth would
        # also need a CSRF token. GetInfo lives in urn:zimbraAccount.
        token = next((c.value for c in cj if c.name == "ZM_AUTH_TOKEN"), "")
        body = (
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">'
            '<soap:Header><context xmlns="urn:zimbra">'
            f"<authToken>{html.escape(token)}</authToken></context></soap:Header>"
            '<soap:Body><GetInfoRequest xmlns="urn:zimbraAccount" sections="mbox"/>'
            "</soap:Body></soap:Envelope>"
        )
        req = urllib.request.Request(
            f"{SP}/service/soap/GetInfoRequest",
            data=body.encode(),
            # Like the webmail's own calls. The opener-wide IdP Referer
            # would fail Zimbra's CSRF Referer check (403).
            headers={"Content-Type": "text/xml; charset=utf-8", "Referer": f"{SP}/"},
        )
        try:
            out = opener.open(req, timeout=30).read().decode("utf-8", "replace")
        except urllib.error.HTTPError as e:
            out = e.read().decode("utf-8", "replace")
        m = re.search(r"<name>([^<]+)</name>", out)
        return m.group(1) if m else None

    # --- 1. SP-initiated SSO entry -----------------------------
    page = fetch(SSO_ENTRY)
    action, fields = parse_form(page)
    if action is None:
        print("  FAIL: SSO entry did not lead to the IdP login form")
        print("  page head:", page[:400].replace("\n", " "))
        # Broken plumbing is never a valid rejection, even with --expect-fail.
        return 1
    print(f"  IdP login form at {action}")

    # --- 2. POST credentials ------------------------------------
    fields["username"] = user
    fields["password"] = pw
    data = urllib.parse.urlencode(fields).encode()
    page = fetch(action, data=data, referer=f"{IDP}/")

    if "SAMLResponse" not in page:
        # The test users are all valid at the IdP: rejection must come from
        # Zimbra (no mailbox), not from a broken IdP step.
        print(f"  FAIL: IdP did not produce a SAMLResponse (got: {page[:200]!r})")
        return 1

    # --- 3. Auto-post form to ACS -------------------------------
    action2, saml_fields = parse_form(page)
    if action2 is None or "SAMLResponse" not in saml_fields:
        print("  FAIL: could not parse SAMLResponse auto-post form")
        print("  page head:", page[:400].replace("\n", " "))
        return 1
    print(f"  SAMLResponse -> {action2}")

    # --- 4. POST to the SP ACS (-> login.php -> Zimbra preauth) --
    data = urllib.parse.urlencode(saml_fields).encode()
    page = fetch(action2, data=data, referer=f"{IDP}/")
    cookies = [c.name for c in cj]
    print(f"  After ACS POST + preauth, cookies: {cookies}")

    # --- 5. Verify session identity -----------------------------
    identity = soap_getinfo()
    print(f"  SOAP GetInfo identity: {identity}")

    if expect_fail:
        ok = identity is None or identity != expected
        print(f"  expect-fail: {'OK (rejected as expected)' if ok else 'FAIL (login unexpectedly succeeded)'}")
        return 0 if ok else 1

    ok = identity == expected
    print(f"  SSO result: {'OK' if ok else 'FAIL'} (expected {expected})")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
