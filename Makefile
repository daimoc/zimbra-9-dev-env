# Zimbra 9 Zimlet Testbed
#
#   make up            render configs, start the stack, run first-boot init
#   make test          run the full validation suite (tests/validate.sh)
#   make zimlets       list installed zimlets
#   make install-zimlet NAME=example-zimlet
#   make remove-zimlet NAME=example-zimlet
#   make saml-check    show the SSO state (SP proxy metadata, Zimbra domain attrs)
#   make down / make destroy
#
# Drop built Zimlet zips into ./zimlets/ .

COMPOSE ?= docker compose
ZIMBRA  ?= $(COMPOSE) exec -u root zimbra
ZM      ?= $(COMPOSE) exec -u zimbra zimbra
NAME    ?= com_zimbra_testbed_hello

.PHONY: up config init test build-example-zimlet zimlets install-zimlet remove-zimlet saml-check logs down destroy

build-example-zimlet:
	cd zimlets/example-zimlet && zip -r ../$(NAME).zip \
		com_zimbra_testbed_hello.xml testbed_hello.js com_zimbra_testbed_hello.properties
	@echo "Built zimlets/$(NAME).zip"

up: config
	$(COMPOSE) up -d
	@echo "Waiting for Zimbra first boot (this can take 10+ minutes)..."
	$(MAKE) init

config:
	./scripts/render-config.sh

init:
	$(ZIMBRA) /opt/zt-init/init.sh

test:
	./tests/validate.sh

zimlets:
	$(ZM) /opt/zimbra/bin/zmzimletctl -l listZimlets

install-zimlet:
	@test -f zimlets/$(NAME).zip || { echo "zimlets/$(NAME).zip not found (build it first)"; exit 1; }
	$(ZM) /opt/zimbra/bin/zmzimletctl -l deploy /opt/zt-zimlets/$(NAME).zip
	@# deploy keeps the LDAP config of an already-installed version: reapply config_template.xml.
	$(ZM) sh -c '/opt/zimbra/bin/zmzimletctl getConfigTemplate /opt/zt-zimlets/$(NAME).zip > /tmp/$(NAME).config.xml 2>/dev/null \
		&& grep -q "<zimletConfig" /tmp/$(NAME).config.xml && /opt/zimbra/bin/zmzimletctl -l configure /tmp/$(NAME).config.xml; rm -f /tmp/$(NAME).config.xml'
	$(ZM) /opt/zimbra/bin/zmprov flushCache zimlet
	@echo "Deployed (installed, enabled, granted to COS default). Reload Webmail."

remove-zimlet:
	$(ZM) /opt/zimbra/bin/zmzimletctl -l undeploy $(NAME)
	$(ZM) /opt/zimbra/bin/zmprov flushCache zimlet

saml-check:
	@echo "--- SP proxy metadata (entity id / ACS) ---"
	$(COMPOSE) exec sp curl -sk https://localhost:8443/simplesaml/module.php/saml/sp/metadata.php/default-sp 2>&1 \
		| grep -oE '(entityID|Location)="[^"]+"' || true
	@echo "--- domain SSO attributes (preauth key redacted) ---"
	$(ZM) /opt/zimbra/bin/zmprov -l gd example.local 2>/dev/null \
		| grep -iE 'preauth|virtual|login|logout|publicservice' | sed -E 's/(zimbraPreAuthKey: ).*/\1<set>/' || true

logs:
	$(COMPOSE) logs -f

down:
	$(COMPOSE) down

destroy:
	$(COMPOSE) down
	@# zimbra-storage is owned by the container's users (root, zimbra, postfix...):
	@# delete it from a throwaway root container (Zimbra image, already pulled).
	@if [ -d zimbra-storage ]; then \
		docker run --rm -v "$(CURDIR)":/w --entrypoint rm \
			$${ZIMBRA_IMAGE:-iwayvietnam/zimbra_all:latest} -rf /w/zimbra-storage; \
	fi
	rm -rf zimbra-storage idp/certs sp/certs
	@echo "Destroyed. 'make up' will rebuild from scratch."
