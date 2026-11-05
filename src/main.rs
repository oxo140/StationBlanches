mod config;
mod db;
mod engine;
mod model;
mod mounts;
mod scanner;

use anyhow::{Context, Result};
use axum::{
    Json, Router,
    extract::{Path, State},
    http::{StatusCode, header},
    response::{Html, IntoResponse},
    routing::get,
};
use config::Config;
use model::{EngineStatus, Progress};
use std::{
    collections::HashMap,
    fs,
    sync::{
        Arc, RwLock,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};

#[derive(Clone)]
struct App {
    config: Config,
    engine: Arc<RwLock<EngineStatus>>,
    progress: Arc<RwLock<Progress>>,
    error: Arc<RwLock<Option<String>>>,
    present_results: Arc<RwLock<Vec<model::Scan>>>,
}

fn worker(app: App, stop: Arc<AtomicBool>) {
    let mut completed = HashMap::new();
    while !stop.load(Ordering::Relaxed) {
        *app.engine.write().unwrap() = engine::health(&app.config);
        let work = (|| -> Result<()> {
            let mounts = mounts::list(&app.config.media)?;
            completed.retain(|key, _| mounts.iter().any(|m| &m.key == key));
            *app.present_results.write().unwrap() = completed.values().cloned().collect();
            if !app.engine.read().unwrap().ready {
                return Ok(());
            }
            for mount in mounts {
                if stop.load(Ordering::Relaxed) {
                    break;
                }
                if completed.contains_key(&mount.key) {
                    continue;
                }
                let engine = engine::health(&app.config);
                *app.engine.write().unwrap() = engine.clone();
                if !engine.ready {
                    break;
                }
                let result =
                    scanner::run(&app.config, &mount, &engine.version, &app.progress, &stop)?;
                completed.insert(mount.key, result);
                *app.present_results.write().unwrap() = completed.values().cloned().collect();
            }
            Ok(())
        })();
        match work {
            Ok(()) => *app.error.write().unwrap() = None,
            Err(error) => {
                tracing::error!(error=%error,"Surveillance interrompue");
                *app.error.write().unwrap() = Some(format!("{error:#}"));
                *app.progress.write().unwrap() = Progress::default();
                // Le stockage doit rester fiable avant de reprendre une analyse.
                if let Ok(db) = db::open(&app.config.database) {
                    let _ = db::recover(&db);
                }
            }
        }
        for _ in 0..20 {
            if stop.load(Ordering::Relaxed) {
                return;
            }
            std::thread::sleep(Duration::from_millis(100));
        }
    }
}

async fn snapshot(State(app): State<App>) -> Result<Json<serde_json::Value>, StatusCode> {
    tokio::task::spawn_blocking(move || {
        let db=db::open(&app.config.database).map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?;
        let kpis=db::kpis(&db).map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?;
        let scans=db::scans(&db).map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?;
        Ok(Json(serde_json::json!({"version":env!("CARGO_PKG_VERSION"),"engine":app.engine.read().unwrap().clone(),"progress":app.progress.read().unwrap().clone(),"present_results":app.present_results.read().unwrap().clone(),"error":app.error.read().unwrap().clone(),"kpis":kpis,"scans":scans})))
    }).await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
}

async fn findings(
    State(app): State<App>,
    Path(id): Path<String>,
) -> Result<Json<Vec<model::Finding>>, StatusCode> {
    if uuid::Uuid::parse_str(&id).is_err() {
        return Err(StatusCode::BAD_REQUEST);
    }
    tokio::task::spawn_blocking(move || {
        let db = db::open(&app.config.database).map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?;
        db::findings(&db, &id)
            .map(Json)
            .map_err(|_| StatusCode::SERVICE_UNAVAILABLE)
    })
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
}

async fn ready(State(app): State<App>) -> impl IntoResponse {
    if app.engine.read().unwrap().ready && app.error.read().unwrap().is_none() {
        StatusCode::OK
    } else {
        StatusCode::SERVICE_UNAVAILABLE
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "station_blanche=info".into()),
        )
        .init();
    let config = Config::from_env()?;
    if let Some(parent) = config.database.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::create_dir_all(&config.quarantine)?;
    let db = db::open(&config.database)?;
    db::recover(&db)?;
    drop(db);
    let app = App {
        config: config.clone(),
        engine: Arc::new(RwLock::new(EngineStatus {
            ready: false,
            version: String::new(),
            last_update_check: None,
            message: "Initialisation du moteur".into(),
        })),
        progress: Arc::new(RwLock::new(Progress::default())),
        error: Arc::new(RwLock::new(None)),
        present_results: Arc::new(RwLock::new(Vec::new())),
    };
    let stop = Arc::new(AtomicBool::new(false));
    let worker_app = app.clone();
    let worker_stop = stop.clone();
    // La boucle de scan ne bloque jamais le serveur HTTP.
    let worker = tokio::task::spawn_blocking(move || worker(worker_app, worker_stop));
    let routes=Router::new()
        .route("/",get(||async {Html(include_str!("../web/index.html"))}))
        .route("/app.js",get(||async {([(header::CONTENT_TYPE,"text/javascript; charset=utf-8")],include_str!("../web/app.js"))}))
        .route("/style.css",get(||async {([(header::CONTENT_TYPE,"text/css; charset=utf-8")],include_str!("../web/style.css"))}))
        .route("/api/status",get(snapshot))
        .route("/api/scans/{id}/findings",get(findings))
        .route("/health/live",get(||async {StatusCode::OK}))
        .route("/health/ready",get(ready))
        .layer(axum::middleware::map_response(|mut response:axum::response::Response|async move {
            let headers=response.headers_mut();
            headers.insert("content-security-policy","default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'none'".parse().unwrap());
            headers.insert("x-content-type-options","nosniff".parse().unwrap());
            headers.insert("referrer-policy","no-referrer".parse().unwrap());
            headers.insert(header::CACHE_CONTROL,"no-store".parse().unwrap());
            response
        }))
        .with_state(app);
    let listener = tokio::net::TcpListener::bind(&config.listen)
        .await
        .context("Écoute HTTP")?;
    tracing::info!(listen=%config.listen,"Station Blanche v2 démarrée");
    axum::serve(listener, routes)
        .with_graceful_shutdown(async move {
            #[cfg(unix)]
            {
                let mut term =
                    tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
                        .expect("SIGTERM");
                tokio::select! { _=tokio::signal::ctrl_c()=>{}, _=term.recv()=>{} }
            }
            #[cfg(not(unix))]
            {
                let _ = tokio::signal::ctrl_c().await;
            }
            stop.store(true, Ordering::Relaxed);
        })
        .await?;
    worker.await?;
    Ok(())
}
