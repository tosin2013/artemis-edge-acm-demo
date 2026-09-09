#!/usr/bin/env bash
set -euo pipefail
#
# Destroy SNO spoke clusters provisioned by deploy-spokes.sh.
#
# This is a convenience wrapper around deploy-spokes.sh --destroy.
# It accepts the same --clusters and --timeout options.
#
# Usage:
#   ./scripts/destroy-spokes.sh                 # Destroy 2 spokes (default)
#   ./scripts/destroy-spokes.sh --clusters 3    # Destroy 3 spokes
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/deploy-spokes.sh" --destroy "$@"
