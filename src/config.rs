use anyhow::{Context, Result, ensure};
use std::{env, path::PathBuf};

#[derive(Clone)]
pub struct Config {
    pub listen: String,
    pub media: PathBuf,
    pub database: PathBuf,
    pub quarantine: PathBuf,
    pub update_status: PathBuf,
    pub clamd: String,
    pub max_file_bytes: u64,
    pub max_update_age: i64,
}

impl Config {
    pub fn from_env() -> Result<Self> {
        let number = |key: &str, default: &str| -> Result<u64> {
            env::var(key)
                .unwrap_or_else(|_| default.into())
                .parse()
                .with_context(|| key.to_owned())
        };
        let config = Self {
            listen: env::var("SB_LISTEN").unwrap_or_else(|_| "127.0.0.1:8080".into()),
            media: env::var("SB_MEDIA")
                .unwrap_or_else(|_| "/media".into())
                .into(),
            database: env::var("SB_DATABASE")
                .unwrap_or_else(|_| "/data/history.db".into())
                .into(),
            quarantine: env::var("SB_QUARANTINE")
                .unwrap_or_else(|_| "/quarantine".into())
                .into(),
            update_status: env::var("SB_UPDATE_STATUS")
                .unwrap_or_else(|_| "/signatures/update-status".into())
                .into(),
            clamd: env::var("SB_CLAMD").unwrap_or_else(|_| "clamav:3310".into()),
            max_file_bytes: number("SB_MAX_FILE_BYTES", "104857600")?,
            max_update_age: number("SB_MAX_UPDATE_AGE_SECONDS", "86400")?.try_into()?,
        };
        ensure!(
            config.media.is_absolute()
                && config.database.is_absolute()
                && config.quarantine.is_absolute(),
            "Les chemins applicatifs doivent être absolus"
        );
        ensure!(
            config.max_file_bytes > 0 && config.max_file_bytes <= 104857600,
            "La limite de fichier doit être comprise entre 1 et 104857600 octets"
        );
        ensure!(
            (3600..=86400).contains(&config.max_update_age),
            "La vérification des signatures doit dater de moins de 24 heures"
        );
        Ok(config)
    }
}
