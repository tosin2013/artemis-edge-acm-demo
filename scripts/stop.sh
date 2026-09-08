#!/usr/bin/env bash
# stop.sh — Stop the Artemis Edge ACM Demo cluster
# Delegates to deploy.sh --stop
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/deploy.sh" --stop "$@"
