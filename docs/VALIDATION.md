# Recette Debian 13.7 — à réaliser avant production

La compilation Windows ne remplace pas cette recette Linux. Noter la version Debian, le noyau, les digests des images et la version ClamAV avec les résultats.

## Contrôles automatisés

La CI exécute formatage, Clippy et tests Rust sur Linux, puis construit les images. Les tests couvrent les verdicts, les signatures périmées ou non chargées, les réponses du moteur, l'historique après redémarrage, l'intégrité de quarantaine et le confinement des ouvertures Linux.

## Installation et accès

1. Installer sur une VM Debian 13.7 amd64 avec bureau, 4 vCPU et 8 Go RAM, USB transmis.
2. Lancer l'installateur ; vérifier les trois services avec `docker compose ps`.
3. Vérifier que l'écran indique un blocage jusqu'à la disponibilité des signatures, puis que `/health/ready` retourne 200.
4. Depuis un autre poste : HTTP 8080 et ClamAV 3310 inaccessibles. HTTPS 443 requiert un identifiant. Un mauvais mot de passe doit retourner 401.
5. Installer le certificat public Caddy ; vérifier l'empreinte et l'absence d'erreur TLS sur l'IP.
6. Redémarrer la VM : propagation des montages disponible, services actifs, kiosque lancé après connexion au bureau.

## Supports et verdicts

1. Clé FAT/exFAT avec fichier ordinaire et fichier caché : tous les fichiers comptés, aucune menace détectée.
2. Clé contenant un fichier de test antivirus EICAR obtenu depuis sa source officielle : détection, SHA-256 enregistré, copie privée en quarantaine, original conservé. Ne pas utiliser de malware réel pour la recette.
3. Archive contenant le fichier de test : détection à l'intérieur de l'archive, copie du conteneur analysé en quarantaine.
4. Fichier de plus de 100 Mio : analyse incomplète, aucune indication favorable.
5. Clé ext4 avec fichier illisible pour UID 10001 et lien symbolique : erreurs détaillées et résultat incomplet.
6. Retirer la clé pendant la lecture, y compris au dernier fichier et lors de la copie : résultat incomplet ou infecté avec erreurs, jamais favorable.
7. Insérer deux clés et une clé avec plusieurs partitions : chaque partition analysée une fois. Retirer puis réinsérer : nouvelle analyse.
8. Brancher une nouvelle clé pendant le scan d'une autre : aucune cible ne reçoit le verdict de l'autre.
9. Recréer le conteneur en cours de scan : historique précédent marqué interrompu, supports présents réanalysés.

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
