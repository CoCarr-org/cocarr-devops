# cocarr-devops

> Infrastructure, Railway, Docker and CI/CD.

Part of the **Cocarr Enterprise Platform** ([CoCarr-org](https://github.com/CoCarr-org)).

Topics: `docker`, `railway`, `github-actions`, `devops`

## Purpose
Central home for infrastructure: Docker images, Railway configuration, reusable GitHub Actions workflows and operational scripts.

## Architecture
This repository is one component of the Cocarr platform, a service-oriented
system fronted by the API gateway. Requests flow through the gateway to the
identity, authorization, workspace, core and notification services, each backed
by its own database. See [`cocarr-docs`](https://github.com/CoCarr-org/cocarr-docs)
for the full platform architecture and Architecture Decision Records.

## Technology Stack
- Docker
- Railway
- GitHub Actions
- Shell

## Folder Structure
```
docker/   # Base images and compose files
railway/  # Railway service configuration
scripts/  # Operational and CI helper scripts
docs/     # Runbooks and infrastructure docs
.github/  # Reusable workflows, templates, CODEOWNERS
```

## Getting Started
```bash
# Clone
git clone https://github.com/CoCarr-org/cocarr-devops.git
cd cocarr-devops

# Work from the develop branch
git checkout develop
```
Copy `.env.example` to `.env` where applicable and install dependencies with
your package manager (`pnpm install`).

## Development
- Format: `pnpm prettier --write .`
- Lint: `pnpm lint`
- Test: `pnpm test`

Editor settings, Prettier, ESLint, EditorConfig and VS Code configuration ship
with the repository for a consistent developer experience.

## Contributing
Please read [CONTRIBUTING.md](CONTRIBUTING.md) and use the issue and pull
request templates. All changes require CODEOWNER review.

## Branch Strategy
| Branch    | Purpose                                   | Protected |
|-----------|-------------------------------------------|-----------|
| `main`    | Always-deployable production baseline     | Yes       |
| `develop` | Integration branch for feature work       | No        |
| `release` | Release-candidate stabilisation branch    | Yes       |

Feature branches: `feature/<description>` from `develop`.

## Deployment
This repo *is* the deployment tooling. Reusable workflows are consumed by the service repositories.

## Security
See [SECURITY.md](SECURITY.md) for vulnerability reporting. Dependabot alerts
and secret scanning are enabled where supported.

## License
Licensed under the [MIT License](LICENSE).
