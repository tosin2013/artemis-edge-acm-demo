# Contributing to Artemis Edge ACM Demo

Thank you for your interest in contributing! This guide covers the development
setup, code standards, and pull request workflow.

## Getting Started

### 1. Fork and Clone

```bash
# Fork on GitHub, then:
git clone https://github.com/<your-user>/artemis-edge-acm-demo.git
cd artemis-edge-acm-demo
```

### 2. Dev Mode Setup

```bash
./bootstrap.sh --mode dev
```

This installs all prerequisites plus development tools (ShellCheck, yamllint)
and skips deployment. The bootstrap script reads
[`onboard.yml`](onboard.yml) — one source of truth for both contributors
and end users.

### 3. Create a Branch

```bash
git checkout -b feat/my-feature
```

Use conventional prefixes: `feat/`, `fix/`, `docs/`, `refactor/`, `chore/`.

## Code Standards

### Shell Scripts

- All scripts pass [ShellCheck](https://www.shellcheck.net/)
- Use `set -euo pipefail` at the top of every script
- Quote all variables: `"${MY_VAR}"`, not `$MY_VAR`
- Use `[[ ]]` instead of `[ ]` for conditionals

```bash
shellcheck scripts/*.sh bootstrap.sh
```

### YAML / Ansible

- All YAML passes `yamllint`
- Use FQCN for all Ansible modules and roles (e.g.,
  `ansible.builtin.debug`, not `debug`)
- Every task must have a `name:` field
- Use YAML block notation, not inline `key=value`

```bash
yamllint -d relaxed agnosticd/ onboard.yml
```

### Helm Charts

- Templates must render cleanly: `helm template . --values values.yaml`
- Use `.Values` references consistently
- Add comments for non-obvious template logic

## Project Architecture

The project follows a manifest-driven onboarding model:

- **[`onboard.yml`](onboard.yml)** — Declarative manifest (prerequisites,
  setup steps, config prompts, validation checks). This is the single source
  of truth.
- **[`bootstrap.sh`](bootstrap.sh)** — Runtime script that reads `onboard.yml`
  via python3 + PyYAML. No values are baked in.
- **[`scripts/deploy.sh`](scripts/deploy.sh)** — Project entry point that
  delegates to the `agd` CLI from
  [tosin2013/agnosticd-v2](https://github.com/tosin2013/agnosticd-v2).
- **[`agnosticd/gcp/vars.yml`](agnosticd/gcp/vars.yml)** — AgnosticD
  deployment variables (copied to `agnosticd-v2-vars/` during setup).

## Governance

This repository uses [Repo Governor](https://github.com/rhpds/repo-governor)
to manage work authorization. Key rules:

- All work must be tracked by a GitHub issue with the `authorized` label
- Discoveries (bugs, refactors, improvements found during work) are recorded
  but not acted on without separate authorization
- When acceptance criteria are met, stop — do not continue with additional
  changes

Before starting work on an issue:

```bash
RG=".cursor/skills/repo-governor"
python3 "$RG/engine/completion.py" <issue-number>
```

## Pull Request Process

1. **One issue, one PR** — Keep PRs focused on a single issue
2. **Run checks locally** before pushing:
   ```bash
   shellcheck scripts/*.sh bootstrap.sh
   yamllint -d relaxed agnosticd/ onboard.yml
   helm template . --values values.yaml > /dev/null
   ./bootstrap.sh --check-only
   ```
3. **Write a clear PR description** with the issue number
4. **Request review** from maintainers
5. **Address feedback** promptly

## Reporting Issues

Use [GitHub Issues](https://github.com/tosin2013/artemis-edge-acm-demo/issues)
to report bugs or request features. Include:

- Steps to reproduce (for bugs)
- Expected vs actual behavior
- Environment details (OS, OCP version, cloud provider)
- Relevant logs or error messages

## License

By contributing, you agree that your contributions will be licensed under the
[Apache-2.0 License](LICENSE).
