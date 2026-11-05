use crate::{
    config::Config,
    db,
    engine::{self, Detection},
    model::{self, Finding, Progress, Scan},
    mounts::{self, Mount},
};
#[cfg(target_os = "linux")]
use anyhow::Context;
use anyhow::{Result, ensure};
use sha2::{Digest, Sha256};
use std::{
    fs::{self, File, OpenOptions},
    io::{Read, Seek, SeekFrom, Write},
    path::Path,
    sync::{
        Arc, RwLock,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};
use uuid::Uuid;
use walkdir::WalkDir;

fn publish(target: &Arc<RwLock<Progress>>, live: &Progress, last: &mut Instant, force: bool) {
    if force || last.elapsed() >= Duration::from_millis(200) {
        *target.write().unwrap() = live.clone();
        *last = Instant::now();
    }
}

fn checkpoint(db: &rusqlite::Connection, scan: &Scan, last: &mut Instant) -> Result<()> {
    if last.elapsed() >= Duration::from_secs(1) {
        db::finish(db, scan)?;
        *last = Instant::now();
    }
    Ok(())
}

#[cfg(target_os = "linux")]
pub fn open_beneath(root: &File, relative: &Path) -> Result<File> {
    use std::{
        ffi::CString,
        os::{
            fd::{AsRawFd, FromRawFd},
            unix::ffi::OsStrExt,
        },
    };
    #[repr(C)]
    struct OpenHow {
        flags: u64,
        mode: u64,
        resolve: u64,
    }
    let name = CString::new(relative.as_os_str().as_bytes())?;
    let how = OpenHow {
        flags: (libc::O_RDONLY | libc::O_CLOEXEC | libc::O_NOFOLLOW | libc::O_NONBLOCK) as u64,
        mode: 0,
        resolve: 0x01 | 0x02 | 0x04 | 0x08, // NO_XDEV | NO_MAGICLINKS | NO_SYMLINKS | BENEATH
    };
    // SAFETY: les deux pointeurs sont valides pendant syscall, avec la taille exacte de open_how.
    let fd = unsafe {
        libc::syscall(
            libc::SYS_openat2,
            root.as_raw_fd(),
            name.as_ptr(),
            &how,
            std::mem::size_of::<OpenHow>(),
        )
    };
    if fd < 0 {
        return Err(std::io::Error::last_os_error()).context("Ouverture confinée au périphérique");
    }
    // SAFETY: syscall a créé un nouveau descripteur dont ce File devient l'unique propriétaire.
    let file = unsafe { File::from_raw_fd(fd as i32) };
    ensure!(file.metadata()?.is_file(), "Fichier spécial non analysable");
    Ok(file)
}

#[cfg(not(target_os = "linux"))]
pub fn open_beneath(_root: &File, _relative: &Path) -> Result<File> {
    anyhow::bail!("Le scan USB nécessite Linux avec openat2 (Debian 13)")
}

pub fn quarantine(dir: &Path, source: &mut File, expected: &str) -> Result<String> {
    let id = Uuid::new_v4().to_string();
    let partial = dir.join(format!("{id}.partial"));
    let dest = dir.join(format!("{id}.bin"));
    let mut copy = || -> Result<()> {
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut output = options.open(&partial)?;
        source.seek(SeekFrom::Start(0))?;
        let mut hash = Sha256::new();
        let mut buffer = [0; 64 * 1024];
        loop {
            let n = source.read(&mut buffer)?;
            if n == 0 {
                break;
            }
            hash.update(&buffer[..n]);
            output.write_all(&buffer[..n])?;
        }
        ensure!(
            format!("{:x}", hash.finalize()) == expected,
            "La copie de quarantaine diffère du fichier analysé"
        );
        output.sync_all()?;
        drop(output);
        fs::rename(&partial, &dest)?;
        #[cfg(unix)]
        File::open(dir)?.sync_all()?;
        Ok(())
    };
    if let Err(error) = copy() {
        let _ = fs::remove_file(partial);
        return Err(error);
    }
    Ok(id)
}

pub fn run(
    config: &Config,
    mount: &Mount,
    engine_version: &str,
    progress: &Arc<RwLock<Progress>>,
    stop: &AtomicBool,
) -> Result<Scan> {
    let db = db::open(&config.database)?;
    let mut scan = Scan {
        id: Uuid::new_v4().to_string(),
        device: mount.label.clone(),
        started_at: model::now(),
        finished_at: None,
        verdict: "running".into(),
        files: 0,
        bytes: 0,
        threats: 0,
        errors: 0,
        engine: engine_version.into(),
        quarantined: 0,
    };
    db::start(&db, &scan)?;
    let mut live = Progress {
        scan_id: Some(scan.id.clone()),
        device: scan.device.clone(),
        started_at: scan.started_at,
        phase: "scanning".into(),
        ..Default::default()
    };
    let mut published = Instant::now();
    let mut saved = Instant::now();
    publish(progress, &live, &mut published, true);
    let record_scan_id = scan.id.clone();
    let record = |path: &str,
                  kind: &str,
                  detail: String,
                  quarantine_id: Option<String>,
                  sha256: Option<String>|
     -> Result<()> {
        db::finding(
            &db,
            &Finding {
                scan_id: record_scan_id.clone(),
                path: path.into(),
                kind: kind.into(),
                detail,
                quarantine_id,
                sha256,
            },
        )
    };
    let result = (|| -> Result<()> {
        let mut guard = mounts::Guard::new(mount, &config.media);
        guard.check(true)?;
        let mut client = engine::Client::new(config)?;
        let root = File::open(&mount.path)?;
        for entry in WalkDir::new(&mount.path).follow_links(false).max_open(16) {
            ensure!(
                !stop.load(Ordering::Relaxed),
                "Analyse arrêtée pour maintenance"
            );
            guard.check(false)?;
            let entry = match entry {
                Ok(entry) => entry,
                Err(error) => {
                    scan.errors += 1;
                    record("", "error", error.to_string(), None, None)?;
                    live.errors = scan.errors;
                    publish(progress, &live, &mut published, true);
                    checkpoint(&db, &scan, &mut saved)?;
                    continue;
                }
            };
            if entry.file_type().is_dir() {
                continue;
            }
            let relative = entry.path().strip_prefix(&mount.path)?;
            let display = relative.to_string_lossy();
            live.current_file = display.to_string();
            live.phase = "scanning".into();
            let file_result = (|| -> Result<()> {
                ensure!(
                    entry.file_type().is_file(),
                    "Lien symbolique ou fichier spécial : analyse incomplète"
                );
                let mut file = open_beneath(&root, relative)?;
                let result = client.scan(&mut file, |bytes| {
                    ensure!(
                        !stop.load(Ordering::Relaxed),
                        "Analyse arrêtée pour maintenance"
                    );
                    guard.check(false)?;
                    live.bytes = scan.bytes + bytes;
                    publish(progress, &live, &mut published, false);
                    checkpoint(&db, &scan, &mut saved)?;
                    Ok(())
                })?;
                guard.check(false)?;
                scan.files += 1;
                scan.bytes += result.bytes;
                if let Detection::Threat(signature) = result.detection {
                    scan.threats += 1;
                    live.files = scan.files;
                    live.threats = scan.threats;
                    live.phase = "quarantine".into();
                    publish(progress, &live, &mut published, true);
                    match quarantine(&config.quarantine, &mut file, &result.sha256) {
                        Ok(id) => {
                            scan.quarantined += 1;
                            record(&display, "threat", signature, Some(id), Some(result.sha256))?
                        }
                        Err(error) => {
                            scan.errors += 1;
                            record(
                                &display,
                                "threat",
                                format!("{signature}; copie de quarantaine échouée : {error:#}"),
                                None,
                                Some(result.sha256),
                            )?;
                        }
                    }
                }
                Ok(())
            })();
            if let Err(error) = file_result {
                scan.errors += 1;
                record(&display, "error", format!("{error:#}"), None, None)?;
            }
            live.files = scan.files;
            live.bytes = scan.bytes;
            live.threats = scan.threats;
            live.errors = scan.errors;
            live.quarantined = scan.quarantined;
            publish(progress, &live, &mut published, false);
            checkpoint(&db, &scan, &mut saved)?;
        }
        live.phase = "finalizing".into();
        publish(progress, &live, &mut published, true);
        guard.check(true)?;
        ensure!(
            engine::health(config).ready,
            "Moteur ou signatures indisponibles en fin de scan"
        );
        Ok(())
    })();
    if let Err(error) = result {
        scan.errors += 1;
        record("", "error", format!("{error:#}"), None, None)?;
    }
    scan.verdict = model::verdict(scan.threats, scan.errors).into();
    scan.finished_at = Some(model::now());
    db::finish(&db, &scan)?;
    tracing::info!(id=%scan.id,verdict=%scan.verdict,files=scan.files,threats=scan.threats,errors=scan.errors,"Analyse terminée");
    Ok(scan)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn quarantine_preserves_source_and_rejects_bad_copies() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("source");
        fs::write(&path, b"test harmless fixture")?;
        let expected = format!("{:x}", Sha256::digest(b"test harmless fixture"));
        let mut file = File::open(&path)?;
        let id = quarantine(temp.path(), &mut file, &expected)?;
        assert_eq!(
            fs::read(temp.path().join(format!("{id}.bin")))?,
            fs::read(&path)?
        );
        assert!(quarantine(temp.path(), &mut file, "wrong").is_err());
        assert!(!fs::read_dir(temp.path())?.any(|e| {
            e.unwrap()
                .path()
                .extension()
                .is_some_and(|x| x == "partial")
        }));
        Ok(())
    }
    #[cfg(target_os = "linux")]
    #[test]
    fn opening_is_confined_and_never_follows_links() -> Result<()> {
        use std::os::unix::fs::symlink;
        let temp = tempfile::tempdir()?;
        fs::write(temp.path().join(".hidden"), b"hidden")?;
        symlink("/etc/passwd", temp.path().join("escape"))?;
        let root = File::open(temp.path())?;
        assert!(open_beneath(&root, Path::new(".hidden")).is_ok());
        assert!(open_beneath(&root, Path::new("escape")).is_err());
        assert!(open_beneath(&root, Path::new("../outside")).is_err());
        Ok(())
    }
}
