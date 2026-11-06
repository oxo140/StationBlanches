use crate::model::{Finding, Kpis, Scan};
use anyhow::Result;
use rusqlite::{Connection, OpenFlags, params};
use std::{path::Path, time::Duration};

pub fn open(path: &Path) -> Result<Connection> {
    let db = Connection::open(path)?;
    db.busy_timeout(Duration::from_secs(5))?;
    db.execute_batch(
        "PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;
        CREATE TABLE IF NOT EXISTS scans (
          id TEXT PRIMARY KEY, device TEXT NOT NULL, started_at INTEGER NOT NULL,
          finished_at INTEGER, verdict TEXT NOT NULL, files INTEGER NOT NULL DEFAULT 0,
          bytes INTEGER NOT NULL DEFAULT 0, threats INTEGER NOT NULL DEFAULT 0,
          errors INTEGER NOT NULL DEFAULT 0, engine TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS findings (
          id INTEGER PRIMARY KEY, scan_id TEXT NOT NULL REFERENCES scans(id),
          path TEXT NOT NULL, kind TEXT NOT NULL, detail TEXT NOT NULL,
          quarantine_id TEXT, sha256 TEXT);
        CREATE INDEX IF NOT EXISTS findings_scan ON findings(scan_id);
        CREATE INDEX IF NOT EXISTS scans_time ON scans(started_at);",
    )?;
    let has_quarantine: bool = db.query_row(
        "SELECT EXISTS(SELECT 1 FROM pragma_table_info('scans') WHERE name='quarantined')",
        [],
        |row| row.get(0),
    )?;
    if !has_quarantine {
        db.execute_batch("BEGIN IMMEDIATE;
            ALTER TABLE scans ADD COLUMN quarantined INTEGER NOT NULL DEFAULT 0;
            UPDATE scans SET quarantined=(SELECT COUNT(*) FROM findings WHERE findings.scan_id=scans.id AND quarantine_id IS NOT NULL);
            COMMIT;")?;
    }
    Ok(db)
}

// Les consultations web ne recréent pas le schéma et ne prennent aucun verrou d'écriture.
pub fn read(path: &Path) -> Result<Connection> {
    let db = Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_ONLY)?;
    db.busy_timeout(Duration::from_secs(5))?;
    Ok(db)
}

pub fn recover(db: &Connection) -> Result<()> {
    db.execute("UPDATE scans SET verdict='interrupted', finished_at=unixepoch(), errors=errors+1 WHERE verdict='running'", [])?;
    Ok(())
}

pub fn start(db: &Connection, scan: &Scan) -> Result<()> {
    db.execute(
        "INSERT INTO scans(id,device,started_at,verdict,engine) VALUES (?1,?2,?3,'running',?4)",
        params![scan.id, scan.device, scan.started_at, scan.engine],
    )?;
    Ok(())
}

pub fn finish(db: &Connection, scan: &Scan) -> Result<()> {
    db.execute("UPDATE scans SET finished_at=?2,verdict=?3,files=?4,bytes=?5,threats=?6,errors=?7,quarantined=?8 WHERE id=?1",
        params![scan.id,scan.finished_at,scan.verdict,scan.files,scan.bytes,scan.threats,scan.errors,scan.quarantined])?;
    Ok(())
}

pub fn finding(db: &Connection, f: &Finding) -> Result<()> {
    db.execute("INSERT INTO findings(scan_id,path,kind,detail,quarantine_id,sha256) VALUES (?1,?2,?3,?4,?5,?6)",
        params![f.scan_id,f.path,f.kind,f.detail,f.quarantine_id,f.sha256])?;
    Ok(())
}

pub fn scans(db: &Connection) -> Result<Vec<Scan>> {
    let mut stmt = db.prepare("SELECT id,device,started_at,finished_at,verdict,files,bytes,threats,errors,engine,quarantined,
        (SELECT COUNT(DISTINCT path) FROM findings WHERE scan_id=scans.id AND kind='error' AND path!='')
        FROM scans ORDER BY started_at DESC,rowid DESC LIMIT 100")?;
    let rows = stmt.query_map([], |r| {
        Ok(Scan {
            id: r.get(0)?,
            device: r.get(1)?,
            started_at: r.get(2)?,
            finished_at: r.get(3)?,
            verdict: r.get(4)?,
            files: r.get(5)?,
            bytes: r.get(6)?,
            threats: r.get(7)?,
            errors: r.get(8)?,
            engine: r.get(9)?,
            quarantined: r.get(10)?,
            unverified_files: r.get(11)?,
        })
    })?;
    Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
}

pub fn findings(db: &Connection, scan_id: &str) -> Result<Vec<Finding>> {
    let mut stmt = db.prepare("SELECT scan_id,path,kind,detail,quarantine_id,sha256 FROM findings WHERE scan_id=?1 ORDER BY id LIMIT 500")?;
    let rows = stmt.query_map([scan_id], |r| {
        Ok(Finding {
            scan_id: r.get(0)?,
            path: r.get(1)?,
            kind: r.get(2)?,
            detail: r.get(3)?,
            quarantine_id: r.get(4)?,
            sha256: r.get(5)?,
        })
    })?;
    Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
}

pub fn kpis(db: &Connection) -> Result<Kpis> {
    Ok(db.query_row(
        "SELECT COUNT(*),
        COALESCE(SUM(started_at >= unixepoch('now','start of day')),0),
        COALESCE(SUM(threats),0), COALESCE(SUM(threats>0),0),
        COALESCE(SUM(verdict IN ('incomplete','interrupted')),0),
        COALESCE(SUM(files),0),COALESCE(SUM(bytes),0),
        (SELECT COUNT(*) FROM findings WHERE quarantine_id IS NOT NULL),
        COALESCE(AVG(CASE WHEN finished_at IS NOT NULL THEN finished_at-started_at END),0)
        FROM scans",
        [],
        |r| {
            Ok(Kpis {
                analyses: r.get(0)?,
                today: r.get(1)?,
                threats: r.get(2)?,
                infected_devices: r.get(3)?,
                incomplete: r.get(4)?,
                files: r.get(5)?,
                bytes: r.get(6)?,
                quarantined: r.get(7)?,
                average_seconds: r.get(8)?,
            })
        },
    )?)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn migration_keeps_existing_history_and_quarantine_counts() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("old.db");
        let old = Connection::open(&path)?;
        old.execute_batch("CREATE TABLE scans(id TEXT PRIMARY KEY,device TEXT,started_at INTEGER,finished_at INTEGER,verdict TEXT,files INTEGER,bytes INTEGER,threats INTEGER,errors INTEGER,engine TEXT);
            CREATE TABLE findings(id INTEGER PRIMARY KEY,scan_id TEXT,path TEXT,kind TEXT,detail TEXT,quarantine_id TEXT,sha256 TEXT);
            INSERT INTO scans VALUES('legacy','sdb1',1,2,'infected',7,1024,1,0,'old-engine');
            INSERT INTO findings VALUES(1,'legacy','test.txt','threat','EICAR','private-copy','sha');")?;
        drop(old);
        let db = open(&path)?;
        assert_eq!(scans(&db)?[0].quarantined, 1);
        drop(db);
        let db = open(&path)?;
        assert_eq!(scans(&db)?[0].files, 7);
        assert_eq!(kpis(&db)?.quarantined, 1);
        db.execute("INSERT INTO findings(scan_id,path,kind,detail) VALUES('legacy','locked.zip','error','encrypted'),('legacy','locked.zip','error','retry'),('legacy','','error','engine issue')", [])?;
        assert_eq!(scans(&db)?[0].unverified_files, 1);
        let reader = read(&path)?;
        assert_eq!(findings(&reader, "legacy")?.len(), 4);
        assert!(reader.execute("DELETE FROM scans", []).is_err());
        Ok(())
    }
    #[test]
    fn interrupted_scans_survive_recreation_without_becoming_clean() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("history.db");
        let db = open(&path)?;
        start(
            &db,
            &Scan {
                id: "one".into(),
                device: "usb".into(),
                started_at: 0,
                finished_at: None,
                verdict: "running".into(),
                files: 0,
                bytes: 0,
                threats: 0,
                errors: 0,
                engine: "test".into(),
                quarantined: 0,
                unverified_files: 0,
            },
        )?;
        drop(db);
        let db = open(&path)?;
        recover(&db)?;
        assert_eq!(scans(&db)?[0].verdict, "interrupted");
        assert_eq!(kpis(&db)?.incomplete, 1);
        Ok(())
    }
}
