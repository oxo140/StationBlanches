"use strict";
import {stationView,offlineView} from "/state.js";
const $ = id => document.getElementById(id);
const number = value => new Intl.NumberFormat("fr-FR").format(value || 0);
const date = value => value ? new Date(value * 1000).toLocaleString("fr-FR") : "—";
const labels = {running:"En cours",infected:"Menace détectée",incomplete:"Analyse incomplète",interrupted:"Interrompue",no_threat_detected:"Aucune menace détectée"};
let failures = 0;
let historyKey="";
$("fullscreen").addEventListener("click", () => {
  const operation = document.fullscreenElement ? document.exitFullscreen() : document.documentElement.requestFullscreen();
  operation.catch(() => { $("connection").textContent = "Plein écran indisponible"; });
});
$("close-details").addEventListener("click", () => {$("findings").hidden = true;});
async function api(path) {
  const response = await fetch(path, {cache:"no-store", signal:AbortSignal.timeout(8000)});
  if(response.redirected && new URL(response.url).pathname==="/login") {location.assign("/login");throw new Error("Session expirée");}
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
}
function text(id, value) { $(id).textContent = value; }
async function detail(id) {
  $("findings").hidden = false;
  $("finding-list").textContent = "Chargement…";
  $("findings").scrollIntoView({behavior:"smooth"});
  try {
    const events = await api(`/api/scans/${encodeURIComponent(id)}/findings`);
    $("finding-list").replaceChildren();
    if (!events.length) $("finding-list").textContent = "Aucune détection ni erreur enregistrée pour cette analyse.";
    for (const event of events) {
      const row = document.createElement("div"); row.className = "finding";
      const path = document.createElement("strong"); path.textContent = event.path || "Périphérique / moteur";
      const message = document.createElement("span"); message.textContent = event.detail;
      row.append(path, message);
      if (event.quarantine_id) {
        const copy = document.createElement("code"); copy.textContent = `Copie isolée : ${event.quarantine_id} · SHA-256 : ${event.sha256}`; row.append(copy);
      }
      $("finding-list").append(row);
    }
  } catch { $("finding-list").textContent = "Impossible de charger les événements. Vérifiez la connexion."; }
}
function history(scans) {
  $("scans").replaceChildren();
  for (const scan of scans) {
    const row = document.createElement("tr");
    const device = document.createElement("td");
    const link = document.createElement("button"); link.type="button"; link.textContent=`USB · ${scan.device}`; link.addEventListener("click", () => detail(scan.id)); device.append(link); row.append(device);
    for (const value of [date(scan.started_at), number(scan.files), number(scan.threats), number(scan.quarantined), number(scan.errors)]) {
      const cell = document.createElement("td"); cell.textContent=value; row.append(cell);
    }
    const cell = document.createElement("td"); const badge = document.createElement("span"); badge.className=`badge ${Object.hasOwn(labels, scan.verdict) ? scan.verdict : "incomplete"}`; badge.textContent=labels[scan.verdict] || "État inconnu"; cell.append(badge); row.append(cell); $("scans").append(row);
  }
  if (!scans.length) {const row=document.createElement("tr");const cell=document.createElement("td");cell.colSpan=7;cell.textContent="Aucune analyse pour le moment. Insérez une clé USB.";row.append(cell);$("scans").append(row);}
}
function chart(scans) {
  $("chart").replaceChildren();
  const days = Array.from({length:7}, (_, index) => {const day=new Date();day.setHours(0,0,0,0);day.setDate(day.getDate()-6+index);return day;});
  const counts = days.map(day => scans.filter(scan => {const value=new Date(scan.started_at*1000);return value.toDateString()===day.toDateString();}).length);
  const max = Math.max(1, ...counts);
  days.forEach((day,index) => {
    const col=document.createElement("div");col.className="chart-column";
    const count=document.createElement("span");count.textContent=number(counts[index]);
    const bar=document.createElement("div");bar.className="chart-bar";bar.style.height=`${Math.max(2,counts[index]/max*95)}px`;
    const label=document.createElement("small");label.textContent=day.toLocaleDateString("fr-FR",{weekday:"short"});
    col.append(count,bar,label);$("chart").append(col);
  });
}
function renderLive(data) {
  const view=data ? stationView(data) : offlineView();
  text("station-title",view.title);
  $("live-progress").hidden=view.kind!=="scanning";
  if(view.phase==="counting" || !view.total_files){
    $("live-bar").removeAttribute("value");
    text("live-label",`${number(view.total_files)} fichiers trouvés · Comptage en cours`);
  }else{
    const percent=Math.min(100,Math.floor(100*(view.processed_files||0)/view.total_files));
    $("live-bar").value=percent;
    text("live-label",`${number(view.processed_files)} / ${number(view.total_files)} fichiers traités · ${percent} %`);
  }
  text("live-speed",view.phase==="counting" ? "Inventaire des répertoires sans lecture du contenu des fichiers" : `${number(((view.read_bytes_per_second||0)/1048576).toFixed(1))} Mio/s · Débit moyen effectif · La progression dépend du nombre de fichiers, pas de leur taille`);
  text("station-detail",view.kind==="scanning" ? `${number(view.files)} fichiers analysés · ${number(view.threats)} menace(s) · ${number(view.quarantined)} copie(s) en quarantaine. ${view.message}` : view.message);
  document.querySelector(".status-panel").classList.toggle("blocked",!["ready","clean","scanning"].includes(view.kind) || view.errors>0 || view.threats>0);
  text("engine-pill",data?.engine?.ready ? "Moteur opérationnel" : "Protection indisponible");
  $("engine-pill").className=data?.engine?.ready ? "pill ready" : "pill";
  text("checked",date(data?.engine?.last_update_check));
  text("engine-version",data?.engine?.version || "ClamAV en attente");
  if (data) text("version",`Version ${data.version}`);
}
async function refreshLive() {
  let active=false;
  try {
    const data=await api("/api/live");failures=0;
    active=Boolean(data.progress.scan_id || data.pending);
    renderLive(data);
    text("connection",`Actualisé à ${new Date().toLocaleTimeString("fr-FR")}`);$("connection").className="";
  } catch {
    failures++;renderLive(null);text("connection","Connexion perdue");$("connection").className="offline";
  } finally {setTimeout(refreshLive,document.hidden || failures ? 5000 : active ? 1000 : 2000);}
}
async function refresh() {
  try {
    const data = await api("/api/status");
    text("history-message","Sélectionnez une analyse pour consulter les détections et les erreurs.");
    const k=data.kpis;
    for (const key of ["analyses","files","threats","quarantined","incomplete"]) text(key,number(k[key]));
    text("today",`${number(k.today)} aujourd’hui · UTC`);text("bytes",`${number((k.bytes/1048576).toFixed(1))} Mo analysés`);text("infected",`${number(k.infected_devices)} partition(s) avec détection`);text("duration",`${number(Math.round(k.average_seconds))} s`);
    const key=JSON.stringify(data.scans);
    if (key!==historyKey) {history(data.scans);chart(data.scans);historyKey=key;}
  } catch {
    text("history-message","Historique temporairement indisponible. Les valeurs affichées peuvent être anciennes.");
  } finally {setTimeout(refresh,document.hidden ? 10000 : 5000);}
}
refreshLive();
refresh();
