# Architecture v2

```text
USB transmis à Debian
    │ udev → unité systemd (montage ro,nosuid,nodev,noexec)
    ▼
/srv/station-blanche/media (montage partagé)
    │ bind readonly rslave
    ▼
Rust / app ── INSTREAM, réseau scan interne ── ClamAV
    │                                             │
    │ SQLite + copies privées                     └─ FreshClam → Internet (6 h)
    │                                                signatures persistantes
    └─ réseau frontend interne → Caddy
                                  ├─ 127.0.0.1:8080 → Chromium kiosque
                                  └─ HTTPS IP:443 + bcrypt
```

Le montage est la seule petite intégration privilégiée sur l'hôte. L'interface du bureau est un navigateur local ; aucun accès X11/Wayland n'est accordé aux conteneurs. Toute la logique applicative s'exécute dans Docker.

## Décisions

Le démon ClamAV garde la base en mémoire : on évite le coût d'un nouveau processus antivirus pour chaque fichier. Le client Rust utilise une mémoire de travail bornée et calcule le hash au fil de la lecture. L'analyse séquentielle réduit la concurrence sur le support USB et rend le comportement prévisible ; les performances réelles sont à mesurer sur la VM avant d'ajouter du parallélisme.

Le service de surveillance fonctionne hors des threads HTTP. Les lectures SQLite de l'API sont également déportées sur le pool bloquant. Le tableau de bord interroge une API JSON en lecture seule toutes les deux secondes, sans bibliothèques externes ni CDN.

Un montage est identifié par l'ID du montage Linux, son périphérique et sa source. L'identité est vérifiée avant chaque fichier, après la lecture et à la fin. Le chemin cible n'est jamais une variable globale partagée entre analyses. Une clé avec plusieurs partitions génère plusieurs analyses.

Une réponse clamd inconnue, une rupture du protocole, une limite du moteur ou une erreur d'ouverture restent des erreurs. Un résultat favorable exige zéro détection, zéro erreur, un montage encore présent et des signatures vérifiées. Une analyse en cours lors d'un redémarrage est marquée interrompue au démarrage suivant.

Le marqueur des signatures contient `époque_unix version_daily`. Il n'est remplacé qu'après un succès de FreshClam et la lecture de la version du fichier daily. L'application compare cette version à celle retournée par clamd ; un reload non terminé ne permet pas de nouveau scan. Une ancienne vérification n'est pas rafraîchie au redémarrage si le réseau échoue.

## Quarantaine

Après une détection, le même descripteur de fichier est relu. La copie est écrite dans un fichier privé temporaire, hashée, synchronisée puis renommée. Le hash doit être identique à celui du flux analysé. Le nom original ne sert jamais à créer le chemin de quarantaine. L'historique stocke le lien entre analyse, chemin relatif, signature, UUID de copie et SHA-256.

Si l'écriture SQLite échoue après la copie, un échantillon orphelin peut subsister. Il reste privé ; il devra être rapproché lors d'une maintenance. Si la copie échoue, la détection reste une menace et l'erreur apparaît dans le rapport. Le support ne reçoit aucune écriture.

## Sécurité web

Les données d'analyse restent en lecture seule, sans téléchargement d'échantillon. La page `/login` poste les identifiants vers `/auth/login` ; Rust vérifie le hachage bcrypt existant et émet une session aléatoire stockée en mémoire, avec un cookie `Secure`, `HttpOnly`, `SameSite=Strict` et préfixe `__Host-`. Caddy vérifie cette session par `forward_auth` pour toutes les pages et API HTTPS hors connexion et ressources de connexion. Les requêtes de connexion/déconnexion exigent l'origine configurée ; les tentatives sont espacées d'au moins deux secondes. Les sessions expirent après huit heures, au redémarrage ou à la déconnexion. Le mot de passe n'est ni dans le code, ni dans les variables Docker : seul son hachage est monté en lecture seule. Le loopback n'expose librement que le kiosque et son état courant, jamais l'historique.

Le DOM utilise `textContent` pour les noms de fichiers, messages et signatures. CSP, absence de CDN, `nosniff`, `no-store` et interdiction des frames limitent les injections et la mise en cache de données sensibles. Le compte admin unique est une première étape ; comptes nominatifs, OIDC, rôles et journal d'accès administrateur constituent des évolutions distinctes.
