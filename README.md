# 🛡️ Stations Blanches

Ce projet est conçu pour des Stations Blanches, permettant de scanner les périphériques USB afin de garantir qu'ils sont exempts de logiciels malveillants. Il repose sur l'antivirus **ClamAV** et inclut des visuels intuitifs pour informer l'utilisateur de l'état du scan.

## 📋 Prérequis

- **Debian 11.8** (ou version supérieure recommandée)
- **Environnement Xfce** obligatoire
- Connexion Internet pour téléchargement et mise a jour de la base de hash.


---

## 🚀 Installation

Exécutez les commandes suivantes pour installer le projet :

```bash
sudo apt update && sudo apt install curl -y
curl -O https://raw.githubusercontent.com/oxo140/StationBlanches/main/installation.sh
chmod +x installation.sh
sudo ./installation.sh
```

---

## 🧪 Test de la station

Pour vérifier le bon fonctionnement de la station blanche :

1. Dans XFCE, vérifier dans Paramètres → Disques et périphériques amovibles que “Monter les médias amovible” est coché.
2. Lancer un terminal et lancé le script avec la commande python
```bash
python3 script.py gui
```
3. Créez un fichier texte sur une clé USB.
4. Insérez-y une clé usb pour tester


📄 À propos de mb_full.txt

C’est un dump complet de hachages SHA-256 de fichiers malveillants connu, fourni par MalwareBazaar.

Format : un hash SHA-256 par ligne (64 caractères hexadécimaux).

Utilisé comme liste noire : si un fichier USB a un hash qui correspond → infection.

Mise à jour :

Automatique via cron à 10h00 et 18h00

Téléchargé en ZIP, décompressé, puis stocké dans hashdb/mb_full.txt.


## 🖼️ Images

Le projet utilise des visuels pour indiquer l'état du scan USB. Ces images sont disponibles ici :

🔗 [Images du projet](https://github.com/dbarzin/pandora-box/tree/main/images)

### Liste des icônes :

- **`no_usb.png`** : Aucun périphérique USB détecté
- **`scanning.png`** : Analyse en cours
- **`infected.png`** : Fichier infecté détecté
- **`clean.png`** : Clé USB sans menace
- **`perte.png`** : Erreur ou perte de connexion USB

---

## 🔄 Mises à jour automatiques

- Mise à jour de la base de données ClamAV à **21h00** chaque jour (modifiable via `crontab`).
- Extinction automatique du système à **22h00** pour éviter un fonctionnement prolongé inutile (modifiable via `crontab`).

---

## 🛠️ Instructions supplémentaires

- **Désactivez la mise en veille** de votre ordinateur pour assurer un fonctionnement continu.
- **Activez l'ouverture automatique de session** afin que les services se lancent correctement au démarrage.
- ⚠️ **Il est préférable de configurer le démarrage automatique de votre machine via le BIOS pour garantir son allumage sans intervention manuelle.**

---

## 📊 Fichiers de Statistiques et Logs

## Le projet génère deux fichiers pour suivre les activités et les infections des périphériques USB :

- NBCLE.txt : Ce fichier contient le nombre total de clés USB connectées.

- LOG.txt : Ce fichier est utilisé pour enregistrer les événements d'infection détectée par l'antivirus ClamAV.
        Chaque fois qu'une infection est détectée sur une clé USB, une entrée est ajoutée avec un horodatage et la description de l'infection.
