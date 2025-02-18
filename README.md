🛡️ Stations Blanches - Sécurité et Supervision

Bienvenue dans le dépôt du projet Stations Blanches.

Ce projet est conçu pour des Stations blanches.
Ce projet nécessite l'utilisation d'Ubuntu Live Server 22 pour garantir une installation stable et performante.
Ce projet est basé sur l'installation de l'outil pandora box disponible ici 
https://github.com/dbarzin/pandora-box/blob/main/INSTALL.md
Cependant, certains problèmes ont été rencontrés. Dans ce cas, veuillez exécuter les commandes de patch suivantes :
```
curl -O https://github.com/oxo140/StationBlanches/blob/main/setup_pandora.sh
chmod +x setup_pandora.sh
sudo ./setup_pandora.sh
```
Pour tester la station :

Branchez une clé USB contenant un fichier texte qui intègre la chaîne de caractères suivante ou télécharger le sur dépot :
```
X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*
```
Cette chaîne est le fichier de test EICAR, reconnu par les antivirus pour vérifier leur fonctionnement.
Assurez-vous que la chaîne soit inscrite exactement comme indiqué, sans espaces ni retours à la ligne supplémentaires.
