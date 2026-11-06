# Station Blanche

**Une station d’analyse USB avec un écran local, une administration web et un historique exportable.**

[Installer](#installation-en-une-ligne) · [Utiliser](#analyser-un-support-usb) · [Administrer](#accéder-aux-interfaces) · [Mettre à jour](#mettre-à-jour-lapplication) · [Dépanner](#diagnostic-rapide)

Station Blanche analyse automatiquement les partitions USB avec **ClamAV**, piloté par une application **Rust**. Les supports sont montés en lecture seule. Les résultats, les détections et les copies de quarantaine sont conservés dans des volumes Docker.

**Plateforme : Debian 13 (Trixie), amd64, avec bureau graphique.** Une VM doit recevoir les périphériques USB par l’hyperviseur.

> **Version candidate.** Le projet contient des tests automatisés ; la validation sur une Debian vierge, les supports physiques et chaque bureau utilisé reste nécessaire avant production. Voir la [recette de validation](docs/VALIDATION.md).

## Installation en une ligne

Dans un terminal **sur la machine Debian**, avec un compte disposant de `sudo` :

```bash
(set -e; sudo apt-get update; sudo apt-get install -y ca-certificates curl; sb_install=$(mktemp); trap 'rm -f -- "$sb_install"' EXIT; curl -fsSL https://raw.githubusercontent.com/oxo140/StationBlanches/codex/v2-rust-docker/deploy/bootstrap.sh -o "$sb_install"; sudo bash "$sb_install")
```

La commande récupère actuellement la branche **`codex/v2-rust-docker`**, puis installe le projet dans **`/opt/station-blanche`**. Elle réutilise un dépôt existant s’il correspond à cette branche et ne contient pas de modifications locales.

L’installateur :

- vérifie le réseau, les sources APT et les dépendances ; installe les composants manquants ;
- conserve la configuration réseau actuelle par défaut et demande seulement si une **IPv4 manuelle** est souhaitée ;
- installe Docker, construit l’application et prépare les montages USB ;
- configure Chromium, l’ouverture automatique de session et les réglages anti-veille/verrouillage ;
- configure la supervision HTTPS, la confiance du certificat sur la station, SSH et l’accès RDP Windows ;
- attend les signatures antivirus et lance les tests avec un document sain et le fichier de test EICAR.

Au premier lancement, créer le **mot de passe administrateur web**, de 16 caractères minimum. Le mot de passe du compte Debian reste inchangé. Une réinstallation conserve les mots de passe existants et les volumes de données.

**Redémarrer Debian à la fin** pour appliquer tous les réglages du bureau et l’ouverture automatique de session. L’installateur n’arrête pas la session en cours.

## Préparer la machine

| Élément | Configuration de départ |
|---|---|
| Système | Debian 13 amd64 |
| Ressources | 4 vCPU, 8 Go de RAM, 40 Go de disque, à ajuster après mesure |
| Bureau | GNOME, GNOME Flashback, Xfce, KDE Plasma, Cinnamon, MATE, LXDE ou LXQt |
| Réseau | Internet pour les signatures ; DHCP avec réservation conseillé, ou IPv4 manuelle |
| USB en VM | Transmission du périphérique à Debian, vérifiable avec `lsblk -f` |

Prévoir de l’espace supplémentaire pour la quarantaine et les fichiers temporaires du moteur. Utiliser un disque système distinct des supports USB à analyser. GDM3, LightDM, SDDM et LXDM sont pris en charge pour l’ouverture automatique de session ; un gestionnaire inconnu produit une erreur explicite.

Pour l’installation depuis un clone, le choix du compte bureau ou la configuration réseau avancée, consulter le [guide d’installation](docs/INSTALLATION.md).

## Analyser un support USB

1. Brancher le support sur la station, ou le transmettre à la VM.
2. Attendre le comptage, puis l’analyse automatique. L’écran affiche la progression par nombre de fichiers, le fichier courant, le volume lu et le débit moyen effectif.
3. Attendre le résultat final avant de retirer le support.

Le comptage parcourt les répertoires sans lire le contenu des fichiers. La progression n’est pas une estimation du temps restant : un gros fichier peut prendre plus de temps que de nombreux petits fichiers. Les partitions sont traitées une à une ; une clé contenant plusieurs partitions génère plusieurs analyses. Une réinsertion déclenche une nouvelle analyse.

| Résultat affiché | Signification |
|---|---|
| **Aucune menace détectée** | Le parcours est terminé sans détection ni erreur, avec un moteur disponible et des signatures vérifiées. |
| **Analyse terminée · N fichiers non vérifiés** | Certains fichiers n’ont pas pu être entièrement contrôlés. Le résultat reste avec réserves ; **Voir les raisons** explique chaque incident. |
| **Menace détectée** | Une détection est enregistrée, avec copie en quarantaine lorsqu’elle réussit. |
| **Analyse interrompue** | Le parcours n’a pas pu être terminé : retrait du support, maintenance ou défaillance, par exemple. |

Une archive ou un document protégé par mot de passe est signalé comme **non vérifiable**. Le chiffrement peut servir à dissimuler un logiciel malveillant, mais ne prouve pas une infection. Un fichier trop volumineux, notamment une image ISO, est également signalé avec sa raison.

**La quarantaine est une copie : l’original reste sur la clé USB.** Elle ne désinfecte pas le support. Une copie échouée est signalée dans le rapport. Aucun antivirus ne garantit l’absence de toute menace.

## Accéder aux interfaces

| Accès | Adresse ou outil | Identifiants |
|---|---|---|
| Écran USB sur la station | `http://127.0.0.1:8080/kiosk` | Aucun pour l’état local |
| Supervision web | `https://IP_DE_LA_STATION` | `admin` et le mot de passe créé dans l’installateur |
| Bureau distant Windows | `mstsc`, puis `IP_DE_LA_STATION:3389` | Compte Debian et son mot de passe existant |
| SSH | `ssh UTILISATEUR@IP_DE_LA_STATION` | Compte Debian et ses méthodes d’authentification |

Le bouton **Supervision** ouvre une page de connexion, même depuis la station. Elle propose **Afficher / Masquer** le mot de passe et indique le résultat de sa vérification. La session web dure au maximum huit heures ; la déconnexion ou le redémarrage de l’application la révoque. **L’historique et l’export CSV restent authentifiés, y compris via l’adresse locale.**

Le certificat HTTPS est approuvé automatiquement dans le système Debian et les magasins Chromium de la station. Sur un autre poste, importer le certificat public après vérification de son empreinte : [procédure HTTPS](docs/EXPLOITATION.md#certificat-https).

XRDP ouvre un **bureau Xfce de maintenance séparé** ; il ne partage pas l’écran local et ne remplace pas le kiosque. Choisir **Xorg** si demandé. Le compte `admin` du site web n’est pas un compte RDP. Voir le [guide RDP](docs/EXPLOITATION.md#bureau-à-distance-windows).

### Historique et export CSV

La supervision présente les KPI, les dernières analyses, les fichiers non vérifiés et leurs raisons, ainsi que les références de quarantaine.

**Exporter tout l’historique · CSV** télécharge **une ligne par analyse enregistrée**, sans la limite des 100 analyses affichées. L’export comprend les dates UTC, compteurs, résultats, moteur et tous les événements disponibles, avec leurs raisons, références de quarantaine et SHA-256.

Le CSV est compatible Excel/LibreOffice : UTF-8 avec BOM, séparateur point-virgule et champs protégés contre l’interprétation en formules. Les détails ne sont pas limités aux 500 événements de la fenêtre web. Le téléchargement se fait en flux sur un instantané de l’historique.

Les KPI comptent des **analyses de partitions**, pas forcément des clés physiques distinctes. Les analyses du jour sont comptées en UTC ; les dates de l’interface suivent le fuseau du navigateur. Les anciens événements restent conservés avec leurs codes techniques d’origine.

## Mise à jour des signatures antivirus

FreshClam récupère les bases officielles ClamAV auprès de `database.clamav.net` : `main`, `daily` et `bytecode`.

| Situation | Comportement actuel |
|---|---|
| Démarrage du conteneur ClamAV | Vérification des bases avant le lancement du moteur |
| Fonctionnement normal | Nouveau contrôle toutes les **6 heures** |
| Échec d’un contrôle périodique | Nouvelle tentative **1 heure** plus tard |
| Échec du tout premier contrôle au démarrage | Prochaine tentative planifiée après **6 heures** — limite actuelle |
| Aucun contrôle réussi depuis plus de **24 heures** | Nouvelles analyses bloquées |

FreshClam vérifie les bases et demande leur rechargement. L’application compare la version `daily` vérifiée à celle annoncée par le moteur avant d’autoriser une analyse. Un contrôle sans nouveauté est un succès ; un échec ne rafraîchit jamais artificiellement la date. Les bases sont conservées après recréation des conteneurs.

**Les signatures sont mises à jour automatiquement ; le programme ClamAV et l’application se mettent à jour par reconstruction des images.** Les fichiers USB sont analysés localement, sans envoi à un service d’analyse en ligne.

## Mettre à jour l’application

Entre deux analyses, après une sauvegarde ou un instantané :

```bash
cd /opt/station-blanche && sudo git pull --ff-only && sudo bash deploy/update.sh
```

Le script réapplique les intégrations du bureau et de XRDP, reconstruit les images et recrée les conteneurs. L’historique, la quarantaine, les signatures et les données Caddy sont conservés. Redémarrer Debian lorsque les réglages du bureau ont changé.

Pour un clone appartenant à votre compte utilisateur, exécuter `git pull --ff-only` sans `sudo` dans ce clone. **Ne pas utiliser `docker compose down -v` pour une mise à jour : cette option supprime les volumes.**

## Diagnostic rapide

Les commandes suivantes sont à exécuter dans `/opt/station-blanche` :

| Besoin | Commande |
|---|---|
| État des conteneurs | `sudo docker compose ps -a` |
| Journaux récents | `sudo docker compose logs --tail=100 app clamav web` |
| Dépendances et réseau, sans installation | `sudo bash installation.sh --check` |
| Réseau uniquement | `sudo bash installation.sh --network-check` |
| Réparation réseau interactive | `sudo bash installation.sh --network` |
| Accès à l’écran local | `sudo bash deploy/check-web.sh 10` |
| Page Chromium chargée et onglet actif | `sudo bash deploy/check-kiosk.sh` |
| Services et port RDP | `sudo bash deploy/check-rdp.sh` |
| Tests antivirus sain / EICAR | `sudo bash deploy/test-antivirus.sh --engine --wait 900` |

`curl: (6) Could not resolve host` indique un problème DNS : une adresse DHCP ne garantit pas la résolution des noms. Si GitHub lui-même ne peut pas être résolu, corriger d’abord le réseau dans Debian. Le [guide d’installation](docs/INSTALLATION.md#réseau--dhcp-ipv4-manuelle-et-dns) détaille le diagnostic et le retour arrière des changements réseau.

Les tests EICAR utilisent un fichier standard de test, pas un véritable virus. Les commandes ci-dessus ne remplacent pas la [recette complète sur supports USB](docs/EXPLOITATION.md#tester-le-moteur-et-les-supports-usb).

## Bureau et disponibilité du kiosque

L’ouverture automatique de session et les réglages anti-veille/verrouillage concernent le compte du kiosque. **Le mot de passe Debian reste inchangé et n’est pas enregistré par l’application.** Les réglages remplacés sont sauvegardés avant modification.

Chromium utilise un profil dédié en navigation privée pour éviter la demande de déverrouillage du trousseau. Le trousseau du bureau, notamment pour le Wi-Fi, reste inchangé. Une fermeture complète du navigateur impose une nouvelle connexion à la supervision.

Le superviseur contrôle le rendu de la page et l’onglet actif par un **pipe privé, sans port de débogage réseau**. Il accepte le kiosque, la connexion ou la supervision. Il relance Chromium cinq secondes après sa fermeture et récupère un onglet disparu après un défaut confirmé. Le démarrage initial dispose d’une tolérance de vingt secondes ; un navigateur bloqué entraîne une récupération limitée puis un redémarrage. Ce contrôle ne confirme pas l’état physique du moniteur.

## Architecture et limites

| Composant | Rôle |
|---|---|
| Application Rust | Parcours USB, communication antivirus, SHA-256, quarantaine, SQLite, API et connexion web |
| ClamAV / FreshClam | Détection des menaces et actualisation des signatures |
| Caddy | Accès HTTPS et contrôle de la session web |
| Scripts Shell / Python | Installation Debian, montages, bureau, XRDP et surveillance de Chromium |
| HTML / CSS / JavaScript | Écran local et administration web |

Les fichiers sains sont lus une seule fois pour l’envoi à ClamAV et le SHA-256. Seuls les fichiers détectés sont relus pour vérifier leur copie de quarantaine. Les conteneurs ne reçoivent ni mode privilégié ni socket Docker ; le montage USB est effectué sur l’hôte.

- **1 Gio par fichier**, **2 Gio cumulés par archive**, 10 000 fichiers internes et 20 niveaux d’archives. Un dépassement empêche la validation complète du fichier.
- Délais : dix minutes de traitement ClamAV et quinze minutes pour transmettre un fichier depuis le support. Les temporaires ClamAV utilisent un volume sur disque.
- Formats montés : FAT, exFAT, NTFS via ntfs3, ext2/3/4. Les supports chiffrés et les autres formats ne sont pas montés automatiquement.
- Quarantaine par copie ; aucune suppression ou restauration depuis le navigateur. Aucune purge automatique : surveiller l’espace disque.
- Docker partage le noyau de l’hôte : l’isolation ne couvre pas toutes les attaques matérielles USB. Les performances dépendent notamment du support et du moteur ; aucun gain chiffré n’est annoncé sans mesure.

## Documentation et développement

- [Installation détaillée et configuration réseau](docs/INSTALLATION.md)
- [Exploitation : certificats, RDP, tests et sauvegardes](docs/EXPLOITATION.md)
- [Architecture technique](docs/ARCHITECTURE.md)
- [Recette Debian et validation avant production](docs/VALIDATION.md)

```bash
cargo fmt --check
cargo clippy --locked --all-targets -- -D warnings
cargo test --locked
```

Le binaire peut être compilé sous Windows pour certains tests ; **le scan USB de production nécessite Linux**. Les dépendances Rust sont verrouillées par `Cargo.lock`. Les scripts historiques de `legacy/` ne sont plus installés.
