#!/usr/bin/env bash
#
# One-time bootstrap for a fresh Lightsail (Ubuntu 22.04+) instance.
#
# Required environment variables:
#   RELAY_DOMAIN        FQDN that points at this instance's static IP.
#   RELAY_IMAGE         Fully-qualified container image (e.g. ghcr.io/org/highpotential-relay:latest).
#
# Optional:
#   RELAY_ACME_EMAIL    Email registered with Let's Encrypt (default: admin@$RELAY_DOMAIN).
#   RELAY_USER          Unix user that owns /opt/relay (default: relay).
#   GHCR_USERNAME       If set together with GHCR_TOKEN, used to docker login to GHCR.
#   GHCR_TOKEN          GitHub PAT (read:packages) for private images.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/<org>/highpotential-relay/main/infra/setup.sh \
#     | RELAY_DOMAIN=relay-1.example.com RELAY_IMAGE=ghcr.io/<org>/highpotential-relay:latest \
#       sudo -E bash

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
	echo "setup.sh must run as root (use sudo -E)." >&2
	exit 1
fi

: "${RELAY_DOMAIN:?RELAY_DOMAIN must be set}"
: "${RELAY_IMAGE:?RELAY_IMAGE must be set}"
RELAY_ACME_EMAIL="${RELAY_ACME_EMAIL:-admin@${RELAY_DOMAIN}}"
RELAY_USER="${RELAY_USER:-relay}"
RELAY_HOME="/opt/relay"

echo "==> Updating apt and installing prerequisites"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
	ca-certificates curl gnupg lsb-release ufw unattended-upgrades

echo "==> Enabling unattended security upgrades"
dpkg-reconfigure -f noninteractive unattended-upgrades

if ! command -v docker >/dev/null 2>&1; then
	echo "==> Installing Docker Engine"
	install -m 0755 -d /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
		| gpg --dearmor -o /etc/apt/keyrings/docker.gpg
	chmod a+r /etc/apt/keyrings/docker.gpg
	. /etc/os-release
	echo \
		"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
		https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
		>/etc/apt/sources.list.d/docker.list
	apt-get update -y
	apt-get install -y --no-install-recommends \
		docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
	systemctl enable --now docker
fi

if ! id "${RELAY_USER}" >/dev/null 2>&1; then
	echo "==> Creating ${RELAY_USER} user"
	useradd --system --create-home --home-dir "${RELAY_HOME}" \
		--shell /usr/sbin/nologin "${RELAY_USER}"
	usermod -aG docker "${RELAY_USER}"
fi

mkdir -p "${RELAY_HOME}"
chown "${RELAY_USER}:${RELAY_USER}" "${RELAY_HOME}"

echo "==> Configuring host firewall (ufw)"
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "==> Writing /opt/relay/docker-compose.yml"
cat >"${RELAY_HOME}/docker-compose.yml" <<COMPOSE
name: relay

services:
  relay:
    image: ${RELAY_IMAGE}
    container_name: relay
    restart: always
    env_file:
      - .env
    expose:
      - "3000"
    networks:
      - edge
    read_only: true
    tmpfs:
      - /tmp:size=16m
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"

  caddy:
    image: caddy:2.8-alpine
    container_name: relay-caddy
    restart: always
    depends_on:
      - relay
    ports:
      - "80:80"
      - "443:443"
    environment:
      - RELAY_DOMAIN=\${RELAY_DOMAIN}
      - RELAY_ACME_EMAIL=\${RELAY_ACME_EMAIL}
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - edge
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"

networks:
  edge:
    driver: bridge

volumes:
  caddy_data:
  caddy_config:
COMPOSE

echo "==> Writing /opt/relay/Caddyfile"
cat >"${RELAY_HOME}/Caddyfile" <<'CADDY'
{
	email {$RELAY_ACME_EMAIL}
	servers {
		trusted_proxies static private_ranges
	}
}

{$RELAY_DOMAIN} {
	encode zstd gzip

	header {
		Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
		X-Content-Type-Options "nosniff"
		Referrer-Policy "no-referrer"
		-Server
	}

	@health path /v1/health
	handle @health {
		reverse_proxy relay:3000
	}

	handle {
		reverse_proxy relay:3000 {
			header_up X-Forwarded-Host {host}
		}
	}

	log {
		output stdout
		format json
	}
}
CADDY

if [[ ! -f "${RELAY_HOME}/.env" ]]; then
	echo "==> Seeding placeholder /opt/relay/.env (fill in before first start)"
	cat >"${RELAY_HOME}/.env" <<ENV
RELAY_DOMAIN=${RELAY_DOMAIN}
RELAY_ACME_EMAIL=${RELAY_ACME_EMAIL}

RELAY_API_KEY=replace-me-with-32+-char-secret
ALLOWED_HOSTS=api.example-provider.com

HOST=0.0.0.0
PORT=3000
LOG_LEVEL=info

MAX_BODY_BYTES=1048576
UPSTREAM_TIMEOUT_MS=15000
MAX_REDIRECTS=0

RATE_LIMIT_MAX=120
RATE_LIMIT_WINDOW_MS=60000

RELAY_VERSION=dev
ENV
	chmod 600 "${RELAY_HOME}/.env"
fi

chown -R "${RELAY_USER}:${RELAY_USER}" "${RELAY_HOME}"

if [[ -n "${GHCR_USERNAME:-}" && -n "${GHCR_TOKEN:-}" ]]; then
	echo "==> Logging Docker into GHCR"
	echo "${GHCR_TOKEN}" | sudo -u "${RELAY_USER}" docker login ghcr.io \
		--username "${GHCR_USERNAME}" --password-stdin
fi

echo "==> Writing systemd unit relay-stack.service"
cat >/etc/systemd/system/relay-stack.service <<UNIT
[Unit]
Description=HighPotential relay stack (relay + Caddy)
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${RELAY_HOME}
EnvironmentFile=${RELAY_HOME}/.env
ExecStartPre=/usr/bin/docker compose pull
ExecStart=/usr/bin/docker compose up -d --remove-orphans
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable relay-stack.service

echo
echo "==> Bootstrap complete."
echo
echo "Next steps:"
echo "  1. Edit ${RELAY_HOME}/.env and set RELAY_API_KEY + ALLOWED_HOSTS."
echo "  2. Confirm DNS: ${RELAY_DOMAIN} -> $(curl -fsS https://api.ipify.org || echo this-instance)"
echo "  3. systemctl start relay-stack"
echo "  4. Tail logs:  docker logs -f relay   |   docker logs -f relay-caddy"
echo "  5. Curl:       curl -i https://${RELAY_DOMAIN}/v1/health"
