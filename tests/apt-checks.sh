#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=deploy/lib.sh
source deploy/lib.sh
# shellcheck source=deploy/apt-lib.sh
source deploy/apt-lib.sh
temp_dir=$(mktemp -d)
# shellcheck disable=SC2329
cleanup() {
    rm -f "$temp_dir/dpkg-query" "$temp_dir/apt-cache" "$temp_dir/apt-get" "$temp_dir/installed" "$temp_dir/log" "$temp_dir/docker.list" "$temp_dir/disabled.sources" "$temp_dir/active.sources"
    rmdir "$temp_dir"
}
trap cleanup EXIT
cat > "$temp_dir/dpkg-query" <<'EOF'
#!/bin/bash
if grep -Fxq "${!#}" "$SB_APT_TEST/installed"; then printf 'install ok installed'; else exit 1; fi
EOF
cat > "$temp_dir/apt-cache" <<'EOF'
#!/bin/bash
if [[ "${!#}" == "${SB_APT_NO_CANDIDATE:-}" ]]; then echo '  Candidate: (none)'; else echo '  Candidate: 1.0'; fi
EOF
cat > "$temp_dir/apt-get" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$SB_APT_TEST/log"
if [[ "$1" == install ]]; then
    shift
    for package in "$@"; do
        if [[ "$package" != -* ]]; then printf '%s\n' "$package" >> "$SB_APT_TEST/installed"; fi
    done
fi
EOF
chmod 0755 "$temp_dir/dpkg-query" "$temp_dir/apt-cache" "$temp_dir/apt-get"
printf 'chromium\n' > "$temp_dir/installed"
: > "$temp_dir/log"
export SB_APT_TEST="$temp_dir"
export PATH="$temp_dir:$PATH"
sb_apt_install_missing chromium
[[ ! -s "$temp_dir/log" ]] # Un Chromium déjà installé ne déclenche ni apt update ni réinstallation.
sb_apt_install_missing chromium jq
[[ $(grep -c 'update$' "$temp_dir/log") == 1 ]]
grep -qx 'install -y jq' "$temp_dir/log"
sb_apt_install_missing chromium jq
[[ $(grep -c '^install' "$temp_dir/log") == 1 ]]
if SB_APT_NO_CANDIDATE=missing-package sb_apt_install_missing missing-package; then
    echo 'Un paquet sans source disponible a été accepté.' >&2; exit 1
fi
[[ $(grep -c '^install' "$temp_dir/log") == 1 ]]
cat > "$temp_dir/docker.list" <<'EOF'
# deb https://download.docker.com/linux/debian trixie stable
deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian trixie stable
EOF
sb_apt_docker_file_enabled "$temp_dir/docker.list"
cat > "$temp_dir/disabled.sources" <<'EOF'
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: trixie
Components: stable
Enabled: no
EOF
if sb_apt_docker_file_enabled "$temp_dir/disabled.sources"; then echo 'Source désactivée considérée active.' >&2; exit 1; fi
cat > "$temp_dir/active.sources" <<'EOF'
Types: deb
URIs: https://deb.debian.org/debian
Suites: trixie
Components: main

Types: deb
URIs:
 https://download.docker.com/linux/debian
Suites: trixie
Components: stable
EOF
sb_apt_docker_file_enabled "$temp_dir/active.sources"
echo 'APT reuse, source detection and Chromium idempotence checks passed'
