#!/bin/bash
set -Eeuo pipefail
exec bash "$(dirname "${BASH_SOURCE[0]}")/deploy/install.sh" "$@"
