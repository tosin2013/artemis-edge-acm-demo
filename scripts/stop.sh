#!/usr/bin/env bash
set -euo pipefail
#
# Stop (hibernate) the GCP cluster to save costs
# Delegates to deploy.sh --action stop
#
# Usage:
#   ./scripts/stop.sh --guid 725j2 --account openenv-gcp
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/deploy.sh" --action stop "$@"
