# 🛡️ Stations Blanches

Ce projet est conçu pour des Stations Blanches, permettant de scanner les périphériques USB afin de garantir qu'ils sont exempts de logiciels malveillants. Il repose sur l'antivirus **ClamAV** et inclut des visuels intuitifs pour informer l'utilisateur de l'état du scan.

## 📋 Prérequis

- **Debian 11.8** (ou version supérieure recommandée)
- **Environnement GNOME** recommandé
- Connexion Internet pour télécharger les dépendances et les ressources



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

1. Créez un fichier texte sur une clé USB.
2. Insérez-y la chaîne de caractères suivante :

```
X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*
```

Cette chaîne est le fichier de test **EICAR**, reconnu par les antivirus pour tester leur bon fonctionnement. **Veillez à respecter les majuscules, les caractères spéciaux et l'absence d'espaces ou de retours à la ligne superflus.**

---

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

## 📄 Licence

Ce projet est sous licence **MIT**. Consultez le fichier `LICENSE` pour plus de détails.

