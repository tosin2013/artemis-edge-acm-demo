#!/usr/bin/env bash
set -euo pipefail
#
# Start (resume) a stopped GCP cluster
# Delegates to deploy.sh --action start
#
# Usage:
#   ./scripts/start.sh --guid 725j2 --account openenv-gcp
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/deploy.sh" --action start "$@"
