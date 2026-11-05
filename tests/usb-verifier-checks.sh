#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
temp_dir=$(mktemp -d)
# shellcheck disable=SC2329
cleanup() { rm -f "$temp_dir/curl" "$temp_dir/count"; rmdir "$temp_dir"; }
trap cleanup EXIT
cat > "$temp_dir/curl" <<'EOF'
#!/bin/bash
set -Eeuo pipefail
case "$*" in
    *'/health/ready') exit 0 ;;
    *'/findings')
        copy='"private-copy-id"'
        if [[ "$SB_USB_CASE" == missing-copy ]]; then copy=null; fi
        printf '[{"kind":"threat","quarantine_id":%s,"sha256":"275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f","detail":"Eicar-Test-Signature"}]\n' "$copy"
        ;;
    *'/api/status')
        count=0
        if [[ -f "$SB_USB_STATE/count" ]]; then count=$(cat "$SB_USB_STATE/count"); fi
        printf '%s\n' "$((count+1))" > "$SB_USB_STATE/count"
        if (( count == 0 )); then
            echo '{"scans":[],"progress":{"scan_id":null},"present_results":[],"kpis":{"analyses":0,"threats":0,"quarantined":0}}'
        else
            verdict=infected; threats=1; errors=0; copies=1
            case "$SB_USB_CASE" in
                clean) verdict=no_threat_detected; threats=0; copies=0 ;;
                incomplete) verdict=incomplete; errors=1 ;;
                missing-copy) copies=0 ;;
            esac
            printf '{"scans":[{"id":"11111111-1111-4111-8111-111111111111","device":"sdb1","finished_at":1000,"verdict":"%s","files":1,"threats":%s,"errors":%s}],"kpis":{"analyses":1,"threats":%s,"quarantined":%s}}\n' "$verdict" "$threats" "$errors" "$threats" "$copies"
        fi
        ;;
    *) echo "Requête inattendue : $*" >&2; exit 1 ;;
esac
EOF
chmod 0755 "$temp_dir/curl"
for scenario in clean infected incomplete missing-copy; do
    rm -f "$temp_dir/count"
    expected=infected
    if [[ "$scenario" == clean ]]; then expected=clean; fi
    if PATH="$temp_dir:$PATH" SB_USB_STATE="$temp_dir" SB_USB_CASE="$scenario" bash deploy/test-antivirus.sh --verify-usb "$expected" sdb1 1; then
        [[ "$scenario" == clean || "$scenario" == infected ]] || { echo "Mauvais résultat accepté : $scenario" >&2; exit 1; }
    else
        [[ "$scenario" == incomplete || "$scenario" == missing-copy ]] || { echo "Bon résultat refusé : $scenario" >&2; exit 1; }
    fi
done
echo 'USB acceptance verifier checks passed'
