import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.base import MIMEBase
from email import encoders

# Configurer l'e-mail
from_email = "votre_email@gmail.com"
to_email = "adresse@destinataire.com"
subject = "Test avec pièce jointe"
body = "Ceci est un test avec une pièce jointe."

# Créer l'objet MIME
msg = MIMEMultipart()
msg['From'] = from_email
msg['To'] = to_email
msg['Subject'] = subject

# Ajouter le corps du message
msg.attach(MIMEText(body, 'plain'))

# Ajouter la pièce jointe
filename = "NBCLE.txt"  # Nom du fichier à joindre
attachment = open(filename, "rb")

part = MIMEBase('application', 'octet-stream')
part.set_payload(attachment.read())
encoders.encode_base64(part)
part.add_header('Content-Disposition', f"attachment; filename= {filename}")

msg.attach(part)

# Configuration du serveur SMTP
server = smtplib.SMTP('smtp.gmail.com', 587)
server.starttls()
server.login(from_email, 'votre_mot_de_passe_d_application')
text = msg.as_string()

# Envoi de l'e-mail
server.sendmail(from_email, to_email, text)
server.quit()
