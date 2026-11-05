use serde::Serialize;
use std::time::{SystemTime, UNIX_EPOCH};

pub fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}

#[derive(Clone, Debug, Serialize)]
pub struct EngineStatus {
    pub ready: bool,
    pub version: String,
    pub last_update_check: Option<i64>,
    pub message: String,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct Progress {
    pub scan_id: Option<String>,
    pub device: String,
    pub files: u64,
    pub bytes: u64,
    pub threats: u64,
    pub errors: u64,
    pub quarantined: u64,
    pub started_at: i64,
    pub current_file: String,
    pub phase: String,
}

#[derive(Clone, Debug, Serialize)]
pub struct Scan {
    pub id: String,
    pub device: String,
    pub started_at: i64,
    pub finished_at: Option<i64>,
    pub verdict: String,
    pub files: u64,
    pub bytes: u64,
    pub threats: u64,
    pub errors: u64,
    pub engine: String,
    pub quarantined: u64,
}

#[derive(Debug, Serialize)]
pub struct Finding {
    pub scan_id: String,
    pub path: String,
    pub kind: String,
    pub detail: String,
    pub quarantine_id: Option<String>,
    pub sha256: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct Kpis {
    pub analyses: u64,
    pub today: u64,
    pub threats: u64,
    pub infected_devices: u64,
    pub incomplete: u64,
    pub files: u64,
    pub bytes: u64,
    pub quarantined: u64,
    pub average_seconds: f64,
}

pub fn verdict(threats: u64, errors: u64) -> &'static str {
    if threats > 0 {
        "infected"
    } else if errors > 0 {
        "incomplete"
    } else {
        "no_threat_detected"
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn errors_never_produce_a_favorable_verdict() {
        assert_eq!(verdict(0, 1), "incomplete");
        assert_eq!(verdict(2, 1), "infected");
        assert_eq!(verdict(0, 0), "no_threat_detected");
    }
}
