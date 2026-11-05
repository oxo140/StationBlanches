"use strict";
const $ = id => document.getElementById(id);
const number = value => new Intl.NumberFormat("fr-FR").format(value || 0);
const date = value => value ? new Date(value * 1000).toLocaleString("fr-FR") : "—";
const labels = {running:"En cours",infected:"Menace détectée",incomplete:"Analyse incomplète",interrupted:"Interrompue",no_threat_detected:"Aucune menace détectée"};
let failures = 0;
if (new URLSearchParams(location.search).has("kiosk")) document.body.classList.add("kiosk");
$("fullscreen").addEventListener("click", () => {
  const operation = document.fullscreenElement ? document.exitFullscreen() : document.documentElement.requestFullscreen();
  operation.catch(() => { $("connection").textContent = "Plein écran indisponible"; });
});
$("close-details").addEventListener("click", () => {$("findings").hidden = true;});
async function api(path) {
  const response = await fetch(path, {cache:"no-store", signal:AbortSignal.timeout(8000)});
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
}
function text(id, value) { $(id).textContent = value; }
function blocked(title, detail) {
  document.querySelector(".status-panel").classList.add("blocked");
  text("station-title", title); text("station-detail", detail);
  text("engine-pill", "Protection indisponible"); $("engine-pill").className = "pill";
}
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
    for (const value of [date(scan.started_at), number(scan.files), number(scan.threats), number(scan.errors)]) {
      const cell = document.createElement("td"); cell.textContent=value; row.append(cell);
    }
    const cell = document.createElement("td"); const badge = document.createElement("span"); badge.className=`badge ${Object.hasOwn(labels, scan.verdict) ? scan.verdict : "incomplete"}`; badge.textContent=labels[scan.verdict] || "État inconnu"; cell.append(badge); row.append(cell); $("scans").append(row);
  }
  if (!scans.length) {const row=document.createElement("tr");const cell=document.createElement("td");cell.colSpan=6;cell.textContent="Aucune analyse pour le moment. Insérez une clé USB.";row.append(cell);$("scans").append(row);}
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
async function refresh() {
  try {
    const data = await api("/api/status"); failures=0;
    text("connection", `Actualisé à ${new Date().toLocaleTimeString("fr-FR")}`); $("connection").className="";
    text("version", `Version ${data.version}`);text("checked",date(data.engine.last_update_check));text("engine-version",data.engine.version || "ClamAV en attente");
    const p=data.progress;
    if (data.error) blocked("Intervention nécessaire", data.error);
    else if (!data.engine.ready) blocked("Analyse bloquée", data.engine.message);
    else {
      document.querySelector(".status-panel").classList.remove("blocked");
      text("engine-pill", "Moteur opérationnel");$("engine-pill").className="pill ready";
      text("station-title",p.scan_id ? (p.threats ? "Menace détectée · analyse en cours" : "Analyse du support en cours") : "Prête pour la prochaine clé USB");
      text("station-detail",p.scan_id ? `${p.device} · ${number(p.files)} fichiers · ${number(p.threats)} menace(s) · ${number(p.errors)} erreur(s). Ne retirez pas le support.` : "Insérez un support USB. Chaque partition est analysée automatiquement.");
      if (p.scan_id && (p.threats || p.errors)) document.querySelector(".status-panel").classList.add("blocked");
      if (!p.scan_id && data.present_results.length) {
        const results=data.present_results;
        const threats=results.reduce((sum,item)=>sum+item.threats,0);
        const errors=results.reduce((sum,item)=>sum+item.errors,0);
        text("station-title", threats ? "Menace détectée sur un support" : errors ? "Analyse incomplète" : "Analyse terminée · aucune menace détectée");
        text("station-detail", threats ? `${number(threats)} détection(s). La clé reste potentiellement dangereuse : les originaux sont conservés. Consultez le rapport.` : errors ? "Certains fichiers n’ont pas pu être analysés. Consultez les erreurs dans le rapport." : `${number(results.length)} partition(s) analysée(s). Vous pouvez retirer le support.`);
        if (threats || errors) document.querySelector(".status-panel").classList.add("blocked");
      }
    }
    const k=data.kpis;
    for (const key of ["analyses","files","threats","quarantined","incomplete"]) text(key,number(k[key]));
    text("today",`${number(k.today)} aujourd’hui · UTC`);text("bytes",`${number((k.bytes/1048576).toFixed(1))} Mo analysés`);text("infected",`${number(k.infected_devices)} partition(s) avec détection`);text("duration",`${number(Math.round(k.average_seconds))} s`);
    history(data.scans);chart(data.scans);
  } catch {
    failures++;text("connection", "Connexion perdue");$("connection").className="offline";
    blocked("État de protection inconnu", "Le tableau de bord ne reçoit plus les résultats. Aucun verdict favorable ne peut être confirmé.");
  } finally {setTimeout(refresh, failures ? 5000 : 2000);}
}
refresh();
