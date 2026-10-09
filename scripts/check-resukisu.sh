#!/bin/bash
# ==============================================================================
# check-resukisu.sh — Compatibility wrapper forwarding to check-folksu.sh
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/check-folksu.sh" "$@"
