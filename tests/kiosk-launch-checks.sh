#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
temp_dir=$(mktemp -d)
cleanup() { rm -rf -- "$temp_dir"; }
trap cleanup EXIT
mkdir "$temp_dir/bin" "$temp_dir/scripts"
cp deploy/host/kiosk-launch.sh deploy/host/kiosk-supervisor.py "$temp_dir/scripts/"
printf '#!/usr/bin/python3\n' > "$temp_dir/scripts/desktop-session.py"
cat > "$temp_dir/bin/python3" <<'EOF'
#!/bin/bash
# Simuler seulement les sondes de santé, sans bureau ni serveur système.
exec /usr/bin/python3 "$@"
EOF
cat > "$temp_dir/bin/chromium" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$SB_TEST_LAUNCHES"
exit 0
EOF
chmod +x "$temp_dir/bin/"*
export SB_TEST_LAUNCHES="$temp_dir/launches"
export XDG_CONFIG_HOME="$temp_dir/config"
export XDG_RUNTIME_DIR="$temp_dir/runtime"
export PATH="$temp_dir/bin:$PATH"
mkdir -p "$XDG_RUNTIME_DIR"
cat > "$temp_dir/scripts/opener.py" <<'EOF'
import importlib.util,sys
spec=importlib.util.spec_from_file_location("supervisor",sys.argv[1])
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class Response:
    status=200
    def __enter__(self): return self
    def __exit__(self,*args): pass
class Opener:
    def open(self,*args,**kwargs): return Response()
module.build_opener=lambda *_: Opener()
sys.argv=sys.argv[1:]
module.main()
EOF
# Intercaler une sonde de santé simulée ; le vrai superviseur et les pipes sont conservés.
mv "$temp_dir/scripts/kiosk-supervisor.py" "$temp_dir/scripts/supervisor.py"
cat > "$temp_dir/scripts/kiosk-supervisor.py" <<EOF
import runpy,sys
sys.argv=["$temp_dir/scripts/opener.py", "$temp_dir/scripts/supervisor.py", *sys.argv[1:]]
runpy.run_path("$temp_dir/scripts/opener.py",run_name="__main__")
EOF
status=0
timeout --signal=TERM 8 bash "$temp_dir/scripts/kiosk-launch.sh" || status=$?
[[ "$status" == 124 ]]
[[ $(wc -l < "$SB_TEST_LAUNCHES") -ge 2 ]]
grep -q -- '--kiosk' "$SB_TEST_LAUNCHES"
grep -q -- '--user-data-dir=' "$SB_TEST_LAUNCHES"
# Un second lanceur ne doit pas ouvrir une autre fenêtre.
count=$(wc -l < "$SB_TEST_LAUNCHES")
flock "$XDG_CONFIG_HOME/station-blanche/kiosk.lock" bash "$temp_dir/scripts/kiosk-launch.sh"
[[ $(wc -l < "$SB_TEST_LAUNCHES") == "$count" ]]
echo 'Kiosk relaunch and single-instance checks passed'
