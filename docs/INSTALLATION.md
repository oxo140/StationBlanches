# Installation détaillée

[Retour au README](../README.md)

La commande recommandée, les prérequis et les composants installés sont présentés dans le [démarrage rapide](../README.md#installation-en-une-ligne).

## Réseau : DHCP, IPv4 manuelle et DNS

**Avant apt et les téléchargements Docker**, l'installateur demande seulement si vous souhaitez passer en IPv4 manuelle. Répondre Non conserve le DHCP actuel sans demander l'interface ni l'adresse IP. Répondre Oui demande l'adresse avec préfixe, la passerelle et les DNS ; l'interface de la route par défaut est détectée automatiquement. Une interface n'est demandée en mode manuel que si aucune route ne permet de la déterminer. Aucun DNS public n'est imposé.

Le diagnostic affiche les adresses et la route IPv4, teste `ping 8.8.8.8` et `ping google.com`, vérifie la résolution des domaines nécessaires à Docker, GitHub, Debian et ClamAV, puis l'accès HTTPS. Un ping filtré ne bloque pas une connexion dont le DNS et HTTPS fonctionnent. Une panne DNS, l'absence de route ou une erreur HTTPS bloque les téléchargements avec une explication.

```bash
cd /opt/station-blanche && sudo bash installation.sh --network-check
```

Configurer ou réparer le réseau indépendamment du reste de l'installation, avec le menu avancé DHCP / IP manuelle / DNS seuls :

```bash
cd /opt/station-blanche && sudo bash installation.sh --network
```

La configuration automatique prend en charge un profil NetworkManager actif (Ethernet ou Wi-Fi), ainsi que les configurations ifupdown filaires simples dans `/etc/network/interfaces` et `/etc/network/interfaces.d/`. Les autres interfaces et la configuration IPv6 sont conservées ; la réactivation d'une connexion peut renouveler ses adresses dynamiques. Les profils ifupdown avec hooks personnalisés, Wi-Fi, ponts ou agrégations sont laissés intacts et doivent être modifiés dans leur gestionnaire Debian.

Avec NetworkManager, un profil est cloné et un checkpoint protège le changement pendant 180 secondes. Avec ifupdown, les fichiers sont sauvegardés sous `/var/lib/station-blanche-network/` et un timer protège la modification. **Pendant l'installation, le changement est confirmé automatiquement uniquement après réussite du diagnostic réseau** ; une panne entraîne un retour arrière. Dans le menu avancé `--network`, la confirmation reste interactive (saisir **Yes** pour NetworkManager). Les hooks DNS prennent en charge les renouvellements dhclient/dhcpcd. Ne pas remplacer manuellement un `/etc/resolv.conf` géré par un résolveur.

**`curl: (6) Could not resolve host: download.docker.com` indique une panne de résolution DNS**, même si une adresse DHCP est présente. Choisir l'option de correction DNS pour essayer les serveurs de votre réseau ou des serveurs publics autorisés (exemple : `1.1.1.1 8.8.8.8`). Une IPv4 fixe seule ne corrige pas le DNS. En cas d'erreur curl 6 pendant le téléchargement de la clé Docker, l'ancienne clé est conservée et l'installation s'arrête sans enregistrer une clé partielle. Si le DNS est tellement défaillant que GitHub lui-même ne peut pas être joint, utiliser d'abord les paramètres réseau du bureau ou `sudo nmtui` si disponible : aucun installateur distant ne peut être téléchargé sans résolution DNS.

Avec DHCP, réserver l'adresse de la station dans le routeur. Si son adresse change, relancer l'installateur pour actualiser l'adresse d'écoute HTTPS et le certificat par IP.

## Installation depuis un clone

Pour consulter les scripts avant exécution :

```bash
sudo apt update
sudo apt install -y git
git clone https://github.com/oxo140/StationBlanches.git
cd StationBlanches
# Tant que la refonte n'est pas fusionnée :
git switch codex/v2-rust-docker
sudo bash installation.sh
```

Le script détecte l'adresse de la VM, installe Docker via son dépôt officiel si absent, prépare systemd/udev et construit les images. Il demande un mot de passe administrateur de 16 caractères minimum et en conserve seulement le hash bcrypt. Les fichiers privés sont dans `secrets/`, exclus de Git.

Diagnostic des dépendances, **sans installer ni modifier quoi que ce soit** :

```bash
sudo bash installation.sh --check
```

Le diagnostic vérifie les paquets et commandes hôte, Chromium, SSH, jq, Docker CLI, Compose, Buildx, l'accès au démon et la configuration lorsqu'elle existe. Code de sortie `0` : dépendances requises disponibles ; `1` : élément manquant, réseau indisponible ou Docker inaccessible. Le bureau local existant est conservé ; Xfce est installé pour la session de maintenance RDP. Si Docker Debian `docker.io` existe déjà, les plugins manquants sont installés depuis Debian ; aucune migration ou suppression automatique d'un moteur existant n'est faite.

Le script n'effectue pas de mise à niveau générale de Debian et n'ajoute pas d'extinction automatique. Une réinstallation conserve les données et le mot de passe existant.

## Choisir le compte bureau

Le compte est détecté depuis l’utilisateur ayant lancé `sudo`, ou depuis l’unique compte utilisateur normal. Lorsque plusieurs comptes existent et que la détection est ambiguë, préciser le compte depuis le clone :

```bash
sudo bash installation.sh --desktop-user UTILISATEUR
```

L’ouverture automatique de session conserve le mot de passe Debian existant. Le mot de passe `admin` créé par l’installateur concerne seulement la supervision web. Les accès SSH et RDP utilisent le compte Debian.

Après installation, redémarrer Debian pour appliquer les réglages du bureau et vérifier le kiosque. La validation réelle des bureaux est détaillée dans [VALIDATION.md](VALIDATION.md).
