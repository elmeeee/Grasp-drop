//! Optional browser portal ("Web Hub") served over plain HTTP on port 7456.
//!
//! Any device with a browser (iPhone, iPad, another PC) can open
//! `http://<host-ip>:7456` to upload files to this machine and download files
//! that Otter has received. This complements the HTTPS
//! server; browsers reject self-signed certificates, so this endpoint is plain
//! HTTP by design.

use anyhow::Result;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use tiny_http::{Header, Method, Request, Response, Server, StatusCode};

/// Default port for the browser portal.
pub const WEB_HUB_PORT: u16 = 7456;

/// A running web hub.
pub struct WebHub {
    server: Arc<Server>,
    #[allow(dead_code)]
    handle: Option<std::thread::JoinHandle<()>>,
}

struct HubState {
    files_dir: PathBuf,
    clipboard: String,
}

impl WebHub {
    /// Starts the web hub on the given port.
    pub fn start(files_dir: PathBuf, port: u16) -> Result<Self> {
        let server = Server::http(format!("0.0.0.0:{}", port))
            .map_err(|e| anyhow::anyhow!("bind web hub port {port}: {e}"))?;
        let server = Arc::new(server);

        let state = Arc::new(Mutex::new(HubState {
            files_dir,
            clipboard: String::new(),
        }));

        let serve_server = Arc::clone(&server);
        let serve_state = Arc::clone(&state);
        let handle = std::thread::spawn(move || {
            for request in serve_server.incoming_requests() {
                if let Err(err) = handle_request(request, Arc::clone(&serve_state)) {
                    eprintln!("[Otter] web hub error: {err}");
                }
            }
        });

        Ok(Self {
            server,
            handle: Some(handle),
        })
    }

    /// Unblocks the server loop.
    pub fn shutdown(&self) {
        self.server.unblock();
    }
}

fn handle_request(mut request: Request, state: Arc<Mutex<HubState>>) -> Result<()> {
    let method = request.method().clone();
    let url = request.url().to_string();
    let path = url.split('?').next().unwrap_or("/").to_string();

    match (&method, path.as_str()) {
        (Method::Get, "/") => {
            let response = Response::from_string(web_html())
                .with_header(header("Content-Type", "text/html; charset=utf-8"));
            request.respond(response)?;
        }
        (Method::Get, "/api/files") => {
            let json = list_files(&state);
            respond_json(request, &json)?;
        }
        (Method::Get, "/api/clipboard") => {
            let text = state.lock().unwrap().clipboard.clone();
            respond_json(request, &serde_json::json!({ "text": text }))?;
        }
        (Method::Post, "/api/clipboard") => {
            let mut body = String::new();
            let _ = request.as_reader().read_to_string(&mut body);
            state.lock().unwrap().clipboard = body;
            respond_text(request, StatusCode(200), "OK")?;
        }
        (Method::Get, p) if p.starts_with("/download/") => {
            let name = percent_decode(&p["/download/".len()..]);
            download_file(request, &state, &name)?;
        }
        (Method::Post, "/upload") => {
            upload_file(request, &state)?;
        }
        _ => respond_text(request, StatusCode(404), "Not Found")?,
    }
    Ok(())
}

#[derive(serde::Serialize)]
struct FileItem {
    name: String,
    size: i64,
}

fn list_files(state: &Arc<Mutex<HubState>>) -> Vec<FileItem> {
    let locked = state.lock().unwrap();
    let mut files = Vec::new();
    if let Ok(entries) = std::fs::read_dir(&locked.files_dir) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with('.') {
                continue;
            }
            let size = entry.metadata().map(|m| m.len() as i64).unwrap_or(0);
            files.push(FileItem { name, size });
        }
    }
    files.sort_by(|a, b| b.size.cmp(&a.size));
    files
}

fn download_file(
    request: Request,
    state: &Arc<Mutex<HubState>>,
    name: &str,
) -> Result<()> {
    let safe = sanitize(name);
    let dir = state.lock().unwrap().files_dir.clone();
    let data = match std::fs::read(dir.join(&safe)) {
        Ok(data) => data,
        Err(_) => return respond_text(request, StatusCode(404), "Not Found"),
    };
    let disposition = format!("attachment; filename=\"{}\"", safe);
    let response = Response::from_data(data)
        .with_header(header("Content-Type", "application/octet-stream"))
        .with_header(header("Content-Disposition", &disposition));
    request.respond(response)?;
    Ok(())
}

fn upload_file(mut request: Request, state: &Arc<Mutex<HubState>>) -> Result<()> {
    let content_type = request
        .headers()
        .iter()
        .find(|h| h.field.equiv("Content-Type"))
        .map(|h| h.value.as_str().to_string())
        .unwrap_or_default();

    let boundary = content_type
        .split("boundary=")
        .nth(1)
        .map(|b| b.trim_matches('"').to_string());

    let mut body = Vec::new();
    request.as_reader().read_to_end(&mut body)?;

    let boundary = match boundary {
        Some(boundary) => boundary,
        None => {
            let response = Response::from_string("Missing boundary")
                .with_status_code(StatusCode(400));
            request.respond(response)?;
            return Ok(());
        }
    };

    let parts = extract_files(&body, &boundary);
    if parts.is_empty() {
        let response = Response::from_string("No files in upload")
            .with_status_code(StatusCode(400));
        request.respond(response)?;
        return Ok(());
    }

    let dir = state.lock().unwrap().files_dir.clone();
    std::fs::create_dir_all(&dir).ok();

    let mut saved = 0usize;
    for (name, data) in parts {
        let transfer_id = crate::transfers::begin("in", "Web browser", &name, data.len() as i64);
        let target = unique_path(&dir, &sanitize(&name));
        match std::fs::write(&target, &data) {
            Ok(()) => {
                eprintln!("[Otter] Web upload saved: {}", target.display());
                crate::transfers::progress(&transfer_id, data.len() as i64);
                crate::transfers::finish(&transfer_id, true, None);
                saved += 1;
            }
            Err(err) => {
                crate::transfers::finish(&transfer_id, false, Some(err.to_string()));
            }
        }
    }

    let response = Response::from_string(format!("{saved} saved"))
        .with_status_code(StatusCode(200));
    request.respond(response)?;
    Ok(())
}

/// Returns every file part of a multipart/form-data body as (file name, bytes).
/// Parts without a filename (plain form fields) are skipped.
fn extract_files(body: &[u8], boundary: &str) -> Vec<(String, Vec<u8>)> {
    let delimiter = format!("--{}", boundary);
    let delimiter_bytes = delimiter.as_bytes();
    let header_end_marker = b"\r\n\r\n";

    let mut files = Vec::new();
    // Split the body on every boundary; each chunk is "\r\n<headers>\r\n\r\n<data>\r\n".
    let mut cursor = match find_bytes(body, delimiter_bytes) {
        Some(index) => index + delimiter_bytes.len(),
        None => return files,
    };

    loop {
        // The closing boundary is followed by "--".
        if body[cursor..].starts_with(b"--") {
            break;
        }
        let next = match find_bytes(&body[cursor..], delimiter_bytes) {
            Some(rel) => cursor + rel,
            None => break,
        };

        // Chunk is between cursor and next: strip leading CRLF and trailing CRLF.
        let mut chunk = &body[cursor..next];
        if chunk.starts_with(b"\r\n") {
            chunk = &chunk[2..];
        }
        if chunk.ends_with(b"\r\n") {
            chunk = &chunk[..chunk.len() - 2];
        }

        if let Some(split) = find_bytes(chunk, header_end_marker) {
            let headers = String::from_utf8_lossy(&chunk[..split]).to_string();
            if let Some(name) = headers
                .split("filename=\"")
                .nth(1)
                .and_then(|rest| rest.split('"').next())
                .filter(|name| !name.is_empty())
            {
                let data = chunk[split + header_end_marker.len()..].to_vec();
                files.push((name.to_string(), data));
            }
        }

        cursor = next + delimiter_bytes.len();
    }
    files
}

fn find_bytes(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() || haystack.len() < needle.len() {
        return None;
    }
    haystack
        .windows(needle.len())
        .position(|window| window == needle)
}

fn respond_json<T: serde::Serialize>(request: Request, value: &T) -> Result<()> {
    let body = serde_json::to_vec(value)?;
    let response = Response::from_data(body)
        .with_header(header("Content-Type", "application/json"))
        .with_header(header("Access-Control-Allow-Origin", "*"));
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

fn sanitize(name: &str) -> String {
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

fn percent_decode(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut output = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'%' && index + 2 < bytes.len() {
            if let Ok(value) = u8::from_str_radix(&input[index + 1..index + 3], 16) {
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

fn web_html() -> String {
    // Kept minimal and dependency-free; matches the Otter web portal styling.
    include_str!("webhub.html").to_string()
}
