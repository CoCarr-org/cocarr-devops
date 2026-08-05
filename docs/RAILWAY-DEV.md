# Deploying the `dev` environment to Railway

Target hosts:

| Host | Railway service | Repo |
|---|---|---|
| `apis-dev.cocarr.com` | `gateway` | `cocarr-api-gateway` |
| `workspace-dev.cocarr.com` | `workspace-web` | `cocarr-platform-web` (`apps/workspace-web`) |
| `admins-dev.cocarr.com` | `admin-web` | `cocarr-platform-web` (`apps/admin-web`) |

**Only those three get a public domain.** identity, authorization, workspace-api,
core-api and notification stay private and are reached over Railway's internal
network. That is not tidiness — the gateway is the platform's only public API by
design, and a service with a public URL is one whose rate limiting, CORS and
correlation ids are optional.

---

## 0. Before you start

You need:

- The **Firebase admin service-account JSON** (one line). Without it every
  service answers `503 AUTH_UNAVAILABLE` on every authenticated route — auth
  fails closed by design, so a missing credential is a refusal, not an opening.
- A **gateway key**: `openssl rand -hex 32`. One value, shared by the gateway and
  the four services behind it.
- DNS access for `cocarr.com`.

```bash
npm i -g @railway/cli && railway login
```

---

## 1. Project and environment

```bash
railway init --name cocarr-dev
```

Use ONE Railway project with a `dev` environment. Separate projects per service
lose private networking between them, which is the whole transport for
service-to-service calls here.

---

## 2. Databases

Three logical databases: **IAM** (identity + authorization share it), **Workspace**,
**Core** (core-api + notification share it).

Add one MySQL service (`+ New` → `Database` → `MySQL`), then create the three
databases inside it:

```bash
railway connect MySQL
```
```sql
CREATE DATABASE cocarr_iam;
CREATE DATABASE cocarr_workspace;
CREATE DATABASE cocarr_core;
```

> One MySQL instance with three databases is the cheap dev shape. It is **not**
> the charter's "independent databases" — a runaway query in Core can starve
> IAM. For staging/production use three MySQL services. Nothing in the code
> changes; only the four `DB_*` variables differ per service.

**No migration step.** Every service runs `db.sync({ alter: true })` at boot and
creates its own tables. Watch the first deploy's logs for `schema synced` — a
failed sync aborts the whole pass and silently leaves every model after the
failure point without a table.

---

## 3. The five private services

For each of `cocarr-identity-service`, `cocarr-authorization-service`,
`cocarr-workspace-api`, `cocarr-core-api`, `cocarr-notification-service`:

1. `+ New` → `GitHub Repo` → pick the repo → branch `develop`.
2. Builder is already set by the repo's `railway.json` (Dockerfile).
3. **Do NOT click "Generate Domain".**
4. Set the variables below.

Shared by all five:

| Variable | Value |
|---|---|
| `NODE_ENV` | `production` |
| `PORT` | `3050` / `3060` / `3040` / `3030` / `3070` respectively |
| `ADMIN_SERVICE_ACCOUNT` | the Firebase JSON, one line |
| `GATEWAY_KEY` | the shared secret from step 0 |
| `AUTH_DISABLED` | `false` (it is ignored in production anyway) |
| `CORS_ORIGINS` | `https://workspace-dev.cocarr.com,https://admins-dev.cocarr.com` |

Per service:

| Service | `DB_NAME` | Extra |
|---|---|---|
| identity | `cocarr_iam` | `SESSION_TTL_DAYS=30` |
| authorization | `cocarr_iam` | — |
| workspace | `cocarr_workspace` | `AUTHORIZATION_SERVICE_URL=http://authorization.railway.internal:3060`, `RBAC_ENFORCE=true` |
| core | `cocarr_core` | `PUBLIC_API_URL=https://apis-dev.cocarr.com/v1/core`, `USER_SERVICE_ACCOUNT`, payment/storage keys |
| notification | `cocarr_core` | `SENDGRID_API_KEY`, `EMAIL_FROM`, `MSG_KEY` (they simulate if unset) |

Database variables use Railway references so a rotated password propagates:

```
DB_HOST=${{MySQL.MYSQLHOST}}
DB_PORT=${{MySQL.MYSQLPORT}}
DB_USER=${{MySQL.MYSQLUSER}}
DB_PASS=${{MySQL.MYSQLPASSWORD}}
DB_NAME=cocarr_iam
```

> `PUBLIC_API_URL` on core-api must point at the **gateway**, not at core-api.
> It is what the image proxy builds URLs against, and every client re-proxies
> against its own base — a mismatch shows up as broken images, not as an error.

---

## 4. The gateway — `apis-dev.cocarr.com`

New service from `cocarr-api-gateway`, branch `develop`. Then:

| Variable | Value |
|---|---|
| `NODE_ENV` | `production` |
| `PORT` | `8080` |
| `ADMIN_SERVICE_ACCOUNT` | the Firebase JSON |
| `GATEWAY_KEY` | **the same value** as the five services |
| `CORS_ORIGINS` | `https://workspace-dev.cocarr.com,https://admins-dev.cocarr.com` |
| `IDENTITY_SERVICE_URL` | `http://identity.railway.internal:3050` |
| `AUTHORIZATION_SERVICE_URL` | `http://authorization.railway.internal:3060` |
| `WORKSPACE_SERVICE_URL` | `http://workspace.railway.internal:3040` |
| `CORE_SERVICE_URL` | `http://core.railway.internal:3030` |
| `NOTIFICATION_SERVICE_URL` | `http://notification.railway.internal:3070` |

`<name>.railway.internal` is the Railway **service name**, so name the services
exactly as above or adjust the URLs to match.

Settings → Networking → Custom Domain → `apis-dev.cocarr.com`. Railway gives you
a CNAME target; add it at your DNS provider.

---

## 5. The two web apps

Both come from `cocarr-platform-web`. Because it is a monorepo, each Railway
service points at that app's own config file:

| Setting | `workspace-web` | `admin-web` |
|---|---|---|
| Repo / branch | `cocarr-platform-web` / `develop` | same |
| Root Directory | **`/`** (leave at repo root) | **`/`** |
| Config-as-code path | `apps/workspace-web/railway.json` | `apps/admin-web/railway.json` |
| Custom domain | `workspace-dev.cocarr.com` | `admins-dev.cocarr.com` |

> Root Directory stays at the repo root. Pointing it at `apps/workspace-web`
> puts the shared `packages/*` outside the build context and the build fails on
> the first `@cocarr/*` import.

Variables for **both**:

```
NEXT_PUBLIC_GATEWAY_URL=https://apis-dev.cocarr.com
NEXT_PUBLIC_FIREBASE_API_KEY=…
NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN=…
NEXT_PUBLIC_FIREBASE_PROJECT_ID=…
NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET=…
NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID=…
NEXT_PUBLIC_FIREBASE_APP_ID=…
```

> **`NEXT_PUBLIC_*` is inlined at BUILD time.** Changing one requires a redeploy,
> not a restart — a restarted app keeps the old value and the change looks like
> it did nothing. Set them before the first build.

Do **not** set `PORT` on the web apps. Railway injects it and `next start` reads
it; pinning it makes the container listen where Railway is not looking, and the
healthcheck fails while the app runs perfectly.

---

## 6. Seed IAM — once

Nothing appears in any sidebar until the taxonomy exists, because the nav IS the
IAM data.

```bash
railway run --service authorization node scripts/seedTaxonomy.js --dry-run
railway run --service authorization node scripts/seedTaxonomy.js --confirm
```

Expect: 3 products, 27 modules, 63 sub-modules, 171 permissions, 4 permission
sets, 8 roles, 2 approval chains. Idempotent — re-running creates nothing.

Then give yourself access. Sign in once at `admins-dev.cocarr.com` so your
identity row is created, then:

```bash
# find your platform identity id
railway run --service identity node -e "require('./src/models').Identity.findAll().then(r=>console.log(r.map(i=>({id:i.id,email:i.email}))))"

# assign super-admin
curl -X POST https://apis-dev.cocarr.com/v1/platform/assignments \
  -H "Authorization: Bearer <your firebase id token>" \
  -H 'content-type: application/json' \
  -d '{"principalId":"<identity id>","roleId":"<super-admin role id>"}'
```

Chicken-and-egg: the assignments endpoint requires authentication, and a fresh
platform has nobody. Either make the first assignment directly against the
database, or run the call once with `RBAC_ENFORCE=false` on authorization and
turn it back on immediately.

---

## 7. Verify, in this order

```bash
curl https://apis-dev.cocarr.com/health          # gateway alive
curl https://apis-dev.cocarr.com/health/services # every upstream reachable
```

`/health/services` is the one that proves private networking. If the gateway is
healthy and upstreams show `ok: false`, that is the IPv6 issue below.

Then in a browser at `workspace-dev.cocarr.com`: sign in, and the sidebar should
render the four Workspace modules. An empty sidebar with no error means the
navigation payload came back with nothing — you are authenticated but hold no
role (step 6).

---

## The five things that actually go wrong

1. **Everything answers 503 `AUTH_UNAVAILABLE`.** `ADMIN_SERVICE_ACCOUNT` is
   missing or malformed on that service. Auth fails closed; the boot log carries
   a FATAL line naming it.
2. **Gateway 502s every upstream, upstreams look healthy.** A service bound to
   IPv4 only. Railway's private network is IPv6-only. Fixed in the code (no host
   argument to `listen`), so this only bites a service pinned to an older commit.
3. **`403` on every call with a valid token.** `GATEWAY_KEY` differs between the
   gateway and that service. A mismatched key is a hard deny, never a
   fall-through — deliberately.
4. **Web app builds, then 404s on every screen.** Its `NEXT_PUBLIC_GATEWAY_URL`
   was set after the build. Redeploy, do not restart.
5. **Sidebar is empty for everyone.** The seed has not run, or the signed-in
   identity holds no role assignment.

---

## What is NOT ready to deploy

- **`operations-web`** — its 41 routes are not migrated yet. Do not create the
  service; it would build and serve an empty app.
- **`/dashboard/teams-access`** on admin-web — deliberately not migrated, because
  it edits COCARR-BACKEND's team/level grid, which the authorization service
  replaces. The route 404s by design until a new IAM editor exists.
- **core-api's own admin RBAC** still governs `/v1/core`. It has not been moved
  onto the authorization service; both systems are live at once, on purpose.
