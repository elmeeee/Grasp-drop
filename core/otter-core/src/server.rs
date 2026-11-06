//! Otter HTTP(S) server.

use crate::identity::Identity;
use crate::protocol::*;
use anyhow::{Context, Result};
use sha2::{Digest, Sha256};
use crate::transfers;
use std::collections::HashMap;
use std::io::{Read, Write};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use tiny_http::{Header, Method, Request, Response, Server, StatusCode};

/// Tracks an upload prepared but not yet completed.
#[derive(Clone)]
struct UploadSession {
    peer: String,
    files: HashMap<String, FileMetadata>,
    tokens: HashMap<String, String>,
}

/// A running Otter server.
pub struct OtterServer {
    port: u16,
    #[allow(dead_code)]
    server: Arc<Server>,
    #[allow(dead_code)]
    handle: Option<std::thread::JoinHandle<()>>,
}

/// Shared mutable server state.
struct ServerState {
    info: DeviceInfo,
    files_dir: PathBuf,
    #[allow(dead_code)]
    download: bool,
    sessions: HashMap<String, UploadSession>,
    download_registry: HashMap<String, String>,
    on_receive: Option<Box<dyn Fn(String, i64) + Send + Sync>>,
}

impl OtterServer {
    /// Starts an HTTPS server on the given port.
    pub fn start(
        info: DeviceInfo,
        files_dir: PathBuf,
        port: u16,
        identity: &Identity,
        on_receive: Option<Box<dyn Fn(String, i64) + Send + Sync>>,
    ) -> Result<Self> {
        let state = Arc::new(Mutex::new(ServerState {
            info,
            files_dir,
            download: true,
            sessions: HashMap::new(),
            download_registry: HashMap::new(),
            on_receive,
        }));

        let tls_config = build_tls_config(identity)?;
        let server = Server::https(
            format!("0.0.0.0:{}", port),
            tls_config,
        )
        .map_err(|e| anyhow::anyhow!("bind HTTPS port {}: {e}", port))?;
        let server = Arc::new(server);

        let serve_server = Arc::clone(&server);
        let serve_state = Arc::clone(&state);
        let handle = std::thread::spawn(move || {
            for request in serve_server.incoming_requests() {
                let state = Arc::clone(&serve_state);
                // Handle sequentially; transfers are large but LAN-bound.
                if let Err(err) = handle_request(request, state) {
                    eprintln!("[Otter] request error: {err}");
                }
            }
        });

        Ok(Self {
            port,
            server,
            handle: Some(handle),
        })
    }

    pub fn port(&self) -> u16 {
        self.port
    }

    /// Unblocks the server loop. `tiny_http` drains remaining requests.
    pub fn shutdown(&self) {
        self.server.unblock();
    }
}

fn build_tls_config(identity: &Identity) -> Result<tiny_http::SslConfig> {
    Ok(tiny_http::SslConfig {
        certificate: identity.cert_pem.as_bytes().to_vec(),
        private_key: identity.key_pem.as_bytes().to_vec(),
    })
}

fn handle_request(mut request: Request, state: Arc<Mutex<ServerState>>) -> Result<()> {
    let method = request.method().clone();
    let url = request.url().to_string();
    let (path, query) = split_url(&url);

    match (&method, path.as_str()) {
        (Method::Get, PATH_INFO) => {
            let info = state.lock().unwrap().info.clone();
            respond_json(request, &info)
        }
        (Method::Post, PATH_REGISTER) => {
            let mut body = String::new();
            let _ = request.as_reader().read_to_string(&mut body);
            if let Ok(remote) = serde_json::from_str::<DeviceInfo>(&body) {
                eprintln!("[Otter] Register from {} ({})", remote.alias, remote.fingerprint);
            }
            let info = state.lock().unwrap().info.clone();
            respond_json(request, &info)
        }
        (Method::Post, PATH_PREPARE_UPLOAD) => handle_prepare_upload(request, state),
        (Method::Post, PATH_UPLOAD) => handle_upload(request, &query, state),
        (Method::Post, PATH_CANCEL) => {
            let session_id = query.get("sessionId").cloned().unwrap_or_default();
            state.lock().unwrap().sessions.remove(&session_id);
            respond_text(request, StatusCode(200), "")
        }
        (Method::Post, PATH_PREPARE_DOWNLOAD) => handle_prepare_download(request, state),
        (Method::Get, PATH_DOWNLOAD) => handle_download(request, &query, state),
        _ => respond_text(request, StatusCode(404), "Not Found"),
    }
}

fn handle_prepare_upload(mut request: Request, state: Arc<Mutex<ServerState>>) -> Result<()> {
    let mut body = Vec::new();
    request
        .as_reader()
        .read_to_end(&mut body)
        .context("read prepare-upload body")?;

    let parsed: PrepareUploadRequest = match serde_json::from_slice(&body) {
        Ok(value) => value,
        Err(_) => return respond_text(request, StatusCode(400), "Invalid body"),
    };

    if parsed.files.is_empty() {
        return respond_text(request, StatusCode(204), "");
    }

    let session_id = uuid::Uuid::new_v4().to_string();
    let mut tokens = HashMap::new();
    for file_id in parsed.files.keys() {
        tokens.insert(file_id.clone(), uuid::Uuid::new_v4().to_string());
    }

    state.lock().unwrap().sessions.insert(
        session_id.clone(),
        UploadSession {
            peer: parsed.info.alias.clone(),
            files: parsed.files,
            tokens: tokens.clone(),
        },
    );

    respond_json(
        request,
        &PrepareUploadResponse {
            session_id,
            files: tokens,
        },
    )
}

fn handle_upload(
    request: Request,
    query: &HashMap<String, String>,
    state: Arc<Mutex<ServerState>>,
) -> Result<()> {
    let session_id = query.get("sessionId").cloned().unwrap_or_default();
    let file_id = query.get("fileId").cloned().unwrap_or_default();
    let token = query.get("token").cloned().unwrap_or_default();

    let (meta, peer, files_dir) = {
        let locked = state.lock().unwrap();
        let session = match locked.sessions.get(&session_id) {
            Some(session) => session.clone(),
            None => return respond_text(request, StatusCode(403), "Unknown session"),
        };
        if session.tokens.get(&file_id) != Some(&token) {
            return respond_text(request, StatusCode(403), "Invalid token");
        }
        let meta = match session.files.get(&file_id) {
            Some(meta) => meta.clone(),
            None => return respond_text(request, StatusCode(400), "Unknown file"),
        };
        (meta, session.peer.clone(), locked.files_dir.clone())
    };

    std::fs::create_dir_all(&files_dir).ok();
    let target = unique_path(&files_dir, &sanitize_name(&meta.file_name));
    let transfer_id = transfers::begin("in", &peer, &meta.file_name, meta.size);

    // Stream the body to disk while hashing it, reporting progress as we go.
    let mut request = request;
    let received = stream_to_file(request.as_reader(), &target, &transfer_id);
    let (written, digest) = match received {
        Ok(result) => result,
        Err(err) => {
            let _ = std::fs::remove_file(&target);
            transfers::finish(&transfer_id, false, Some(err.to_string()));
            return respond_text(request, StatusCode(500), "Transfer error");
        }
    };

    if let Some(expected) = &meta.sha256 {
        if !expected.is_empty() && !digest.eq_ignore_ascii_case(expected) {
            let _ = std::fs::remove_file(&target);
            transfers::finish(&transfer_id, false, Some("checksum mismatch".to_string()));
            return respond_text(request, StatusCode(422), "Checksum mismatch");
        }
    }

    let name = target
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_default();
    eprintln!("[Otter] Received {} ({} bytes)", name, written);
    transfers::finish(&transfer_id, true, None);

    if let Some(callback) = state.lock().unwrap().on_receive.as_ref() {
        callback(name, written);
    }

    respond_text(request, StatusCode(200), "")
}

/// Copies `reader` into `target`, returning the byte count and SHA-256 hex digest.
fn stream_to_file(
    reader: &mut dyn Read,
    target: &PathBuf,
    transfer_id: &str,
) -> Result<(i64, String)> {
    let mut file = std::fs::File::create(target).context("create target file")?;
    let mut hasher = Sha256::new();
    let mut buffer = vec![0u8; 64 * 1024];
    let mut total: i64 = 0;
    loop {
        let read = reader.read(&mut buffer).context("read upload body")?;
        if read == 0 {
            break;
        }
        file.write_all(&buffer[..read]).context("write file")?;
        hasher.update(&buffer[..read]);
        total += read as i64;
        transfers::progress(transfer_id, total);
    }
    file.flush().context("flush file")?;
    Ok((total, hex::encode(hasher.finalize())))
}

fn handle_prepare_download(
    request: Request,
    state: Arc<Mutex<ServerState>>,
) -> Result<()> {
    let (info, files, registry) = {
        let locked = state.lock().unwrap();
        let mut files = HashMap::new();
        let mut registry = HashMap::new();
        if let Ok(entries) = std::fs::read_dir(&locked.files_dir) {
            for entry in entries.flatten() {
                let name = entry.file_name().to_string_lossy().to_string();
                if name.starts_with('.') {
                    continue;
                }
                let size = entry.metadata().map(|m| m.len() as i64).unwrap_or(0);
                let id = uuid::Uuid::new_v4().to_string();
                registry.insert(id.clone(), name.clone());
                files.insert(
                    id.clone(),
                    FileMetadata {
                        id,
                        file_name: name,
                        size,
                        file_type: Some("application/octet-stream".to_string()),
                        sha256: None,
                        preview: None,
                        metadata: None,
                    },
                );
            }
        }
        (locked.info.clone(), files, registry)
    };

    state.lock().unwrap().download_registry = registry;

    respond_json(
        request,
        &PrepareDownloadResponse {
            info,
            session_id: uuid::Uuid::new_v4().to_string(),
            files,
        },
    )
}

fn handle_download(
    request: Request,
    query: &HashMap<String, String>,
    state: Arc<Mutex<ServerState>>,
) -> Result<()> {
    let file_id = match query.get("fileId") {
        Some(id) => id.clone(),
        None => return respond_text(request, StatusCode(400), "Missing fileId"),
    };

    let (name, files_dir) = {
        let locked = state.lock().unwrap();
        let name = locked
            .download_registry
            .get(&file_id)
            .cloned()
            .unwrap_or_else(|| sanitize_name(&file_id));
        (name, locked.files_dir.clone())
    };

    let path = files_dir.join(&name);
    let data = match std::fs::read(&path) {
        Ok(data) => data,
        Err(_) => return respond_text(request, StatusCode(404), "Not Found"),
    };

    let disposition = format!("attachment; filename=\"{}\"", name);
    let response = Response::from_data(data)
        .with_status_code(StatusCode(200))
        .with_header(header("Content-Type", "application/octet-stream"))
        .with_header(header("Content-Disposition", &disposition));
    request.respond(response)?;
    Ok(())
}

// MARK: - Helpers

fn respond_json<T: serde::Serialize>(request: Request, value: &T) -> Result<()> {
    let body = serde_json::to_vec(value)?;
    let response = Response::from_data(body)
        .with_status_code(StatusCode(200))
        .with_header(header("Content-Type", "application/json"));
    request.respond(response)?;
    Ok(())
}

fn respond_text(request: Request, status: StatusCode, body: &str) -> Result<()> {
    let response = Response::from_string(body)
        .with_status_code(status)
        .with_header(header("Content-Type", "text/plain"));
    request.respond(response)?;
    Ok(())
}

fn header(name: &str, value: &str) -> Header {
    Header::from_bytes(name.as_bytes(), value.as_bytes()).unwrap()
}

fn split_url(url: &str) -> (String, HashMap<String, String>) {
    let mut query = HashMap::new();
    match url.split_once('?') {
        Some((path, query_string)) => {
            for pair in query_string.split('&') {
                if pair.is_empty() {
                    continue;
                }
                let (key, value) = pair.split_once('=').unwrap_or((pair, ""));
                query.insert(percent_decode(key), percent_decode(value));
            }
            (percent_decode(path), query)
        }
        None => (percent_decode(url), query),
    }
}

fn percent_decode(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut output = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'%' && index + 2 < bytes.len() {
            if let Ok(value) = u8::from_str_radix(
                &input[index + 1..index + 3],
                16,
            ) {
                output.push(value);
                index += 3;
                continue;
            }
        }
        output.push(bytes[index]);
        index += 1;
    }
    String::from_utf8_lossy(&output).to_string()
}

fn sanitize_name(name: &str) -> String {
    PathBuf::from(name)
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "received_file".to_string())
}

fn unique_path(dir: &PathBuf, name: &str) -> PathBuf {
    let base = dir.join(name);
    if !base.exists() {
        return base;
    }
    let path = std::path::Path::new(name);
    let stem = path
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| "file".to_string());
    let ext = path.extension().map(|e| e.to_string_lossy().to_string());
    for index in 1..10_000 {
        let candidate = match &ext {
            Some(ext) => dir.join(format!("{} ({}).{}", stem, index, ext)),
            None => dir.join(format!("{} ({})", stem, index)),
        };
        if !candidate.exists() {
            return candidate;
        }
    }
    base
}
