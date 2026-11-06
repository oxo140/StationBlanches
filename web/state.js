export function stationView(data) {
  const p=data.progress || {};
  const results=data.present_results || [];
  const summary={files:0,bytes:0,threats:0,errors:0,quarantined:0,unverified_files:0};
  for (const result of results) for (const key of Object.keys(summary)) summary[key]+=Number(result[key] || 0);
  const base={...summary,kind:"ready",title:"Branchez votre clé USB",message:"L’analyse démarre automatiquement. Gardez le support branché jusqu’au résultat.",file:"",phase:"",started_at:0};
  if (data.error) return {...base,kind:"error",title:"Intervention nécessaire",message:data.error};
  if (!data.engine?.ready) return {...base,kind:"blocked",title:"Protection en préparation",message:data.engine?.message || "Connexion au moteur antivirus…"};
  if (p.scan_id) return {...base,...p,kind:"scanning",title:p.phase==="counting" ? "Comptage des fichiers" : p.phase==="quarantine" ? "Copie en quarantaine" : p.phase==="finalizing" ? "Enregistrement du résultat" : "Analyse en cours",message:p.threats ? "Menace détectée. Ne retirez pas le support : l’analyse continue." : "Ne retirez pas votre clé USB pendant l’analyse.",file:p.current_file || "Préparation de l’analyse…"};
  if (data.pending>0) return {...base,kind:"scanning",title:"Préparation de l’analyse",message:`${data.pending} partition(s) en attente. Gardez le support branché.`};
  if (summary.threats>0) return {...base,kind:"infected",title:"Menace détectée",message:summary.quarantined>=summary.threats && !summary.errors ? "Copie isolée en quarantaine. Les originaux restent sur la clé : ne l’utilisez pas." : "Quarantaine incomplète ou erreurs de lecture. Le support ne peut pas être validé."};
  if (results.some(r=>r.verdict==="interrupted")) return {...base,kind:"incomplete",title:"Analyse interrompue",message:"Le parcours du support n’a pas pu être terminé. Consultez les raisons dans la supervision. Le support n’est pas validé."};
  if (summary.errors>0 || results.some(r=>r.verdict!=="no_threat_detected")) return {...base,kind:"incomplete",title:"Analyse terminée avec réserves",message:summary.unverified_files ? `${summary.unverified_files} fichier${summary.unverified_files>1 ? "s" : ""} non vérifié${summary.unverified_files>1 ? "s" : ""}. Consultez les raisons dans la supervision. Le support n’est pas entièrement vérifié.` : "Des incidents empêchent de valider le support. Consultez les raisons dans la supervision."};
  if (results.length) return {...base,kind:"clean",title:"Analyse terminée",message:"Aucune menace détectée. Vous pouvez retirer votre clé USB."};
  return base;
}

export function offlineView() {
  return {kind:"offline",title:"Connexion à la station perdue",message:"Le résultat n’est plus disponible. Attendez le rétablissement de la connexion.",files:0,bytes:0,threats:0,errors:0,quarantined:0,file:"",phase:"",started_at:0};
}
