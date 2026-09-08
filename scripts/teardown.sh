#!/usr/bin/env bash
set -euo pipefail
#
# Teardown Artemis Edge ACM Demo on GCP via AgnosticD v2
# Delegates to deploy.sh --action destroy
#
# Usage:
#   ./scripts/teardown.sh --guid 725j2 --account openenv-gcp
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/deploy.sh" --action destroy "$@"
