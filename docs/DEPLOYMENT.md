# Cocarr Platform — Deployment Topology & Railway Guide

This is the platform-wide map. Each service repo also has its own
`docs/DEPLOYMENT.md` and `.env.example` with the authoritative variable list.

## Migration status (old → new)

| Old repo | New production repo | Status |
|---|---|---|
| `COCARR-BACKEND` | [`cocarr-core-api`](https://github.com/CoCarr-org/cocarr-core-api) | ✅ migrated, build-verified, deploy config added |
| `COCARR-ADMIN` | [`cocarr-platform-web`](https://github.com/CoCarr-org/cocarr-platform-web) | ✅ migrated, build-verified, deploy config added |
| — | identity / authorization / workspace / gateway / notification / DBs | ⬜ planned |

The old repos remain the live deployment until the new ones are wired and cut
over. Nothing is retired yet.

## Target Railway services (current phase)

| Service | Repo / branch | Builder | Start | Notes |
|---|---|---|---|---|
| `core-api` | cocarr-core-api @ `develop` | Dockerfile | `node index.js` | Needs MySQL + all secrets |
| `mysql` | Railway MySQL plugin | — | — | Or external MySQL 8 |
| `web-admin` | cocarr-platform-web @ `develop` | Nixpacks | `npm run start` | `NEXT_PUBLIC_PANEL=admin` |
| `web-root` (later) | cocarr-platform-web @ `develop` | Nixpacks | `npm run start` | `NEXT_PUBLIC_PANEL=root` |
| `web-<team>` (later) | cocarr-platform-web @ `develop` | Nixpacks | `npm run start` | one per panel |

**Every web panel is a separate service building the same repo** with a
different `NEXT_PUBLIC_PANEL` — `NEXT_PUBLIC_*` is inlined at build time.

## Request flow (today)
```
Browser (admin.cocarr.com, ...)  ──►  core-api (/v1)  ──►  MySQL
        │                                   │
        └─ Firebase Auth (admin project)    └─ Firebase Admin, Razorpay, KYC, Storage, SendGrid
```
The charter's api-gateway / identity / authorization split is a **later** phase;
today core-api serves those responsibilities in-process (`resolveAccess`,
`requirePermission`, panel binding).

## Environment variables — where they live
- **core-api:** `cocarr-core-api/.env.example` — DB, Firebase ×2, RBAC/panels,
  storage (`STORAGE_*`/`S3_*`/`AWS_*` aliases), Razorpay (`PG_*`), KYC, SendGrid,
  MSG91, cron flags.
- **platform-web:** `cocarr-platform-web/.env.example` — `NEXT_PUBLIC_PANEL`, API
  base (+ legacy `REACT_APP_*`), public Firebase config, cross-panel host map,
  panel key/gateway.

## Manual steps that require your access (cannot be automated from here)
1. Railway account: create the project + services, connect the GitHub repos.
2. Provision MySQL; copy connection details into core-api `DB_*`.
3. Paste real secrets into each service's Variables (Firebase service-account
   JSON, `PG_*`, `KYC_*`, `STORAGE_*`, `SENDGRID_API_KEY`, `MSG_KEY`,
   `BOOTSTRAP_SUPER_ADMIN_PASSWORD`, `PANEL_KEY`).
4. Domains: map `api.` / `admin.` / per-panel hosts; set `PUBLIC_API_URL`,
   `CORS_ORIGINS`, `ADMIN_PANEL_ORIGINS`, `NEXT_PUBLIC_BASE_URL` accordingly.
5. Verify core-api boots (DB reachable, bootstrap super-admin created), then the
   admin panel signs in end-to-end, before cutting DNS over from the old repos.

## Local development
```bash
docker compose -f docker/docker-compose.dev.yml up -d   # MySQL + Adminer (:8080)
# cocarr-core-api:    cp .env.example .env && npm install && npm run dev
# cocarr-platform-web: cp .env.example .env.local && npm install && npm run dev
```
