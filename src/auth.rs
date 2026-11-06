use axum::{
    extract::{Form, State},
    http::{HeaderMap, StatusCode, header},
    response::{IntoResponse, Redirect, Response},
};
use serde::Deserialize;
use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

#[derive(Clone)]
pub struct Auth {
    hash: Arc<String>,
    origin: Arc<String>,
    inner: Arc<Mutex<Inner>>,
}
struct Inner {
    sessions: HashMap<String, Instant>,
    next_attempt: Instant,
}
impl Auth {
    pub fn new() -> anyhow::Result<Self> {
        let hash = match std::env::var("SB_ADMIN_HASH_FILE") {
            Ok(path) => std::fs::read_to_string(path)?.trim().to_owned(),
            Err(_) => String::new(),
        };
        if !hash.is_empty() {
            anyhow::ensure!(hash.starts_with("$2"), "Hachage administrateur invalide");
        }
        Ok(Self {
            hash: Arc::new(hash),
            origin: Arc::new(std::env::var("SB_ORIGIN").unwrap_or_default()),
            inner: Arc::new(Mutex::new(Inner {
                sessions: HashMap::new(),
                next_attempt: Instant::now(),
            })),
        })
    }
    fn same_origin(&self, headers: &HeaderMap) -> bool {
        !self.origin.is_empty()
            && headers.get(header::ORIGIN).and_then(|v| v.to_str().ok())
                == Some(self.origin.as_str())
    }
    fn token(headers: &HeaderMap) -> Option<&str> {
        headers
            .get(header::COOKIE)?
            .to_str()
            .ok()?
            .split(';')
            .find_map(|part| part.trim().strip_prefix("__Host-sb_session="))
    }
    fn authorized(&self, headers: &HeaderMap) -> bool {
        let mut inner = self.inner.lock().unwrap();
        inner
            .sessions
            .retain(|_, expires| *expires > Instant::now());
        Self::token(headers).is_some_and(|token| inner.sessions.contains_key(token))
    }
}
#[derive(Deserialize)]
pub struct Credentials {
    username: String,
    password: String,
}

pub async fn login(
    State(auth): State<Auth>,
    headers: HeaderMap,
    Form(credentials): Form<Credentials>,
) -> Response {
    if !auth.same_origin(&headers) {
        return StatusCode::FORBIDDEN.into_response();
    }
    {
        let mut inner = auth.inner.lock().unwrap();
        if Instant::now() < inner.next_attempt {
            return Redirect::to("/login?error=wait").into_response();
        }
        inner.next_attempt = Instant::now() + Duration::from_secs(2);
    }
    let hash = auth.hash.clone();
    let valid = tokio::task::spawn_blocking(move || {
        credentials.username == "admin"
            && !hash.is_empty()
            && credentials.password.len() <= 1024
            && bcrypt::verify(&credentials.password, hash.as_str()).unwrap_or(false)
    })
    .await
    .unwrap_or(false);
    if !valid {
        return Redirect::to("/login?error=invalid").into_response();
    }
    let token = uuid::Uuid::new_v4().to_string();
    let mut inner = auth.inner.lock().unwrap();
    inner
        .sessions
        .retain(|_, expires| *expires > Instant::now());
    if inner.sessions.len() >= 32 {
        inner.sessions.clear();
    }
    inner.sessions.insert(
        token.clone(),
        Instant::now() + Duration::from_secs(8 * 3600),
    );
    ([(header::SET_COOKIE, format!("__Host-sb_session={token}; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=28800"))], Redirect::to("/")).into_response()
}
pub async fn check(State(auth): State<Auth>, headers: HeaderMap) -> StatusCode {
    if auth.authorized(&headers) {
        StatusCode::OK
    } else {
        StatusCode::UNAUTHORIZED
    }
}
pub async fn logout(State(auth): State<Auth>, headers: HeaderMap) -> Response {
    if !auth.same_origin(&headers) {
        return StatusCode::FORBIDDEN.into_response();
    }
    if let Some(token) = Auth::token(&headers) {
        auth.inner.lock().unwrap().sessions.remove(token);
    }
    (
        [(
            header::SET_COOKIE,
            "__Host-sb_session=; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=0",
        )],
        Redirect::to("/login"),
    )
        .into_response()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn login_reuses_bcrypt_and_logout_revokes_session() {
        let auth = Auth {
            hash: Arc::new(bcrypt::hash("test-password", 4).unwrap()),
            origin: Arc::new("https://192.0.2.1".into()),
            inner: Arc::new(Mutex::new(Inner {
                sessions: HashMap::new(),
                next_attempt: Instant::now(),
            })),
        };
        let mut headers = HeaderMap::new();
        headers.insert(header::ORIGIN, "https://192.0.2.1".parse().unwrap());
        let wrong = login(
            State(auth.clone()),
            headers.clone(),
            Form(Credentials {
                username: "admin".into(),
                password: "wrong".into(),
            }),
        )
        .await;
        assert_eq!(wrong.headers()[header::LOCATION], "/login?error=invalid");
        let limited = login(
            State(auth.clone()),
            headers.clone(),
            Form(Credentials {
                username: "admin".into(),
                password: "test-password".into(),
            }),
        )
        .await;
        assert_eq!(limited.headers()[header::LOCATION], "/login?error=wait");
        auth.inner.lock().unwrap().next_attempt = Instant::now();
        let response = login(
            State(auth.clone()),
            headers.clone(),
            Form(Credentials {
                username: "admin".into(),
                password: "test-password".into(),
            }),
        )
        .await;
        assert_eq!(response.status(), StatusCode::SEE_OTHER);
        let cookie = response.headers()[header::SET_COOKIE].to_str().unwrap();
        assert!(cookie.contains("Secure; HttpOnly; SameSite=Strict"));
        headers.insert(
            header::COOKIE,
            cookie.split(';').next().unwrap().parse().unwrap(),
        );
        assert!(auth.authorized(&headers));
        assert_eq!(
            logout(State(auth.clone()), headers.clone()).await.status(),
            StatusCode::SEE_OTHER
        );
        assert!(!auth.authorized(&headers));
    }
    #[test]
    fn sessions_expire_and_origin_is_required() {
        let auth = Auth {
            hash: Arc::new(String::new()),
            origin: Arc::new("https://192.0.2.1".into()),
            inner: Arc::new(Mutex::new(Inner {
                sessions: HashMap::new(),
                next_attempt: Instant::now(),
            })),
        };
        let mut headers = HeaderMap::new();
        assert!(!auth.same_origin(&headers));
        headers.insert(header::ORIGIN, "https://other.invalid".parse().unwrap());
        assert!(!auth.same_origin(&headers));
        headers.insert(header::ORIGIN, "https://192.0.2.1".parse().unwrap());
        assert!(auth.same_origin(&headers));
        headers.insert(
            header::COOKIE,
            "other=x; __Host-sb_session=test".parse().unwrap(),
        );
        assert!(!auth.authorized(&headers));
        auth.inner
            .lock()
            .unwrap()
            .sessions
            .insert("test".into(), Instant::now() + Duration::from_secs(1));
        assert!(auth.authorized(&headers));
        auth.inner
            .lock()
            .unwrap()
            .sessions
            .insert("test".into(), Instant::now());
        assert!(!auth.authorized(&headers));
    }
}
