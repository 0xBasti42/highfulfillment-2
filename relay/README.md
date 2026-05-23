# HighPotential Relay

A small, security-hardened HTTP relay that forwards outbound API calls from a
fixed set of static IPs whitelisted by upstream data providers.

The relay accepts authenticated inbound requests describing a target URL, validates
the URL against a strict allowlist (with SSRF defenses), and forwards the call
upstream. Responses are returned to the caller.

This service is designed to run on small AWS Lightsail instances behind a Caddy
TLS reverse proxy. Each instance has its own static IPv4, and each of those IPs
is registered with the data provider.

---

## Architecture

```
Caller (Supabase Edge Fn / SvelteKit server)
        │  HTTPS + Bearer API key
        ▼
   Caddy (auto Let's Encrypt)              ┐
        │  http://relay:3000               │  Lightsail instance
        ▼                                  │  static IP (whitelisted)
   Fastify relay                           │
        │  outbound HTTPS                  ┘
        ▼
   Data provider API
```

The same static IP is used for ingress (caller → Caddy) and egress (relay →
provider). That is the property that makes Lightsail a good fit here.

---

## Repository layout

```
relay/
├── src/
│   ├── server.ts        Fastify app + route registration
│   ├── proxy.ts         Forwarding logic (undici)
│   ├── allowlist.ts     URL allowlist + SSRF defenses
│   ├── auth.ts          API key middleware
│   ├── config.ts        Environment loading + validation
│   └── logger.ts        Pino logger
├── infra/
│   ├── setup.sh         One-time bootstrap for a fresh Lightsail instance
│   └── Caddyfile        TLS reverse proxy config
├── .github/workflows/
│   ├── ci.yml           Lint + typecheck + test on PRs
│   └── deploy.yml       Build + push to GHCR + SSH deploy to instances
├── Dockerfile
├── docker-compose.yml
├── package.json
├── tsconfig.json
└── README.md
```

---

## API

### `POST /v1/relay`

Forwards a single request to a whitelisted upstream.

**Headers**
```
Authorization: Bearer <RELAY_API_KEY>
Content-Type:  application/json
```

**Body**
```json
{
  "url":     "https://api.example-provider.com/v1/players?week=12",
  "method":  "GET",
  "headers": { "X-Provider-Key": "..." },
  "body":    null
}
```

`method`, `headers`, and `body` are optional. Default method is `GET`.

**Response**
```json
{
  "status":  200,
  "headers": { "content-type": "application/json" },
  "body":    "<upstream response, base64-encoded if non-text>"
}
```

### `GET /v1/health`

Liveness probe. Returns `{ ok: true, version: "<sha>" }`. Does not call the
upstream — use a separate readiness probe if you want a real upstream check.

---

## Local development

```bash
cp .env.example .env
# fill in RELAY_API_KEY and ALLOWED_HOSTS at minimum
npm install
npm run dev
```

The relay listens on `http://127.0.0.1:3000` by default.

```bash
curl -sS http://127.0.0.1:3000/v1/relay \
  -H "Authorization: Bearer $RELAY_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"url":"https://api.example-provider.com/v1/ping"}'
```

---

## Provisioning a Lightsail instance

1. Create a new Lightsail instance (Ubuntu 22.04 LTS, `nano` or `micro`,
   region close to the data provider's API).
2. Attach a Static IP and record it.
3. Open ports `22` (restricted to your IP), `80`, and `443` in the Lightsail
   firewall.
4. Add a DNS record pointing your relay subdomain at the static IP
   (e.g. `relay-1.highpotential.xyz` → `<static IP>`).
5. SSH in and run the bootstrap:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/<org>/highpotential-relay/main/infra/setup.sh \
     | RELAY_DOMAIN=relay-1.highpotential.xyz \
       RELAY_IMAGE=ghcr.io/<org>/highpotential-relay:latest \
       sudo -E bash
   ```
6. Place the production `.env` at `/opt/relay/.env` (see `.env.example` for
   required keys), then:
   ```bash
   sudo systemctl restart relay-stack
   ```
7. Register the static IP with the data provider's IP allowlist.

Repeat for each instance. Each instance is fully independent — there is no
shared state.

---

## Deployment

Pushes to `main` trigger the `deploy.yml` workflow, which:

1. Builds a Docker image and pushes to GHCR tagged with the commit SHA and `latest`.
2. SSHes into every host listed in the `LIGHTSAIL_HOSTS` GitHub secret and runs
   `docker compose pull && docker compose up -d` against `/opt/relay/docker-compose.yml`.

Required GitHub Actions secrets:

| Secret              | Purpose                                                  |
| ------------------- | -------------------------------------------------------- |
| `LIGHTSAIL_HOSTS`   | Newline- or comma-separated list of `user@ip` targets.   |
| `LIGHTSAIL_SSH_KEY` | Private SSH key with access to all instances.            |
| `GHCR_USERNAME`     | GitHub username or org slug for GHCR auth.               |
| `GHCR_TOKEN`        | PAT with `read:packages` (or use the default token).     |

---

## Security posture

- All inbound traffic terminates TLS at Caddy with Let's Encrypt.
- All requests must carry a valid `Authorization: Bearer …` token; comparison is
  constant-time.
- Outbound URLs are validated against `ALLOWED_HOSTS` (exact match or `.suffix`).
- Hostnames are resolved before the call, and any answer that includes a
  private, loopback, link-local, or multicast IP is rejected — basic SSRF and
  DNS-rebinding defense.
- Outbound protocol is restricted to `https:`.
- Outbound redirects are not followed by default (`MAX_REDIRECTS=0`).
- Inbound and outbound bodies are capped (`MAX_BODY_BYTES`).
- Outbound calls have a hard timeout (`UPSTREAM_TIMEOUT_MS`).
- Rate-limited per-API-key by Fastify's built-in limiter.

If you discover a security issue, do not open a public issue — contact the
maintainers directly.
