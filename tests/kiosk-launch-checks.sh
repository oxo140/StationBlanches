#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
temp_dir=$(mktemp -d)
cleanup() { rm -rf -- "$temp_dir"; }
trap cleanup EXIT
mkdir "$temp_dir/bin"
printf '#!/bin/bash\nexit 0\n' > "$temp_dir/bin/curl"
cat > "$temp_dir/bin/chromium" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$SB_TEST_LAUNCHES"
exit 0
EOF
chmod +x "$temp_dir/bin/"*
export SB_TEST_LAUNCHES="$temp_dir/launches"
export XDG_CONFIG_HOME="$temp_dir/config"
export PATH="$temp_dir/bin:$PATH"
status=0
timeout --signal=TERM 7 bash deploy/host/kiosk-launch.sh || status=$?
[[ "$status" == 124 ]]
[[ $(wc -l < "$SB_TEST_LAUNCHES") -ge 2 ]]
grep -q -- '--kiosk' "$SB_TEST_LAUNCHES"
grep -q -- '--user-data-dir=' "$SB_TEST_LAUNCHES"
# Un second lanceur ne doit pas ouvrir une autre fenêtre.
count=$(wc -l < "$SB_TEST_LAUNCHES")
flock "$XDG_CONFIG_HOME/station-blanche/kiosk.lock" bash deploy/host/kiosk-launch.sh
[[ $(wc -l < "$SB_TEST_LAUNCHES") == "$count" ]]
echo 'Kiosk relaunch and single-instance checks passed'
