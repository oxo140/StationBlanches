# Station Blanche v2 — Rust, ClamAV et Docker

Refonte pour **Debian 13 (Trixie), dont 13.7, amd64**, avec bureau graphique et supports USB transmis à la machine. L'application Rust expose un tableau de bord local plein écran et une supervision HTTPS accessible par l'adresse IP de la station.

**Statut : version candidate à valider sur la VM.** Les tests Rust sont automatisés ; le montage USB, le moteur réel et la chaîne Docker doivent aussi passer la recette décrite dans [docs/VALIDATION.md](docs/VALIDATION.md). Les scripts Python historiques sont conservés dans `legacy/` et ne sont plus installés.

## Fonctionnement

- Détection des partitions USB par udev/systemd sur l'hôte et montage **lecture seule, nodev, nosuid, noexec** dans `/srv/station-blanche/media`.
- Propagation des montages vers Docker : pas de conteneur privilégié, pas d'accès à `/dev`, pas de socket Docker dans l'application.
- Client de scan Rust : lecture en blocs de 64 Kio, SHA-256 calculé pendant cette lecture, envoi INSTREAM à ClamAV. La base reste chargée en mémoire dans `clamd`.
- Parcours des fichiers en flux, fichiers cachés inclus, sans suivre les liens. Les ouvertures Linux utilisent `openat2` pour rester dans le support analysé.
- Les partitions sont traitées en file d'attente, une à la fois. Une réinsertion produit une nouvelle analyse. Après recréation de l'application, les supports présents sont réanalysés.
- Recherche de nouvelles signatures toutes les **6 heures**, nouvelle tentative après **1 heure** en cas d'échec. La dernière vérification réussie doit dater de moins de **24 heures** et la version doit être chargée par ClamAV.
- Verdicts distincts : **aucune menace détectée**, **menace détectée**, **analyse incomplète**, **interrompue**. Fichier illisible, erreur, lien, fichier spécial, limite dépassée ou déconnexion ne donnent jamais un verdict favorable.
- Copie des fichiers détectés dans une quarantaine privée, nom aléatoire, droits `0600`, vérification SHA-256. **L'original n'est pas supprimé de la clé** : celle-ci reste potentiellement dangereuse. Aucune restauration ou ouverture des échantillons depuis le navigateur.
- Historique SQLite et indicateurs persistants : analyses, fichiers, volumes lus, détections, partitions infectées, copies en quarantaine, analyses incomplètes et durée moyenne. Les compteurs concernent les **partitions**, pas nécessairement des clés physiques distinctes.

ClamAV examine également les archives dans ses limites configurées. Le SHA-256 sert ici à l'intégrité et à la traçabilité, pas de moteur antivirus unique. Aucun produit ne garantit l'absence de toute menace.

## Préparer la VM

Prévoir **4 vCPU, 8 Go de RAM, 40 Go de disque minimum**, un bureau GNOME ou XFCE, une connexion Internet et une IPv4 fixe ou une réservation DHCP. Ces ressources sont une base de départ, à ajuster après mesure. Le stockage doit aussi accueillir les bases et la quarantaine.

Configurer le passage USB de l'hyperviseur vers Debian. Vérifier avec `lsblk -f` que la clé apparaît **dans la VM**. Docker ne peut pas rendre visible un périphérique que la VM ne reçoit pas.

Ne pas installer cette station sur le disque USB destiné aux analyses : les règles réservent les systèmes de fichiers USB à la station.

## Installer

**Installation en une ligne**, depuis un terminal Debian avec sudo :

```bash
(set -e; sudo apt-get update; sudo apt-get install -y ca-certificates curl; sb_install=$(mktemp); trap 'rm -f -- "$sb_install"' EXIT; curl -fsSL https://raw.githubusercontent.com/oxo140/StationBlanches/codex/v2-rust-docker/deploy/bootstrap.sh -o "$sb_install"; sudo bash "$sb_install")
```

Cette commande télécharge l'installateur depuis **la branche de refonte** puis l'exécute ; elle fonctionne avant la fusion dans `main`. Les sources sont installées dans `/opt/station-blanche`. Le script vérifie Debian 13 amd64, inventorie les dépendances et demande l'adresse IP avec une proposition automatique.

L'assistant pose des questions **oui/non** pour installer les dépendances manquantes, Docker et ses plugins, puis choisir Xfce si aucun bureau reconnu n'est présent, Chromium, son démarrage automatique, SSH, les outils de vérification des KPI, le démarrage des conteneurs et les tests antivirus. Refuser un prérequis obligatoire arrête l'installation ; refuser une option conserve la configuration existante. Le mot de passe HTTPS existant est conservé. Rust et ClamAV sont installés dans les images Docker, sans chaîne Rust à installer sur Debian.

### Réseau : DHCP, IPv4 manuelle et DNS

**Avant apt et les téléchargements Docker**, l'installateur propose de conserver la configuration actuelle (DHCP par défaut si déjà actif), de passer en DHCP, de définir une adresse IPv4 manuelle avec préfixe et passerelle, ou de corriger seulement les DNS en conservant l'adresse DHCP. Les DNS manuels sont saisis explicitement ; aucun DNS public n'est imposé.

Le diagnostic affiche les adresses et la route IPv4, teste `ping 8.8.8.8` et `ping google.com`, vérifie la résolution des domaines nécessaires à Docker, GitHub, Debian et ClamAV, puis l'accès HTTPS. Un ping filtré ne bloque pas une connexion dont le DNS et HTTPS fonctionnent. Une panne DNS, l'absence de route ou une erreur HTTPS bloque les téléchargements avec une explication.

```bash
cd /opt/station-blanche && sudo bash installation.sh --network-check
```

Configurer ou réparer le réseau indépendamment du reste de l'installation :

```bash
cd /opt/station-blanche && sudo bash installation.sh --network
```

La configuration automatique prend en charge un profil NetworkManager actif, ainsi que les configurations ifupdown simples dans `/etc/network/interfaces` et `/etc/network/interfaces.d/`. Les autres interfaces et les adresses IPv6 sont conservées. Les configurations personnalisées non reconnues sont laissées intactes et doivent être modifiées dans leur gestionnaire Debian.

Avec NetworkManager, un profil est cloné et un checkpoint permet le retour à l'ancien profil sans confirmation dans les 180 secondes ; saisir **Yes** pour conserver les changements après le diagnostic. Avec ifupdown, les fichiers sont sauvegardés sous `/var/lib/station-blanche-network/` et un timer de restauration protège la modification ; confirmer le résultat dans le délai. Les hooks DNS prennent en charge les renouvellements dhclient/dhcpcd. Ne pas remplacer manuellement un `/etc/resolv.conf` géré par un résolveur.

**`curl: (6) Could not resolve host: download.docker.com` indique une panne de résolution DNS**, même si une adresse DHCP est présente. Choisir l'option de correction DNS pour essayer les serveurs de votre réseau ou des serveurs publics autorisés (exemple : `1.1.1.1 8.8.8.8`). Une IPv4 fixe seule ne corrige pas le DNS. En cas d'erreur curl 6 pendant le téléchargement de la clé Docker, l'ancienne clé est conservée et l'installation s'arrête sans enregistrer une clé partielle. Si le DNS est tellement défaillant que GitHub lui-même ne peut pas être joint, utiliser d'abord les paramètres réseau du bureau ou `sudo nmtui` si disponible : aucun installateur distant ne peut être téléchargé sans résolution DNS.

Avec DHCP, réserver l'adresse de la station dans le routeur. Si son adresse change, relancer l'installateur pour actualiser l'adresse d'écoute HTTPS et le certificat par IP.

**Alternative : installation depuis un clone**, pour consulter les scripts avant exécution :

```bash
sudo apt update
sudo apt install -y git
git clone https://github.com/oxo140/StationBlanches.git
cd StationBlanches
# Tant que la refonte n'est pas fusionnée :
git switch codex/v2-rust-docker
sudo bash installation.sh 192.168.1.50 "$USER"
```

Remplacer l'adresse par celle de la VM. Le script vérifie Debian 13 et amd64, installe Docker via son dépôt officiel si absent, prépare systemd/udev et construit les images. Il demande un mot de passe administrateur de 16 caractères minimum et en conserve seulement le hash bcrypt. Les fichiers privés sont dans `secrets/`, exclus de Git.

Diagnostic des dépendances, **sans installer ni modifier quoi que ce soit** :

```bash
cd /opt/station-blanche && sudo bash installation.sh --check
```

Le diagnostic vérifie les paquets et commandes hôte, Docker CLI, Compose, Buildx, l'accès au démon et la configuration lorsqu'elle existe. Code de sortie `0` : dépendances requises disponibles ; `1` : élément manquant ou Docker inaccessible. Les composants optionnels sont signalés séparément. Si Docker Debian `docker.io` existe déjà, les plugins manquants sont installés depuis Debian ; aucune migration ou suppression automatique d'un moteur existant n'est faite.

Le script n'effectue pas de mise à niveau générale de Debian et n'ajoute pas d'extinction automatique. Une réinstallation conserve les données et le mot de passe existant.

Retirer puis réinsérer les clés déjà montées par le bureau avant l'installation. La première récupération des signatures peut prendre plusieurs minutes ; l'application reste bloquée tant que le moteur n'est pas prêt.

- Écran local : `http://127.0.0.1:8080/?kiosk=1`, lecture seule, accessible uniquement depuis la station.
- Supervision distante : `https://192.168.1.50`, utilisateur `admin`, mot de passe choisi à l'installation.
- Chromium se lance à la connexion au bureau si l'utilisateur a été fourni au script. L'ouverture automatique de session et la désactivation de veille restent des choix à configurer dans Debian.

## Tester : fichier sain et détection antivirus

Le test utilise le [fichier standard EICAR](https://www.eicar.org/download-anti-malware-testfile/), **pas un vrai virus**. Son contenu est généré localement et vérifié (68 octets, SHA-256), sans téléchargement d'échantillon malveillant.

### Test automatique du moteur installé

```bash
cd /opt/station-blanche && sudo bash deploy/test-antivirus.sh --engine --wait 900
```

Le script attend le moteur et des signatures vérifiées, puis exige un code `0` pour un document sain et un code `1` avec une signature EICAR pour le fichier de test. Une panne du moteur ou l'absence de détection fait échouer le script. Ces deux scans directs **ne modifient pas l'historique USB, les KPI ou la quarantaine**.

### Test complet avec une clé USB

Sur un poste de préparation Linux (ou avant d'activer les montages en lecture seule), créer les fichiers :

```bash
bash deploy/test-antivirus.sh --fixtures /tmp
```

Le script affiche un nouveau répertoire contenant `clean/document-sain.txt` et `infected/eicar.com.txt`, sans écraser de fichier existant. Copier **seulement `clean/`** sur une clé de test vide, puis retirer la clé du poste de préparation. Sur la station, retirer la clé avant de lancer le script suivant et l'insérer quand le script le demande :

```bash
cd /opt/station-blanche && bash deploy/test-antivirus.sh --verify-usb clean sdb1 300
```

Remplacer `sdb1` par la partition reçue dans la VM, visible avec `lsblk`. Le test exige une **nouvelle** analyse de cette partition, au moins un fichier analysé, zéro détection, zéro erreur et une hausse du compteur d'analyses.

Ensuite, ajouter `infected/eicar.com.txt` sur la clé depuis le poste de préparation, la retirer et lancer sur la station :

```bash
cd /opt/station-blanche && bash deploy/test-antivirus.sh --verify-usb infected sdb1 300
```

Insérer la clé après le message. Le script vérifie le verdict infecté, l'absence d'erreur, l'enregistrement d'une copie EICAR avec le bon SHA-256 et l'augmentation des KPI d'analyse, détection et quarantaine. `jq` est nécessaire et proposé par l'installateur. Les analyses de test restent dans l'historique ; le script n'efface aucun résultat ni fichier sur la clé. La copie isolée n'enlève pas l'original EICAR de la clé.

## Faire confiance au certificat HTTPS

L'accès par IP utilise l'autorité locale de Caddy. Il faut installer **uniquement son certificat public** sur les postes d'administration :

```bash
sudo docker compose cp web:/data/caddy/pki/authorities/local/root.crt ./station-blanche-ca.crt
```

Transférer ce certificat par un canal de confiance et comparer son empreinte :

```bash
openssl x509 -in station-blanche-ca.crt -noout -fingerprint -sha256
```

Sous Windows, importer ce certificat dans les autorités de certification racines de confiance du compte administrateur. Sous Debian, le copier dans `/usr/local/share/ca-certificates/` puis lancer `sudo update-ca-certificates`. Certains navigateurs utilisent leur propre magasin. Ne pas contourner les avertissements de certificat et ne jamais exporter `root.key`.

Seul le port HTTPS 443 est publié sur l'IP choisie. Le HTTP local reste lié à `127.0.0.1` ; le port ClamAV 3310 n'est pas publié. Le réseau Docker du moteur est isolé de celui de la supervision. Ne pas rediriger le port 443 depuis Internet. Les postes locaux de la station ont accès à la supervision sans authentification via loopback : la session du kiosque doit rester réservée à cet usage.

## Mettre à jour l'application

À effectuer entre deux analyses, après un instantané ou une sauvegarde :

```bash
cd /opt/station-blanche
sudo git pull --ff-only
sudo bash deploy/update.sh
```

Pour un clone installé manuellement dans votre compte, utiliser `git pull --ff-only` sans sudo dans ce clone.

Ce script reconstruit les images avec les paquets Debian courants et recrée les conteneurs. Les volumes `history`, `quarantine`, `signatures` et Caddy sont conservés. Les signatures sont mises à jour séparément, sans reconstruire l'application.

Ne pas exécuter `docker compose down -v` : cela supprime les volumes. Les tags de base `rust:1-trixie`, `debian:trixie-slim` et `caddy:2` suivent les correctifs ; pour un déploiement figé, consigner et épingler leurs digests après la recette. Les dépendances Rust sont verrouillées par `Cargo.lock`.

Mise à jour immédiate des signatures, sans lancer deux instances concurrentes de FreshClam :

```bash
sudo docker compose restart clamav
```

Les analyses sont bloquées pendant le redémarrage. Une analyse active peut devenir incomplète : attendre son terme avant maintenance.

## Exploitation et sauvegardes

```bash
sudo docker compose ps
sudo docker compose logs --tail=100 app clamav web
curl -i http://127.0.0.1:8080/health/ready
systemctl status station-blanche-media.service
journalctl -u 'station-blanche-usb@*' --since today
findmnt -R /srv/station-blanche/media
```

`/health/live` vérifie que le serveur répond ; `/health/ready` retourne 503 si le moteur ou les signatures sont indisponibles. Le tableau de bord affiche la raison du blocage. Les contrôles Docker n'effectuent pas de redémarrage sur un simple état `unhealthy` : surveiller les alertes affichées.

Pour sauvegarder, arrêter l'application et ClamAV, sauvegarder les volumes Docker, `.env` et `secrets/`, puis redémarrer. Ne pas copier un fichier SQLite en cours d'écriture en oubliant son WAL. Le volume de quarantaine contient des fichiers potentiellement dangereux : conserver des droits stricts et ne pas l'exposer au partage réseau. Aucune purge automatique n'est appliquée ; surveiller l'espace disque et définir une politique de rétention avant production.

## Limites de cette version candidate

- Formats montés : FAT, exFAT, NTFS via ntfs3, ext2/3/4. Supports chiffrés et autres formats non montés automatiquement. Les permissions Unix des fichiers sont respectées ; un fichier inaccessible entraîne un résultat incomplet.
- Limite par fichier : **100 Mio**. Limites d'archives : 256 Mio de données analysées, 10 000 fichiers et 20 niveaux ; un dépassement signalé par le moteur entraîne un résultat incomplet. Une archive chiffrée peut être signalée comme détection heuristique.
- La quarantaine est une copie isolée et non une désinfection du support. Il faut traiter la clé séparément après une détection.
- Administration web en lecture seule : pas de suppression, restauration, lancement de commande ou mise à jour applicative depuis le navigateur. Le module mail historique est désactivé.
- Les 100 dernières analyses et les 500 premiers événements d'une analyse sont affichés ; les compteurs globaux utilisent tout l'historique. Les analyses du jour sont comptées en UTC, les heures affichées dans le fuseau du navigateur.
- Docker isole les services mais pas le noyau qui monte le système de fichiers. Garder Debian à jour et utiliser une machine dédiée ; la station ne protège pas contre toutes les attaques matérielles USB.

## Développer et vérifier

```bash
cargo fmt --check
cargo clippy --locked --all-targets -- -D warnings
cargo test --locked
```

Le binaire se compile aussi sur Windows pour les tests de protocole et de persistance ; le scan USB de production nécessite Linux. Voir [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) et [docs/VALIDATION.md](docs/VALIDATION.md).
