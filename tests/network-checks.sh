#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=deploy/lib.sh
source deploy/lib.sh
# shellcheck source=deploy/network-lib.sh
source deploy/network-lib.sh
for value in 192.168.1.50/24 10.0.0.2/8; do sb_cidr4 "$value"; done
for value in 192.168.1.2/0 192.168.1.2/33 192.168.1.2/024 999.1.1.1/24 '192.168.1.2/24;reboot'; do
    if sb_cidr4 "$value"; then echo "CIDR invalide accepté : $value" >&2; exit 1; fi
done
sb_dns4 '1.1.1.1 8.8.8.8'
for value in '' '1.1.1.1;reboot' '256.1.1.1' '1.1.1.1 2.2.2.2 3.3.3.3 4.4.4.4'; do
    if sb_dns4 "$value"; then echo 'Liste DNS invalide acceptée' >&2; exit 1; fi
done
temp_dir=$(mktemp -d)
# shellcheck disable=SC2329
cleanup() {
    rm -f "$temp_dir/profile" "$temp_dir/manual" "$temp_dir/auto" "$temp_dir/dns" "$temp_dir/ip" "$temp_dir/ping" "$temp_dir/getent" "$temp_dir/timeout" "$temp_dir/curl" "$temp_dir/confirmation"
    rmdir "$temp_dir"
}
trap cleanup EXIT
printf 'Yes\n' > "$temp_dir/confirmation"
[[ $(sb_nm_auto_confirm "$temp_dir/confirmation") == Yes ]]
printf 'No\n' > "$temp_dir/confirmation"
[[ $(sb_nm_auto_confirm "$temp_dir/confirmation") == No ]]
printf 'invalid\n' > "$temp_dir/confirmation"
[[ $(sb_nm_auto_confirm "$temp_dir/confirmation") == No ]]
cat > "$temp_dir/profile" <<'EOF'
auto lo
iface lo inet loopback
allow-hotplug enp0s3
iface enp0s3 inet dhcp
    dns-nameservers 192.168.1.1
    mtu 1500
iface enp0s3 inet6 auto
iface eth1 inet static
    address 10.0.0.2/24
    gateway 10.0.0.1
EOF
sb_render_interfaces "$temp_dir/profile" enp0s3 manual 192.168.1.50/24 192.168.1.1 '1.1.1.1 8.8.8.8' > "$temp_dir/manual"
grep -qx 'iface enp0s3 inet static' "$temp_dir/manual"
grep -qx '    address 192.168.1.50/24' "$temp_dir/manual"
grep -qx 'iface enp0s3 inet6 auto' "$temp_dir/manual"
grep -qx '    address 10.0.0.2/24' "$temp_dir/manual"
grep -qx '    mtu 1500' "$temp_dir/manual"
if grep -q 'dns-nameservers 192.168.1.1' "$temp_dir/manual"; then exit 1; fi
sb_render_interfaces "$temp_dir/manual" enp0s3 auto '' '' '' > "$temp_dir/auto"
grep -qx 'iface enp0s3 inet dhcp' "$temp_dir/auto"
if grep -q 'address 192.168.1.50' "$temp_dir/auto"; then exit 1; fi
grep -qx '    address 10.0.0.2/24' "$temp_dir/auto"
sb_render_interfaces "$temp_dir/profile" enp0s3 dns '' '' '1.1.1.1' > "$temp_dir/dns"
grep -qx 'iface enp0s3 inet dhcp' "$temp_dir/dns"
grep -qx '    dns-nameservers 1.1.1.1' "$temp_dir/dns"

cat > "$temp_dir/ip" <<'EOF'
#!/bin/bash
if [[ "$*" == '-4 route show default' ]]; then
    if [[ "$SB_NET_SCENARIO" != no-route ]]; then echo 'default via 192.168.1.1 dev enp0s3'; fi
else
    echo 'enp0s3 UP 192.168.1.50/24'
fi
EOF
cat > "$temp_dir/ping" <<'EOF'
#!/bin/bash
[[ "$SB_NET_SCENARIO" != icmp-filtered ]]
EOF
cat > "$temp_dir/getent" <<'EOF'
#!/bin/bash
if [[ "$SB_NET_SCENARIO" == dns-failure && "$*" == *download.docker.com* ]]; then exit 2; fi
echo '192.0.2.1 STREAM test'
EOF
cat > "$temp_dir/timeout" <<'EOF'
#!/bin/bash
shift
exec "$@"
EOF
cat > "$temp_dir/curl" <<'EOF'
#!/bin/bash
if [[ "$*" == *download.docker.com* ]]; then
    case "$SB_NET_SCENARIO" in dns-failure) exit 6 ;; tls-failure) exit 60 ;; esac
fi
exit 0
EOF
chmod 0755 "$temp_dir/ip" "$temp_dir/ping" "$temp_dir/getent" "$temp_dir/timeout" "$temp_dir/curl"
for scenario in ok icmp-filtered dns-failure tls-failure no-route; do
    if PATH="$temp_dir:$PATH" SB_NET_SCENARIO="$scenario" sb_network_check; then
        [[ "$scenario" == ok || "$scenario" == icmp-filtered ]] || { echo "Panne ignorée : $scenario" >&2; exit 1; }
    else
        [[ "$scenario" == dns-failure || "$scenario" == tls-failure || "$scenario" == no-route ]] || exit 1
    fi
done
if PATH="$temp_dir:$PATH" SB_NET_SCENARIO=dns-failure sb_fetch https://download.docker.com/linux/debian/gpg /dev/null; then
    echo 'Erreur curl 6 ignorée' >&2; exit 1
else
    [[ $? == 6 ]]
fi
echo 'Network diagnostics and configuration rendering checks passed'
