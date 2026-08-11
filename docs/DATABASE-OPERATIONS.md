# Database operations

The MySQL instance, its schemas and what to do when something is wrong.

Topology and rationale: `cocarr-docs/DATABASE.md`.
Migrations and releases: `cocarr-docs/RELEASES.md`.

**One instance. One schema per service. Each service owns its schema and can
reach no other** — enforced by grants, not convention.

| Service | Schema | User |
|---|---|---|
| cocarr-core-api | `cocarr_core` | `svc_core` |
| cocarr-authorization-service | `cocarr_iam` | `svc_iam` |
| cocarr-workspace-api | `cocarr_workspace` | `svc_workspace` |
| cocarr-identity-service | `cocarr_identity` | `svc_identity` |
| cocarr-notification-service | `cocarr_notification` | `svc_notification` |

---

## Provisioning a new environment

`docker/mysql/init/01-schemas-and-users.sql` is the source of truth for schemas,
users and grants. Locally it runs automatically on the first start of an empty
volume. For a managed instance, run the same file once by hand.

Then, per service, from the service's own repo:

```bash
npm run migrate:up
```

**Nothing else creates schema.** Services no longer sync on boot.

### Why the grants matter

Verified against a real instance:

```
svc_core sees:  cocarr_core          # and nothing else
svc_core -> cocarr_iam:  ERROR 1044 Access denied
svc_core -> cocarr_core: DDL allowed
```

Without per-service users, "each service owns its schema" is a naming habit and
nothing stops a mistyped `DB_NAME` letting one service's migration run against
another's tables. With them, that mistake fails at startup as
`ER_ACCESS_DENIED_ERROR`, which every service's preflight reports by name.

---

## Diagnosing a broken service

Every service classifies its own database failure at boot. Read the log first —
it names the cause and the fix:

```
!!! DATABASE UNREACHABLE — EVERY QUERY WILL FAIL !!!
  The schema 'cocarr_core' does not exist on db.internal.
  fix: node scripts/ensureDatabase.js --confirm
  DB_NAME=cocarr_core DB_HOST=db.internal DB_USER=svc_core
```

| Symptom | Cause | Fix |
|---|---|---|
| `Unknown database 'x'` | `DB_NAME` names a schema that does not exist | `npm run db:ensure` — **read the warning about data under another name first** |
| `Access denied for user` | wrong credentials, **or the service is pointed at another service's schema** | check `DB_NAME` before changing the password |
| `Table 'x.y' doesn't exist` | migrations not applied, or a pre-migration aborted `alter` | `npm run migrate:status`, then `migrate:up` |
| `PENDING MIGRATIONS` at boot | the revision shipped without its release step | run `migrate:up`; the deploy order is wrong |
| lists empty, no errors, reference data present | **empty or wrong schema** — boot seeders refill cities/brands | compare `DB_NAME` against the table above |

That last row cost a day once. Forty cities and zero vehicles with no errors is
the signature of a *fresh* database, not a broken query.

### Before creating a schema, look for the data

`ensureDatabase.js --dry-run` lists every schema on the instance first, on
purpose. If the data is sitting under a different name, the fix is `DB_NAME` —
**not** a new empty schema beside it.

---

## Backups

**A migration is the one deploy step that redeploying the previous image cannot
undo.** Snapshot before every production migration.

```bash
# One schema, structure + data, safe for a live instance
mysqldump --single-transaction --routines --triggers \
  -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" \
  "$DB_NAME" > "$DB_NAME-$(date +%Y%m%d-%H%M).sql"
```

`--single-transaction` takes a consistent snapshot of InnoDB tables without
locking writers. Without it, a dump of a live database can contain a mix of
before- and after-states of the same transaction.

Restore into a **scratch** schema, never over a live one:

```bash
mysql -e "CREATE DATABASE cocarr_core_restore"
mysql cocarr_core_restore < cocarr_core-20260812-1400.sql
```

### Rehearse production migrations on a restored copy

Not on staging. Staging's data volume and history are not production's, and the
failures that matter only appear at real size: MySQL's 64-key-per-table limit,
foreign-key type mismatches, and `ALTER TABLE` holding a lock long enough to
matter on a large table.

```bash
DB_NAME=cocarr_core_restore npm run migrate:status   # read the plan
DB_NAME=cocarr_core_restore npm run migrate:up       # time it
```

---

## Checking a database against the code

`cocarr-core-api` ships `npm run db:diff`, which compares a live schema against
what the models describe and reports missing tables, extra tables, missing
columns and changed types.

**Run it against a restored copy of production before trusting the baseline on
that environment.** The baseline creates each table only if absent, so it never
inspects a table that already exists — any drift it does not see becomes
permanent and invisible once the baseline is recorded.

---

## Local development

```bash
docker compose -f docker/docker-compose.dev.yml up -d
```

Provisions all five schemas and their users. Then per service: set `DB_NAME` /
`DB_USER` / `DB_PASS` from the table above, `npm run migrate:up`, `npm run dev`.

The init scripts run **once**, on the first start of an empty volume. After
editing them:

```bash
docker compose -f docker/docker-compose.dev.yml down -v   # the -v drops the volume
docker compose -f docker/docker-compose.dev.yml up -d
```

`DB_SYNC=true` restores the old `sync({alter:true})` behaviour for local
iteration. It is refused in production, and it will happily drop columns — do
not reach for it to "fix" a schema you can migrate instead.
