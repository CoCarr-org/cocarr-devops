-- ONE INSTANCE, ONE SCHEMA PER SERVICE — provisioned for local development so
-- that a laptop matches production in the way that matters.
--
-- This runs ONCE, on the FIRST start of an empty data directory. MySQL's
-- docker-entrypoint ignores /docker-entrypoint-initdb.d entirely if the volume
-- already has data, so editing this file does nothing to a stack that is
-- already up. To re-provision:
--
--     docker compose -f docker/docker-compose.dev.yml down -v   # -v drops the volume
--     docker compose -f docker/docker-compose.dev.yml up -d
--
-- WHY PER-SERVICE USERS AND NOT ONE SHARED ACCOUNT.
--
-- Separate schemas are only a naming convention until the grants make them
-- real. With one shared account, a service pointed at the wrong DB_NAME can run
-- its `alter` against another service's tables and nothing stops it — and a
-- wrong DB_NAME has already caused an outage on this platform. With the grants
-- below, that same mistake fails at startup with ACCESS DENIED, which the
-- preflight reports by name.
--
-- Passwords here are development-only and deliberately obvious. Production
-- credentials live in the platform's secret store, never in a repo.

CREATE DATABASE IF NOT EXISTS `cocarr_core`         CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS `cocarr_iam`          CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS `cocarr_workspace`    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS `cocarr_identity`     CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS `cocarr_notification` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'svc_core'@'%'         IDENTIFIED BY 'dev_core';
CREATE USER IF NOT EXISTS 'svc_iam'@'%'          IDENTIFIED BY 'dev_iam';
CREATE USER IF NOT EXISTS 'svc_workspace'@'%'    IDENTIFIED BY 'dev_workspace';
CREATE USER IF NOT EXISTS 'svc_identity'@'%'     IDENTIFIED BY 'dev_identity';
CREATE USER IF NOT EXISTS 'svc_notification'@'%' IDENTIFIED BY 'dev_notification';

-- ALL PRIVILEGES on its OWN schema only.
--
-- The breadth is required while services still create their schema through
-- migrations: `CREATE TABLE`, `ALTER`, `INDEX` are all DDL. What matters is the
-- narrowness — each user can see exactly one schema, so the isolation is
-- enforced by the server rather than by everyone remembering the convention.
GRANT ALL PRIVILEGES ON `cocarr_core`.*         TO 'svc_core'@'%';
GRANT ALL PRIVILEGES ON `cocarr_iam`.*          TO 'svc_iam'@'%';
GRANT ALL PRIVILEGES ON `cocarr_workspace`.*    TO 'svc_workspace'@'%';
GRANT ALL PRIVILEGES ON `cocarr_identity`.*     TO 'svc_identity'@'%';
GRANT ALL PRIVILEGES ON `cocarr_notification`.* TO 'svc_notification'@'%';

FLUSH PRIVILEGES;
