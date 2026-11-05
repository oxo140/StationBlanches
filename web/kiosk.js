import {stationView,offlineView} from "/state.js";
const $=id=>document.getElementById(id);
const number=value=>new Intl.NumberFormat("fr-FR").format(value || 0);
let state=offlineView();
let last='';
function render(view) {
  document.body.dataset.state=view.kind;
  $("title").textContent=view.title;
  $("message").textContent=view.message;
  $("state-label").textContent=view.kind==="clean" ? "ANALYSE OK" : view.kind==="infected" ? "SUPPORT À ISOLER" : "CONTRÔLE DES SUPPORTS USB";
  $("counters").hidden=!["scanning","clean","infected","incomplete"].includes(view.kind);
  for (const key of ["files","threats","quarantined"]) $(key).textContent=number(view[key]);
  $("current-file").textContent=view.file || "";
  $("errors").hidden=!view.errors;
  $("errors").textContent=`${number(view.errors)} erreur(s) : consultez le rapport dans la supervision.`;
}
function elapsed() {
  const seconds=state.started_at ? Math.max(0,Math.floor(Date.now()/1000-state.started_at)) : 0;
  $("transfer").textContent=state.kind==="scanning" ? `${number((state.bytes/1048576).toFixed(1))} Mo lus · ${Math.floor(seconds/60)} min ${seconds%60} s` : "";
}
async function refresh() {
  try {
    const response=await fetch("/api/live",{cache:"no-store",signal:AbortSignal.timeout(6000)});
    if (!response.ok) throw new Error("Station inaccessible");
    const data=await response.json();
    state=stationView(data);
    $("connection").textContent="Station connectée";
    $("engine").textContent=data.engine.ready ? "ClamAV · signatures vérifiées" : "ClamAV · protection en préparation";
  } catch {
    state=offlineView();
    $("connection").textContent="Connexion perdue";
    $("engine").textContent="État du moteur inconnu";
  }
  const value=JSON.stringify(state);
  if (value!==last) {render(state);last=value;}
  elapsed();
  setTimeout(refresh,document.hidden ? 5000 : 1000);
}
$("fullscreen").addEventListener("click",()=>{
  const operation=document.fullscreenElement ? document.exitFullscreen() : document.documentElement.requestFullscreen();
  operation.catch(()=>{$("connection").textContent="Utilisez F11 pour le plein écran";});
});
refresh();
