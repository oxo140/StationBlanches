use crate::{
    config::Config,
    model::{EngineStatus, now},
};
use anyhow::{Context, Result, bail, ensure};
use sha2::{Digest, Sha256};
use std::{
    fs::{self, File},
    io::{BufRead, BufReader, Read, Write},
    net::{SocketAddr, TcpStream, ToSocketAddrs},
    time::{Duration, Instant},
};

const RESPONSE_LIMIT: usize = 8192;
const CHUNK_SIZE: usize = 256 * 1024;

fn connect(address: &str) -> Result<TcpStream> {
    let addresses: Vec<_> = address.to_socket_addrs()?.collect();
    // Le nom est interne à Docker, aucun port clamd n'est publié sur l'hôte.
    let addr = addresses.first().context("Adresse clamd introuvable")?;
    connect_address(*addr)
}

fn connect_address(address: SocketAddr) -> Result<TcpStream> {
    let stream = TcpStream::connect_timeout(&address, Duration::from_secs(5))?;
    stream.set_nodelay(true)?;
    stream.set_read_timeout(Some(Duration::from_secs(30)))?;
    stream.set_write_timeout(Some(Duration::from_secs(5)))?;
    Ok(stream)
}

fn response(stream: &mut TcpStream) -> Result<String> {
    let mut result = Vec::new();
    let mut reader = BufReader::with_capacity(1024, stream).take((RESPONSE_LIMIT + 2) as u64);
    reader.read_until(0, &mut result)?;
    ensure!(
        result.last() == Some(&0),
        "Réponse clamd tronquée ou trop longue"
    );
    result.pop();
    ensure!(result.len() <= RESPONSE_LIMIT, "Réponse clamd trop longue");
    Ok(String::from_utf8(result)?)
}

pub fn command(address: &str, command: &[u8]) -> Result<String> {
    let mut stream = connect(address)?;
    stream.write_all(command)?;
    response(&mut stream)
}

pub fn parse_update_status(text: &str, version: &str, age: i64, timestamp: i64) -> Result<i64> {
    let mut fields = text.split_whitespace();
    let checked: i64 = fields
        .next()
        .context("Vérification des signatures absente")?
        .parse()?;
    let database_version = fields.next().context("Version des signatures absente")?;
    ensure!(
        checked <= timestamp + 60 && timestamp - checked <= age,
        "Dernière vérification des signatures trop ancienne"
    );
    ensure!(
        version.split('/').nth(1) == Some(database_version),
        "ClamAV n'a pas encore chargé les dernières signatures vérifiées"
    );
    Ok(checked)
}

pub fn health(config: &Config) -> EngineStatus {
    let mut status = EngineStatus {
        ready: false,
        version: String::new(),
        last_update_check: None,
        message: String::new(),
    };
    let check = || -> Result<(String, i64)> {
        let version = command(&config.clamd, b"zVERSION\0")?;
        ensure!(
            version.starts_with("ClamAV ") && version.split('/').count() >= 3,
            "Version ClamAV invalide"
        );
        let text = fs::read_to_string(&config.update_status)?;
        let checked = parse_update_status(&text, &version, config.max_update_age, now())?;
        Ok((version, checked))
    };
    match check() {
        Ok((version, checked)) => {
            status.ready = true;
            status.version = version;
            status.last_update_check = Some(checked);
            status.message = "Moteur prêt et signatures vérifiées".into();
        }
        Err(error) => status.message = format!("Analyse bloquée : {error:#}"),
    }
    status
}

#[derive(Debug, PartialEq, Eq)]
pub enum Detection {
    Clear,
    Threat(String),
}

pub fn parse_detection(text: &str) -> Result<Detection> {
    if text == "stream: OK" {
        return Ok(Detection::Clear);
    }
    if let Some(signature) = text
        .strip_prefix("stream: ")
        .and_then(|x| x.strip_suffix(" FOUND"))
    {
        ensure!(!signature.is_empty(), "Signature vide");
        ensure!(
            !signature.starts_with("Heuristics.Limits."),
            "Limite interne du moteur atteinte : {signature}"
        );
        return Ok(Detection::Threat(signature.into()));
    }
    bail!("Analyse non terminée : {text}")
}

pub struct FileResult {
    pub detection: Detection,
    pub sha256: String,
    pub bytes: u64,
}

pub struct Client {
    address: SocketAddr,
    max_file_bytes: u64,
    buffer: Vec<u8>,
}

impl Client {
    pub fn new(config: &Config) -> Result<Self> {
        let address = config
            .clamd
            .to_socket_addrs()?
            .next()
            .context("Adresse clamd introuvable")?;
        Ok(Self {
            address,
            max_file_bytes: config.max_file_bytes,
            buffer: vec![0; CHUNK_SIZE],
        })
    }

    pub fn scan(
        &mut self,
        file: &mut File,
        mut progress: impl FnMut(u64) -> Result<()>,
    ) -> Result<FileResult> {
        let before = file.metadata()?;
        ensure!(before.is_file(), "Objet non régulier");
        ensure!(
            before.len() <= self.max_file_bytes,
            "Fichier trop volumineux pour la politique de scan"
        );
        #[cfg(target_os = "linux")]
        {
            use std::os::fd::AsRawFd;
            // SAFETY: descripteur valide ; conseil de lecture uniquement, aucun changement du fichier.
            unsafe {
                libc::posix_fadvise(file.as_raw_fd(), 0, 0, libc::POSIX_FADV_SEQUENTIAL);
            }
        }
        let mut stream = connect_address(self.address)?;
        stream.set_read_timeout(Some(Duration::from_secs(660)))?;
        stream.write_all(b"zINSTREAM\0")?;
        let buffer = &mut self.buffer;
        let mut hash = Sha256::new();
        let mut bytes = 0u64;
        let started = Instant::now();
        let mut published = Instant::now();
        progress(0)?;
        loop {
            ensure!(
                started.elapsed() < Duration::from_secs(900),
                "Durée maximale d'analyse dépassée"
            );
            let count = file.read(buffer)?;
            if count == 0 {
                break;
            }
            bytes += count as u64;
            ensure!(
                bytes <= self.max_file_bytes,
                "Fichier devenu trop volumineux"
            );
            hash.update(&buffer[..count]);
            stream.write_all(&(count as u32).to_be_bytes())?;
            stream.write_all(&buffer[..count])?;
            if published.elapsed() >= Duration::from_millis(250) {
                progress(bytes)?;
                published = Instant::now();
            }
        }
        stream.write_all(&0u32.to_be_bytes())?;
        progress(bytes)?;
        let detection = parse_detection(&response(&mut stream)?)?;
        let after = file.metadata()?;
        ensure!(
            bytes == before.len()
                && before.len() == after.len()
                && before.modified()? == after.modified()?,
            "Fichier modifié pendant le scan"
        );
        Ok(FileResult {
            detection,
            sha256: format!("{:x}", hash.finalize()),
            bytes,
        })
    }
}

#[cfg(test)]
pub fn scan(config: &Config, file: &mut File) -> Result<FileResult> {
    Client::new(config)?.scan(file, |_| Ok(()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{net::TcpListener, path::PathBuf};

    #[test]
    #[ignore = "nécessite le démon ClamAV de tests/clamd-integration.sh"]
    fn real_clamav_detects_a_harmless_custom_signature() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let config = Config {
            listen: String::new(),
            media: PathBuf::new(),
            database: PathBuf::new(),
            quarantine: PathBuf::new(),
            update_status: PathBuf::new(),
            clamd: std::env::var("SB_TEST_CLAMD")?,
            max_file_bytes: 104857600,
            max_update_age: 86400,
        };
        let path = temp.path().join("fixture");
        fs::write(&path, b"ordinary harmless content")?;
        assert_eq!(
            scan(&config, &mut File::open(&path)?)?.detection,
            Detection::Clear
        );
        fs::write(&path, b"ST-BLANCHE-CI-FIXTURE")?;
        let result = scan(&config, &mut File::open(&path)?)?;
        assert!(
            matches!(result.detection,Detection::Threat(ref name) if name.starts_with("StationBlanche.Test"))
        );
        let id = crate::scanner::quarantine(temp.path(), &mut File::open(&path)?, &result.sha256)?;
        assert_eq!(
            fs::read(temp.path().join(format!("{id}.bin")))?,
            fs::read(path)?
        );
        Ok(())
    }

    #[test]
    fn streams_all_bytes_and_hashes_the_exact_scanned_content() -> Result<()> {
        let listener = TcpListener::bind("127.0.0.1:0")?;
        let address = listener.local_addr()?.to_string();
        let content: Vec<u8> = (0..200_000).map(|n| (n % 251) as u8).collect();
        let expected = content.clone();
        let server = std::thread::spawn(move || -> Result<()> {
            let (mut connection, _) = listener.accept()?;
            let mut command = [0; 10];
            connection.read_exact(&mut command)?;
            ensure!(&command == b"zINSTREAM\0", "Commande INSTREAM invalide");
            let mut received = Vec::new();
            loop {
                let mut size = [0; 4];
                connection.read_exact(&mut size)?;
                let size = u32::from_be_bytes(size) as usize;
                if size == 0 {
                    break;
                }
                ensure!(size <= CHUNK_SIZE, "Bloc trop grand");
                let mut chunk = vec![0; size];
                connection.read_exact(&mut chunk)?;
                received.extend(chunk);
            }
            ensure!(received == expected, "Contenu transmis différent");
            for byte in b"stream: OK\0" {
                connection.write_all(&[*byte])?;
            }
            Ok(())
        });
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("input");
        fs::write(&path, &content)?;
        let config = Config {
            listen: String::new(),
            media: PathBuf::new(),
            database: PathBuf::new(),
            quarantine: PathBuf::new(),
            update_status: PathBuf::new(),
            clamd: address,
            max_file_bytes: 104857600,
            max_update_age: 86400,
        };
        let mut updates = Vec::new();
        let result = Client::new(&config)?.scan(&mut File::open(path)?, |bytes| {
            updates.push(bytes);
            Ok(())
        })?;
        assert_eq!(updates.first(), Some(&0));
        assert_eq!(updates.last(), Some(&(content.len() as u64)));
        assert!(updates.windows(2).all(|pair| pair[0] <= pair[1]));
        assert_eq!(result.bytes, content.len() as u64);
        assert_eq!(result.sha256, format!("{:x}", Sha256::digest(&content)));
        assert_eq!(result.detection, Detection::Clear);
        server.join().unwrap()?;
        Ok(())
    }

    #[test]
    fn incomplete_protocol_response_is_an_error() -> Result<()> {
        let listener = TcpListener::bind("127.0.0.1:0")?;
        let address = listener.local_addr()?.to_string();
        let server = std::thread::spawn(move || -> Result<()> {
            let (mut connection, _) = listener.accept()?;
            let mut command = [0; 9];
            connection.read_exact(&mut command)?;
            connection.write_all(b"ClamAV 1.4/42/date")?;
            Ok(())
        });
        assert!(command(&address, b"zVERSION\0").is_err());
        server.join().unwrap()?;
        Ok(())
    }
    #[test]
    fn unknown_truncated_and_limit_responses_are_never_clean() {
        assert_eq!(parse_detection("stream: OK").unwrap(), Detection::Clear);
        assert!(matches!(
            parse_detection("stream: Win.Test FOUND").unwrap(),
            Detection::Threat(_)
        ));
        for response in [
            "",
            "stream: OK ERROR",
            "stream: read error ERROR",
            "stream: Heuristics.Limits.Exceeded.MaxFileSize FOUND",
        ] {
            assert!(parse_detection(response).is_err());
        }
    }
    #[test]
    fn stale_future_or_unloaded_signatures_are_rejected() {
        assert_eq!(
            parse_update_status("1000 42", "ClamAV 1.4/42/date", 86400, 1010).unwrap(),
            1000
        );
        assert!(parse_update_status("1000 42", "ClamAV 1.4/41/date", 86400, 1010).is_err());
        assert!(parse_update_status("1000 42", "ClamAV 1.4/42/date", 86400, 90000).is_err());
        assert!(parse_update_status("90000 42", "ClamAV 1.4/42/date", 86400, 1000).is_err());
    }
}
