const form=document.querySelector("form");
const message=document.getElementById("error");
const password=document.getElementById("password");
const toggle=document.getElementById("toggle-password");
const submit=document.getElementById("submit-login");
const errors={wait:"Veuillez patienter deux secondes avant de réessayer.",invalid:"Identifiant ou mot de passe incorrect."};
function feedback(text,kind="error"){
  message.hidden=false;message.textContent=text;message.dataset.kind=kind;
}
const error=new URLSearchParams(location.search).get("error");
if(error) feedback(errors[error] || "Connexion refusée. Veuillez réessayer depuis cette page.");
toggle.addEventListener("click",()=>{
  const visible=password.type==="password";
  password.type=visible ? "text" : "password";
  toggle.textContent=visible ? "Masquer" : "Afficher";
  toggle.setAttribute("aria-pressed",String(visible));
});
form.addEventListener("submit",async event=>{
  event.preventDefault();
  if(submit.disabled) return;
  submit.disabled=true;
  feedback("Vérification du mot de passe…","pending");
  try{
    const response=await fetch(form.action,{method:"POST",mode:"cors",credentials:"same-origin",body:new URLSearchParams(new FormData(form)),signal:AbortSignal.timeout(20000)});
    if(response.status===403){
      feedback("Connexion refusée : vérifiez que vous utilisez l’adresse HTTPS configurée sur la station. Ouvrez la supervision depuis l’écran USB, puis réessayez.");
      return;
    }
    if(!response.ok) throw new Error("Connexion indisponible");
    const destination=new URL(response.url);
    if(destination.pathname==="/login"){
      const reason=destination.searchParams.get("error");
      feedback(errors[reason] || "Session non établie. Vérifiez que les cookies sont autorisés, puis réessayez.");
      if(reason==="invalid") password.setAttribute("aria-invalid","true");
      return;
    }
    if(destination.origin!==location.origin || destination.pathname!=="/") throw new Error("Réponse inattendue");
    password.removeAttribute("aria-invalid");
    password.value="";
    password.type="password";
    toggle.textContent="Afficher";
    toggle.setAttribute("aria-pressed","false");
    feedback("Mot de passe valide. Ouverture de la supervision…","success");
    setTimeout(()=>location.replace("/"),700);
  }catch{
    feedback("Impossible de vérifier le mot de passe. Vérifiez la connexion à la station et réessayez.");
  }finally{
    if(message.dataset.kind!=="success") submit.disabled=false;
  }
});
