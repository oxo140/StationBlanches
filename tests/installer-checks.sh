#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=deploy/lib.sh
source deploy/lib.sh
for value in 192.168.1.50 10.0.0.1 172.16.0.254; do sb_ipv4 "$value"; done
for value in 0.0.0.0 127.0.0.1 192.168.1.256 192.168.01.1 '1.2.3.4.' '1.2.3.4;touch /tmp/not-created' ''; do
    if sb_ipv4 "$value"; then echo "IPv4 invalide acceptée : $value" >&2; exit 1; fi
done
temp_dir=$(mktemp -d)
# shellcheck disable=SC2329
cleanup() {
    if [[ -n "${fixture_dir:-}" ]]; then
        rm -f "$fixture_dir/clean/document-sain.txt" "$fixture_dir/infected/eicar.com.txt"
        rmdir "$fixture_dir/clean" "$fixture_dir/infected" "$fixture_dir"
    fi
    rm -f "$temp_dir/docker" "$temp_dir/one-line.sh"
    rmdir "$temp_dir"
}
trap cleanup EXIT
awk '/^\(set -e; sudo apt-get update;/ {print}' README.md > "$temp_dir/one-line.sh"
[[ -s "$temp_dir/one-line.sh" ]]
bash -n "$temp_dir/one-line.sh"
bash deploy/test-antivirus.sh --fixtures "$temp_dir"
fixture_dir=$(find "$temp_dir" -mindepth 1 -maxdepth 1 -type d -name 'station-blanche-test.*')
[[ $(sha256sum "$fixture_dir/infected/eicar.com.txt" | cut -d' ' -f1) == 275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f ]]
[[ $(stat -c '%a' "$fixture_dir/clean/document-sain.txt") == 644 ]]
cat > "$temp_dir/docker" <<'EOF'
#!/bin/bash
set -euo pipefail
case "$*" in
    'compose config --quiet'|info|*'/health/ready'*) exit 0 ;;
    *clamdscan*)
        content=$(cat)
        case "${SB_MOCK_RESULT:-normal}" in
            error) echo 'connection failed'; exit 2 ;;
            false-negative) echo 'stdin: OK'; exit 0 ;;
        esac
        if [[ "$content" == *EICAR* ]]; then echo 'stdin: Eicar-Test-Signature FOUND'; exit 1; fi
        echo 'stdin: OK'; exit 0
        ;;
    *) echo "Commande Docker inattendue : $*" >&2; exit 2 ;;
esac
EOF
chmod 0755 "$temp_dir/docker"
PATH="$temp_dir:$PATH" bash deploy/test-antivirus.sh --engine --wait 1
if PATH="$temp_dir:$PATH" SB_MOCK_RESULT=error bash deploy/test-antivirus.sh --engine --wait 1; then
    echo 'Une erreur moteur a été acceptée.' >&2; exit 1
fi
if PATH="$temp_dir:$PATH" SB_MOCK_RESULT=false-negative bash deploy/test-antivirus.sh --engine --wait 1; then
    echo 'Un EICAR non détecté a été accepté.' >&2; exit 1
fi
echo 'Installer and antivirus script checks passed'
