#!/bin/bash
set -Eeuo pipefail
umask 077
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mode=${1:---engine}
wait_seconds=60
eicar_base64='WDVPIVAlQEFQWzRcUFpYNTQoUF4pN0NDKTd9JEVJQ0FSLVNUQU5EQVJELUFOVElWSVJVUy1URVNULUZJTEUhJEgrSCo='
eicar_sha256=275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f
eicar() { printf '%s' "$eicar_base64" | base64 --decode; }
usage() {
    cat <<'EOF'
Tests Station Blanche — aucun malware réel, uniquement le fichier standard EICAR.

sudo bash deploy/test-antivirus.sh --engine [--wait SECONDES]
    Vérifie le moteur installé : fichier sain non détecté, EICAR détecté.
    Ne crée aucune analyse USB, aucun KPI ni copie de quarantaine.

bash deploy/test-antivirus.sh --fixtures DOSSIER
    Crée deux dossiers séparés, sain et EICAR, sans écraser de fichier existant.
    Copier seulement le dossier sain sur une clé de test vide pour le premier test.
    Pour le second test, ajouter ensuite EICAR depuis un poste où la clé est inscriptible.

bash deploy/test-antivirus.sh --verify-usb clean|infected sdb1 [SECONDES]
    Attendre une nouvelle analyse réelle de la partition indiquée (nécessite curl et jq).
    Retirer la clé avant de lancer ; insérer après le message du script.
    Vérifie le verdict, les erreurs, les KPI et, en mode infected, la copie EICAR en quarantaine.
EOF
}
fail() { echo "[ÉCHEC] $*" >&2; exit 1; }
seconds() { [[ "$1" =~ ^[1-9][0-9]{0,3}$ ]] && (( $1 <= 3600 )); }
need() { command -v "$1" >/dev/null || fail "Commande $1 manquante. Voir installation.sh --check."; }
need base64
need sha256sum
[[ $(eicar | sha256sum | cut -d' ' -f1) == "$eicar_sha256" ]] || fail 'Fixture EICAR invalide.'

case "$mode" in
    --help|-h) usage; exit 0 ;;
    --fixtures)
        [[ $# == 2 ]] || { usage; exit 2; }
        parent=$(realpath -e -- "$2")
        [[ -d "$parent" && -w "$parent" ]] || fail 'Choisir un répertoire existant et inscriptible.'
        output=$(mktemp -d "$parent/station-blanche-test.XXXXXXXX")
        mkdir "$output/clean" "$output/infected"
        printf 'Station Blanche : document de test sain, sans signature antivirus.\n' > "$output/clean/document-sain.txt"
        eicar > "$output/infected/eicar.com.txt"
        chmod 0755 "$output" "$output/clean" "$output/infected"
        chmod 0644 "$output/clean/document-sain.txt" "$output/infected/eicar.com.txt"
        [[ $(wc -c < "$output/infected/eicar.com.txt") == 68 ]] || fail 'Taille EICAR incorrecte.'
        echo "[OK] Fichier sain : $output/clean/document-sain.txt"
        echo "[OK] Test EICAR : $output/infected/eicar.com.txt (68 octets, SHA-256 vérifié)"
        echo 'Copier seulement clean/ sur une clé vide pour le test sain ; ajouter infected/ ensuite pour le test de détection.'
        echo 'La station monte les clés en lecture seule : préparer les fichiers sur un autre poste ou avant installation.'
        exit 0
        ;;
    --engine)
        if [[ $# != 1 && $# != 0 ]]; then
            [[ $# == 3 && "$2" == --wait ]] || { usage; exit 2; }
            wait_seconds=$3
        fi
        seconds "$wait_seconds" || fail 'Délai invalide (1 à 3600 secondes).'
        need docker
        docker compose config --quiet
        docker info >/dev/null || fail 'Docker inaccessible. Lancer avec sudo sur la station.'
        deadline=$((SECONDS + wait_seconds))
        echo 'Attente du moteur et des signatures vérifiées…'
        until docker compose exec -T app curl -fsS --max-time 5 http://127.0.0.1:8080/health/ready >/dev/null 2>&1; do
            (( SECONDS < deadline )) || fail 'Moteur non prêt. Consulter docker compose logs app clamav.'
            sleep 2
        done
        if output=$(printf 'Station Blanche : fichier de test sain.\n' | docker compose exec -T clamav clamdscan --config-file=/etc/clamav/clamd.conf --stream --no-summary - 2>&1); then code=0; else code=$?; fi
        printf '%s\n' "$output"
        [[ $code == 0 ]] || fail "Le fichier sain n'a pas été accepté (code $code)."
        echo '[OK] Test sain : aucune menace détectée.'
        if output=$(eicar | docker compose exec -T clamav clamdscan --config-file=/etc/clamav/clamd.conf --stream --no-summary - 2>&1); then code=0; else code=$?; fi
        printf '%s\n' "$output"
        [[ $code == 1 ]] || fail "EICAR non détecté ou erreur du moteur (code $code)."
        grep -qi eicar <<< "$output" || fail 'La signature détectée ne correspond pas à EICAR.'
        echo '[OK] Test EICAR : détection antivirus confirmée, sans virus réel.'
        exit 0
        ;;
    --verify-usb)
        [[ $# == 3 || $# == 4 ]] || { usage; exit 2; }
        expected=$2
        device=${3##*/}
        wait_seconds=${4:-300}
        [[ "$expected" == clean || "$expected" == infected ]] || fail 'Résultat attendu : clean ou infected.'
        [[ "$device" =~ ^[a-zA-Z0-9]+$ ]] || fail 'Partition invalide : par exemple sdb1.'
        seconds "$wait_seconds" || fail 'Délai invalide (1 à 3600 secondes).'
        need curl
        need jq
        need docker
        docker info >/dev/null || fail 'Docker inaccessible. Lancer avec sudo sur la station.'
        api=http://127.0.0.1:8080
        # Recette privilégiée via le conteneur : ne pas rouvrir l'historique au kiosque.
        api_get() { docker compose exec -T app curl -fsS --max-time 10 "$api$1"; }
        api_get /health/ready >/dev/null || fail 'Station non prête.'
        before=$(api_get /api/status)
        known=$(jq -c '[.scans[].id]' <<< "$before")
        jq -e '.progress.scan_id == null' <<< "$before" >/dev/null || fail 'Une analyse est déjà en cours. Attendre son terme.'
        if jq -e --arg device "$device" '.present_results[] | select(.device == $device)' <<< "$before" >/dev/null; then
            fail 'Retirer la clé avant de lancer le script pour vérifier une nouvelle analyse.'
        fi
        echo "Insérez maintenant la clé de test (partition $device). Attente maximale : $wait_seconds s."
        deadline=$((SECONDS + wait_seconds))
        while (( SECONDS < deadline )); do
            current=$(api_get /api/status) || fail 'Connexion à la station perdue.'
            result=$(jq -c --arg device "$device" --argjson known "$known" '[.scans[] | select(.device == $device and .finished_at != null) | select(.id as $id | ($known | index($id)) == null)][0] // empty' <<< "$current")
            if [[ -n "$result" ]]; then
                current=$(api_get /api/status) || fail 'Lecture des KPI impossible.'
                jq . <<< "$result"
                jq -e '.errors == 0' <<< "$result" >/dev/null || fail 'Analyse avec erreurs.'
                scan_id=$(jq -r '.id' <<< "$result")
                if [[ "$expected" == clean ]]; then
                    jq -e '.verdict == "no_threat_detected" and .threats == 0 and .files > 0' <<< "$result" >/dev/null || fail 'Verdict sain attendu sur une clé contenant le document de test.'
                else
                    jq -e '.verdict == "infected" and .threats > 0' <<< "$result" >/dev/null || fail 'Détection attendue.'
                    findings=$(api_get "/api/scans/$scan_id/findings")
                    jq -e --arg hash "$eicar_sha256" '[.[] | select(.kind == "threat" and .quarantine_id != null and .sha256 == $hash and (.detail | ascii_downcase | contains("eicar")))] | length > 0' <<< "$findings" >/dev/null || fail 'Copie EICAR vérifiée absente du rapport.'
                fi
                analyses_before=$(jq '.kpis.analyses' <<< "$before")
                jq -e --argjson count "$analyses_before" '.kpis.analyses > $count' <<< "$current" >/dev/null || fail 'Compteur des analyses non incrémenté.'
                if [[ "$expected" == infected ]]; then
                    threats_before=$(jq '.kpis.threats' <<< "$before")
                    copies_before=$(jq '.kpis.quarantined' <<< "$before")
                    jq -e --argjson threats "$threats_before" --argjson copies "$copies_before" '.kpis.threats > $threats and .kpis.quarantined > $copies' <<< "$current" >/dev/null || fail 'KPI de détection / quarantaine non incrémentés.'
                fi
                echo "[OK] Test USB $expected réussi : analyse, verdict et KPI vérifiés."
                exit 0
            fi
            sleep 2
        done
        fail 'Aucune nouvelle analyse terminée dans le délai. Vérifier la transmission USB à la VM et les journaux systemd.'
        ;;
    *) usage; exit 2 ;;
esac
