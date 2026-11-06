use anyhow::Result;
use rusqlite::Connection;

// Champ compatible Excel/LibreOffice : guillemets CSV et neutralisation des formules.
fn field(value: &str) -> String {
    let dangerous = value.trim_start().starts_with(['=', '+', '-', '@'])
        || value.starts_with(['\t', '\r', '\n']);
    format!(
        "\"{}{}\"",
        if dangerous { "'" } else { "" },
        value.replace('"', "\"\"")
    )
}

pub fn write(db: &Connection, mut emit: impl FnMut(String) -> Result<()>) -> Result<()> {
    let transaction = db.unchecked_transaction()?;
    let db = &transaction;
    let mut stmt = db.prepare("SELECT s.id,s.device,datetime(s.started_at,'unixepoch'),COALESCE(datetime(s.finished_at,'unixepoch'),''),s.verdict,s.files,s.bytes,s.threats,s.errors,s.quarantined,s.engine,
        (SELECT COUNT(DISTINCT path) FROM findings WHERE scan_id=s.id AND kind='error' AND path!='')
        FROM scans s ORDER BY s.started_at DESC,s.rowid DESC")?;
    let mut details = db.prepare("SELECT CASE WHEN path='' THEN 'Station / moteur' ELSE path END || ' : ' || kind || ' : ' || detail ||
            CASE WHEN quarantine_id IS NOT NULL THEN ' | quarantaine=' || quarantine_id ELSE '' END ||
            CASE WHEN sha256 IS NOT NULL THEN ' | SHA256=' || sha256 ELSE '' END
            FROM findings WHERE scan_id=?1 ORDER BY id")?;
    emit("\u{feff}Identifiant;Support;Debut_UTC;Fin_UTC;Verdict_technique;Fichiers_analyses;Octets_analyses;Menaces;Erreurs;Copies_quarantaine;Moteur;Fichiers_non_verifies;Resultat;Details_et_raisons\r\n".into())?;
    let mut rows = stmt.query([])?;
    while let Some(row) = rows.next()? {
        let mut values = (0..12)
            .map(|index| {
                use rusqlite::types::ValueRef;
                let value = match row.get_ref(index)? {
                    ValueRef::Text(text) => String::from_utf8_lossy(text).into_owned(),
                    ValueRef::Integer(number) => number.to_string(),
                    _ => String::new(),
                };
                Ok(field(&value))
            })
            .collect::<rusqlite::Result<Vec<_>>>()?;
        let count: u64 = row.get(11)?;
        let verdict: String = row.get(4)?;
        let label = match verdict.as_str() {
            "incomplete" if count > 0 => {
                format!("Analyse terminée avec réserves : {count} fichier(s) non vérifié(s)")
            }
            "incomplete" => "Analyse terminée avec réserves".into(),
            "interrupted" => "Analyse interrompue".into(),
            "infected" => "Menace détectée".into(),
            "no_threat_detected" => "Aucune menace détectée".into(),
            "running" => "En cours".into(),
            _ => "État inconnu".into(),
        };
        values.push(field(&label));
        emit(values.join(";") + ";\"")?;
        let id: String = row.get(0)?;
        let mut findings = details.query([id])?;
        let mut first = true;
        while let Some(finding) = findings.next()? {
            if first {
                emit("Événements :".into())?;
                first = false;
            }
            let description: String = finding.get(0)?;
            emit("\n".to_owned() + &description.replace('"', "\"\""))?;
        }
        emit("\"\r\n".into())?;
    }
    drop(rows);
    drop(stmt);
    drop(details);
    transaction.commit()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn escapes_formulas_quotes_and_multiline_values() {
        assert_eq!(field("  =1+1"), "\"'  =1+1\"");
        assert_eq!(
            field("file;\"name\"\nreason"),
            "\"file;\"\"name\"\"\nreason\""
        );
    }
    #[test]
    fn exports_all_scans_and_all_findings_without_display_limits() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let db = crate::db::open(&temp.path().join("export.db"))?;
        for index in 0..105 {
            db.execute("INSERT INTO scans(id,device,started_at,verdict,engine) VALUES(?1,'usb',1,'incomplete','test')", [index.to_string()])?;
        }
        for index in 0..505 {
            db.execute(
                "INSERT INTO findings(scan_id,path,kind,detail) VALUES('0',?1,'error',?2)",
                rusqlite::params![format!("file{index}"), format!("reason{index}")],
            )?;
        }
        let mut output = String::new();
        write(&db, |row| {
            output.push_str(&row);
            Ok(())
        })?;
        assert_eq!(output.matches("\r\n").count(), 106);
        assert!(output.starts_with('\u{feff}'));
        assert!(output.contains("file504 : error : reason504"));
        Ok(())
    }
}
