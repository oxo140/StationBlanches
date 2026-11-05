const error=new URLSearchParams(location.search).get("error");
if(error){const message=document.getElementById("error");message.hidden=false;message.textContent=error==="wait" ? "Veuillez patienter deux secondes avant de réessayer." : "Identifiant ou mot de passe incorrect.";}
