#!/usr/bin/env bash
# teardown.sh — Destroy the Artemis Edge ACM Demo cluster
# Delegates to deploy.sh --destroy
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/deploy.sh" --destroy "$@"
