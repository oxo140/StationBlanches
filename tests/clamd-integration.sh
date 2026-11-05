#!/bin/bash
set -Eeuo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
temp_dir=$(mktemp -d)
daemon_pid=""
# Appelée par trap.
# shellcheck disable=SC2329
cleanup() {
    [[ -z "$daemon_pid" ]] || kill "$daemon_pid" 2>/dev/null || true
    [[ -z "$daemon_pid" ]] || wait "$daemon_pid" 2>/dev/null || true
    rm -f "$temp_dir/clamd.conf" "$temp_dir/clamd.log"
    rmdir "$temp_dir"
}
trap cleanup EXIT
cat > "$temp_dir/clamd.conf" <<EOF
Foreground yes
DatabaseDirectory $root/tests/fixtures
TCPSocket 13310
TCPAddr 127.0.0.1
StreamMaxLength 110M
MaxFileSize 100M
MaxScanSize 256M
AlertExceedsMax yes
AlertEncrypted yes
ScanArchive yes
EOF
clamd --config-file="$temp_dir/clamd.conf" > "$temp_dir/clamd.log" 2>&1 &
daemon_pid=$!
for _ in {1..30}; do
    if printf 'zPING\0' | nc -w 1 127.0.0.1 13310 | grep -q PONG; then
        SB_TEST_CLAMD=127.0.0.1:13310 cargo test --locked real_clamav -- --ignored
        exit 0
    fi
    if ! kill -0 "$daemon_pid" 2>/dev/null; then cat "$temp_dir/clamd.log"; exit 1; fi
    sleep 1
done
cat "$temp_dir/clamd.log"
exit 1
