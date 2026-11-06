//! Client that pushes files to a peer using the LocalSend upload API.

use crate::protocol::*;
use crate::transfers;
use anyhow::{anyhow, Context, Result};
use reqwest::blocking::Client;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;
use std::time::Duration;

/// Wraps a reader and reports how many bytes have been read through it.
struct CountingReader<R> {
    inner: R,
    transfer_id: String,
    done: i64,
}

impl<R: Read> Read for CountingReader<R> {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        let read = self.inner.read(buf)?;
        self.done += read as i64;
        transfers::progress(&self.transfer_id, self.done);
        Ok(read)
    }
}

/// Builds an HTTP client that accepts LocalSend's self-signed certificates.
pub fn build_client() -> Result<Client> {
    Client::builder()
        .danger_accept_invalid_certs(true)
        .timeout(Duration::from_secs(3600))
        .build()
        .context("build HTTP client")
}

/// Progress callback reporting completed and total file counts.
pub type ProgressFn<'a> = &'a dyn Fn(usize, usize);

/// Pushes files to a peer.
pub fn send_files(
    info: &DeviceInfo,
    peer: &Peer,
    paths: &[String],
    progress: Option<ProgressFn>,
) -> Result<usize> {
    if paths.is_empty() {
        return Ok(0);
    }

    let client = build_client()?;
    let base = peer.base_url();

    let mut files: HashMap<String, FileMetadata> = HashMap::new();
    let mut order: Vec<String> = Vec::with_capacity(paths.len());
    let mut path_by_id: HashMap<String, String> = HashMap::new();

    for (index, path) in paths.iter().enumerate() {
        // Hash by streaming so large files never sit in memory.
        let mut file = std::fs::File::open(path).with_context(|| format!("open {path}"))?;
        let mut hasher = Sha256::new();
        let size = std::io::copy(&mut file, &mut hasher).with_context(|| format!("read {path}"))? as i64;
        let digest = hex::encode(hasher.finalize());
        let id = format!("file-{}-{}", index, uuid::Uuid::new_v4().simple());
        let name = Path::new(path)
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_else(|| format!("file-{index}"));
        files.insert(
            id.clone(),
            FileMetadata {
                id: id.clone(),
                file_name: name,
                size,
                file_type: mime_for(path),
                sha256: Some(digest),
                preview: None,
                metadata: None,
            },
        );
        order.push(id.clone());
        path_by_id.insert(id, path.clone());
    }

    let request = PrepareUploadRequest {
        info: info.clone(),
        files,
    };

    let response = client
        .post(format!("{}{}", base, PATH_PREPARE_UPLOAD))
        .json(&request)
        .send()
        .context("prepare-upload")?;

    let status = response.status().as_u16();
    match status {
        200 => {}
        204 => return Ok(paths.len()),
        403 => return Err(anyhow!("transfer rejected by peer")),
        401 => return Err(anyhow!("PIN required by peer")),
        other => return Err(anyhow!("prepare-upload failed: HTTP {other}")),
    }

    let prepared: PrepareUploadResponse =
        response.json().context("decode prepare-upload response")?;

    let mut sent = 0;
    for id in &order {
        let token = match prepared.files.get(id) {
            Some(token) => token.clone(),
            None => continue,
        };
        let path = match path_by_id.get(id) {
            Some(path) => path.clone(),
            None => continue,
        };

        let url = format!(
            "{}{}?sessionId={}&fileId={}&token={}",
            base, PATH_UPLOAD, prepared.session_id, id, token
        );
        let file_name = Path::new(&path)
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_default();
        let size = std::fs::metadata(&path).map(|m| m.len() as i64).unwrap_or(0);
        let transfer_id = transfers::begin("out", &peer.info.alias, &file_name, size);

        let mut file = std::fs::File::open(&path).with_context(|| format!("open {path}"))?;
        file.seek(SeekFrom::Start(0))?;
        let reader = CountingReader {
            inner: file,
            transfer_id: transfer_id.clone(),
            done: 0,
        };
        let upload = client
            .post(&url)
            .header("Content-Type", "application/octet-stream")
            .body(reqwest::blocking::Body::sized(reader, size as u64))
            .send();

        let upload = match upload {
            Ok(response) => response,
            Err(err) => {
                transfers::finish(&transfer_id, false, Some(err.to_string()));
                return Err(anyhow!("upload {path}: {err}"));
            }
        };

        if upload.status().as_u16() != 200 {
            let status = upload.status().as_u16();
            transfers::finish(&transfer_id, false, Some(format!("HTTP {status}")));
            let _ = client
                .post(format!("{}{}?sessionId={}", base, PATH_CANCEL, prepared.session_id))
                .send();
            return Err(anyhow!("upload failed: HTTP {status}"));
        }
        transfers::finish(&transfer_id, true, None);

        sent += 1;
        if let Some(callback) = progress {
            callback(sent, order.len());
        }
    }

    Ok(sent)
}

/// Sends a short text message as a .txt file.
pub fn send_text(info: &DeviceInfo, peer: &Peer, text: &str) -> Result<usize> {
    let temp = std::env::temp_dir().join(format!("otter-text-{}.txt", uuid::Uuid::new_v4()));
    std::fs::write(&temp, text)?;
    let result = send_files(
        info,
        peer,
        &[temp.to_string_lossy().to_string()],
        None,
    );
    let _ = std::fs::remove_file(&temp);
    result
}

fn mime_for(path: &str) -> Option<String> {
    let extension = Path::new(path)
        .extension()
        .map(|e| e.to_string_lossy().to_lowercase())
        .unwrap_or_default();
    let mime = match extension.as_str() {
        "jpg" | "jpeg" => "image/jpeg",
        "png" => "image/png",
        "gif" => "image/gif",
        "pdf" => "application/pdf",
        "mp4" => "video/mp4",
        "txt" => "text/plain",
        "zip" => "application/zip",
        _ => "application/octet-stream",
    };
    Some(mime.to_string())
}
