# Recette Debian 13.7 — à réaliser avant production

La compilation Windows ne remplace pas cette recette Linux. Noter la version Debian, le noyau, les digests des images et la version ClamAV avec les résultats.

## Contrôles automatisés

La CI exécute formatage, Clippy et tests Rust sur Linux, puis construit les images. Les tests couvrent les verdicts, les signatures périmées ou non chargées, les réponses du moteur, l'historique après redémarrage, l'intégrité de quarantaine et le confinement des ouvertures Linux. Un vrai démon ClamAV détecte une signature de test inoffensive. Les images sont également démarrées avec leurs restrictions de production pour vérifier la disponibilité HTTP, le blocage sans moteur, les permissions des volumes, l'arrêt SIGTERM et la validation de la configuration HTTPS/authentification Caddy.

## Installation et accès

Le README propose une commande d'installation en une ligne. Le bootstrap réutilise ou récupère la branche de refonte dans `/opt/station-blanche`. L'installation conserve le DHCP par défaut et demande uniquement si une IPv4 manuelle est souhaitée ; les composants manquants sont installés automatiquement. Le mot de passe HTTPS est saisi seulement lors de sa création. Les tests APT vérifient la réutilisation de Chromium et des sources actives, l'absence de réinstallation inutile et le refus d'un paquet sans candidat. `sudo bash installation.sh --check` produit un diagnostic sans installation. Les tests des scripts vérifient aussi les adresses, les fichiers de recette, le refus d'une panne moteur ou d'un EICAR non détecté, puis les verdicts USB et l'absence de copie de quarantaine via des réponses API simulées. Le conteneur ClamAV réel est également testé avec un document sain et EICAR ; les supports physiques restent à tester ci-dessous.

1. Installer sur une VM Debian 13.7 amd64 avec bureau, 4 vCPU et 8 Go RAM, USB transmis.
2. Lancer l'installateur ; vérifier les trois services avec `docker compose ps`.
3. Vérifier que l'écran indique un blocage jusqu'à la disponibilité des signatures, puis que `/health/ready` retourne 200.
4. Depuis un autre poste : HTTP 8080 et ClamAV 3310 inaccessibles. HTTPS 443 redirige vers `/login` sans fenêtre Basic Auth. Un mauvais mot de passe affiche une erreur ; vérifier l'espacement des tentatives, puis connexion avec `admin`, accès API et révocation immédiate par Déconnexion. L'accès local direct à l'historique doit également rediriger vers la connexion HTTPS.
5. Vérifier que l'installation/mise à jour approuve le certificat public Caddy sur Debian et pour Chromium. Après redémarrage du navigateur, l'IP HTTPS ne doit plus afficher d'erreur TLS. Sur un autre poste, importer séparément le certificat public après vérification de l'empreinte.
6. Redémarrer la VM : propagation des montages disponible, services actifs, kiosque lancé après connexion au bureau.
7. Fermer Chromium : vérifier sa réouverture après cinq secondes et l'absence d'une deuxième instance si le lanceur est exécuté deux fois.
8. Vérifier le bureau et le gestionnaire de connexion détectés. Après redémarrage : ouverture automatique du compte prévu sans modification du mot de passe Debian ; absence de verrouillage, écran noir et suspension après le délai habituel. Refaire la recette sur chaque bureau utilisé, en X11 et Wayland lorsqu'ils sont disponibles.
9. Garder Chromium ouvert mais fermer l'onglet Station Blanche : vérifier sa réouverture. Ouvrir la supervision : elle doit rester utilisable sans retour forcé au kiosque. Une page d'erreur ou un rendu bloqué ne doivent pas donner un diagnostic `visible`. Vérifier `sudo bash deploy/check-kiosk.sh` et l'absence de port de débogage Chromium en écoute.

## Supports et verdicts

1. Clé FAT/exFAT avec fichier ordinaire et fichier caché : tous les fichiers comptés, aucune menace détectée.
2. Clé contenant un fichier de test antivirus EICAR obtenu depuis sa source officielle : détection, SHA-256 enregistré, copie privée en quarantaine, original conservé. Ne pas utiliser de malware réel pour la recette.
3. Archive contenant le fichier de test : détection à l'intérieur de l'archive, copie du conteneur analysé en quarantaine.
4. Fichier de plus de 1 Gio : analyse incomplète, aucune indication favorable. Vérifier également qu'un fichier sain de plus de 100 Mio et de moins de 1 Gio ne déclenche plus la limite précédente.
5. Clé ext4 avec fichier illisible pour UID 10001 et lien symbolique : erreurs détaillées et résultat incomplet.
6. Retirer la clé pendant la lecture, y compris au dernier fichier et lors de la copie : résultat incomplet ou infecté avec erreurs, jamais favorable.
7. Insérer deux clés et une clé avec plusieurs partitions : chaque partition analysée une fois. Retirer puis réinsérer : nouvelle analyse.
8. Brancher une nouvelle clé pendant le scan d'une autre : aucune cible ne reçoit le verdict de l'autre.
9. Recréer le conteneur en cours de scan : historique précédent marqué interrompu, supports présents réanalysés.
10. Vérifier le comptage préalable, puis la progression sur les fichiers traités / total et le débit moyen effectif. Une copie en quarantaine ou une vérification finale ne doit jamais devenir un verdict favorable avant la fin. Tester une clé avec de nombreux petits fichiers et une avec un gros fichier : le pourcentage n'est pas une estimation du temps restant.

## Signatures, pannes et persistance

1. Vérifier dans les logs FreshClam un contrôle réussi et le couple date/version dans `update-status`.
2. Couper Internet : la date ne change pas après une tentative échouée ; après 24 heures, nouvelles analyses bloquées. Rétablir le réseau et redémarrer ClamAV entre deux scans : fonctionnement rétabli.
3. Arrêter ClamAV pendant une analyse : résultat incomplet. Redémarrer puis réinsérer la clé.
4. Remplir un petit volume de test de quarantaine : détection conservée, erreur de copie visible, aucun original supprimé.
5. Arrêter le serveur ou couper la connexion au navigateur : état inconnu affiché, pas de protection verte persistante.
6. Recréer tous les conteneurs sans supprimer leurs volumes : compteurs, historique et copies conservés.
7. Vérifier que les trois conteneurs n'ont ni mode privilégié ni accès au socket Docker. Vérifier les montages USB `ro,nosuid,nodev,noexec` avec `findmnt`.

## Mesures à relever

Chronométrer une clé de nombreux petits fichiers, une clé de gros fichiers et une archive. Relever fichiers/s, débit, mémoire RSS, charge CPU, temps de chargement des signatures et espace de quarantaine. Aucune promesse de gain chiffré Rust/Python n'est faite avant ces mesures : le moteur antivirus et le support USB déterminent une grande partie du temps.
