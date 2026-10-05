# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Chart version follows SemVer: MAJOR (breaking topology changes) . MINOR
(new features/modes) . PATCH (bug fixes, docs, chores).

## [0.3.0] — 2026-10-05

### Added
- `values.schema.json` — JSON Schema validation for chart values (#129)
- `templates/NOTES.txt` — post-install instructions (#129)
- `templates/tests/test-connection.yaml` — `helm test` hook for hub broker smoke test (#129)
- CI matrix for Mode 2 — `helm-validate.yaml` now lints and templates Mode 1, Mode 2 regional, and Mode 2 Global Hub (#129)
- Unit tests for all four Java modules — 18 tests total (#130)
- `.github/CODEOWNERS`, issue/PR templates, `dependabot.yml` (#131)
- `CHANGELOG.md` and release/tag convention (#133)
- `docs/delivery-mechanisms.md` — comparison of the four AMQ delivery mechanisms (#132)
- `deploy.sh --tier all` — sequential 4-tier Mode 2 provisioning (global → east → central → west) (#155)
- `scripts/patch-agnosticd-pre-infra.sh` — idempotent AgnosticD pre_infra.yml auto-patch (#157)
- `docs/mode2-quickstart.md` — dedicated Mode 2 deployment guide with one-command deploy, recovery, and validation (#156)
- `onboard.yml` setup step for AgnosticD patching, `post_validation_command_multihub` updated to use `--tier all` (#155, #157)

### Fixed
- Removed phantom `hub-02` references from `values.yaml` and `generate-tls.sh` (#128)
- `validate-deployment.sh` now detects deployment mode and skips spoke broker checks in Mode 2 (#127)
- `deploy.sh` reads `agnosticd_root` from `config.yml` as fallback (#126)
- `bootstrap.sh` now evaluates `condition` field in quota checks and dispatches `post_validation_command_multihub` (#125)
- `.helmignore` missing exclusions — `gcp-key.json` and 12 other non-chart files (#124)
- AMQ version drift — upgraded `ztp/`, `acm/`, `fleet-gitops/` from `amq-broker-rhel8` 7.12.x to `amq-broker-rhel9` 7.14.x (#123)
- `helm lint` failure on `workshop-user-rbac.yaml` YAML document separator (#122)
- `spoke-rhacm-policies.yaml` YAML separator lint error (same pattern as #122)
- `fleet-gitops-app.yaml` nil pointer when `.Values.gitops` unset in Mode 2 Global Hub

### Changed
- `mqtt-client` groupId corrected from `org.redhat.examples` to `com.redhat.examples` (#130)
- `artemis-extensions` POM: added JUnit 5, Mockito, Surefire, and compiler plugin
- Chart `appVersion` updated to `7.14.1` (AMQ Broker version)
- Chart `version` bumped to `0.3.0`
- Added `gitops` section to `values.yaml` and `values-mode2-global.yaml`
- Azure deployment gap documented in `values-azure.yaml` and `docs/azure-status.md` (#134)

### Removed
- Pruned 11 stale branches (local and remote); only `main` and `release/mode-1` remain (#135)

## [0.2.0] — 2026-09-16 — Mode 2 (Hub-of-Hubs)

Tag: `mode-1` marks the end of Mode 1 development at commit `6c3d720`.
Mode 2 work begins after this tag.

### Added
- Mode 2 hub-of-hubs architecture: Global Hub (Tier 0), regional ACM hubs (Tier 1), student SNOs (Tier 2) (#72)
- `fleet-gitops/` — App-of-Apps with push (Global → regional) and pull (regional → SNO) ApplicationSets
- `values-mode2.yaml` and `values-mode2-global.yaml` overlay files
- Mode 2 lab modules (5603/5604 messaging paths, Global Hub verify) (#74)
- GCP cluster quota checks in `onboard.yml` (#80, #81)
- `import-managed-hubs.sh` post-provision script for Mode 2 (#89)
- RHACM-ArgoCD bridge and fleet-gitops Application (#82)
- Showroom GitHub Pages deployment (`showroom-gh-pages.yaml` workflow)
- `deploy-spokes.sh` for Mode 2 SNO provisioning (#102)
- `save-deployment-info.sh` for multi-hub environments (#99)
- Blog posts (`blogs/` directory) (#101)
- Documentation: architecture, platform guide, developer guide, GCP deployment, Mermaid diagrams

### Fixed
- cert-manager DNS zone mismatch in Mode 2 (#87)
- ArgoCD app-controller memory increased to 4Gi for multi-hub (#90)
- Operator subscriptions updated for OCP 4.22 (#91)
- Showroom image fixed to `quay.io/rhpds/showroom-content:v1.4.2`
- Mode 2 multi-hub onboarding pipeline gaps (#102) — 10+ commits
- Bridge configurations and federation policies for edge brokers (#119, #120)
- AMQ Broker upgraded to 7.14.1 (`amq-broker-rhel9`) (#120)

### Changed
- Workshop modules rewritten for AMQ Broker 7.14.1 (#121)
- `CONTRIBUTING.md` added with PR workflow and code standards

## [0.1.0] — 2026-09-04 — Mode 1 (Single Hub)

### Added
- Initial Helm chart: AMQ Broker operator, hub broker, edge brokers with AMQP federation
- Keycloak SSO integration
- ACM Observability (MCO) dashboards and alerts
- TLS toggle (`tls.enabled`) for broker acceptors
- Workshop modules 1–8 (Showroom/Antora-based)
- Java Quarkus clients: `amqp-client`, `mqtt-client`, `amqp-bridge`
- `artemis-extensions` Artemis plugin (StaticHeaderPlugin)
- ACM policies for edge broker deployment
- ZTP PolicyGenerator for SNO edge brokers
- `bootstrap.sh` manifest-driven onboarding with `onboard.yml`
- `scripts/deploy.sh` → AgnosticD v2 deployment
- `scripts/validate-deployment.sh` post-deploy health checks

---

## Release Convention

| Tag pattern | Meaning |
|---|---|
| `v0.X.Y` | Chart SemVer release (matches `Chart.yaml` `version`) |
| `mode-1` | Freeze tag — Mode 1 stable at `6c3d720` |
| `fleet-{region}` | Mode 2 promotion boundary per region |

To create a release:

```bash
# Bump version in Chart.yaml, update this CHANGELOG, then:
git tag -a v0.3.0 -m "v0.3.0: Helm tests, Java tests, community files"
git push origin v0.3.0
# Create GitHub Release from the tag
gh release create v0.3.0 --title "v0.3.0" --notes-file CHANGELOG_EXCERPT.md
```
