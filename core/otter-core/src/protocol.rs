//! Otter protocol data model.
//!
//! Modelled on the LocalSend Protocol v2.2 design (not wire-compatible with the
//! official LocalSend app. The protocol identifier stays `localsend` on the wire
//! even though the product is Otter.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Protocol version reported to peers (`major.minor`).
pub const PROTOCOL_VERSION: &str = "2.2";

/// Default port for both multicast UDP and the HTTP(S) server.
pub const DEFAULT_PORT: u16 = 53317;

/// Default multicast group address.
pub const MULTICAST_GROUP: &str = "224.0.0.167";

pub const SCHEME_HTTPS: &str = "https";
pub const SCHEME_HTTP: &str = "http";

pub const DEVICE_MOBILE: &str = "mobile";
pub const DEVICE_DESKTOP: &str = "desktop";
pub const DEVICE_WEB: &str = "web";
pub const DEVICE_HEADLESS: &str = "headless";
pub const DEVICE_SERVER: &str = "server";

/// Device type reported to peers, derived from the platform this core runs on.
fn local_device_type() -> &'static str {
    if cfg!(target_os = "android") || cfg!(target_os = "ios") {
        DEVICE_MOBILE
    } else {
        DEVICE_DESKTOP
    }
}

/// Describes a device participating in the protocol.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DeviceInfo {
    pub alias: String,
    pub version: String,
    #[serde(rename = "deviceModel", skip_serializing_if = "Option::is_none")]
    pub device_model: Option<String>,
    #[serde(rename = "deviceType", skip_serializing_if = "Option::is_none")]
    pub device_type: Option<String>,
    pub fingerprint: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub port: Option<u16>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub protocol: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub download: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub announce: Option<bool>,
}

impl DeviceInfo {
    /// Creates device info with the protocol fields Otter reports.
    pub fn new(alias: impl Into<String>, fingerprint: impl Into<String>) -> Self {
        Self {
            alias: alias.into(),
            version: PROTOCOL_VERSION.to_string(),
            device_model: Some(std::env::consts::OS.to_string()),
            device_type: Some(local_device_type().to_string()),
            fingerprint: fingerprint.into(),
            port: Some(DEFAULT_PORT),
            protocol: Some(SCHEME_HTTPS.to_string()),
            download: Some(true),
            announce: None,
        }
    }
}

/// A single file entry in a transfer session.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FileMetadata {
    pub id: String,
    #[serde(rename = "fileName")]
    pub file_name: String,
    pub size: i64,
    #[serde(rename = "fileType", skip_serializing_if = "Option::is_none")]
    pub file_type: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sha256: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub preview: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub metadata: Option<HashMap<String, String>>,
}

/// Metadata-only request sent before an upload.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrepareUploadRequest {
    pub info: DeviceInfo,
    pub files: HashMap<String, FileMetadata>,
}

/// Maps file IDs to one-time upload tokens.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrepareUploadResponse {
    #[serde(rename = "sessionId")]
    pub session_id: String,
    pub files: HashMap<String, String>,
}

/// Response returned by the reverse (download) API.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrepareDownloadResponse {
    pub info: DeviceInfo,
    #[serde(rename = "sessionId")]
    pub session_id: String,
    pub files: HashMap<String, FileMetadata>,
}

/// A discovered peer with its resolved IP address.
#[derive(Debug, Clone)]
pub struct Peer {
    pub info: DeviceInfo,
    pub ip: String,
}

impl Peer {
    /// Base URL for the peer's HTTP(S) endpoint.
    pub fn base_url(&self) -> String {
        let scheme = self
            .info
            .protocol
            .clone()
            .unwrap_or_else(|| SCHEME_HTTPS.to_string());
        let port = self.info.port.unwrap_or(DEFAULT_PORT);
        format!("{}://{}:{}", scheme, self.ip, port)
    }
}

// The wire paths retain the `localsend` identifier for interoperability.
pub const PATH_INFO: &str = "/api/otter/v2/info";
pub const PATH_REGISTER: &str = "/api/otter/v2/register";
pub const PATH_PREPARE_UPLOAD: &str = "/api/otter/v2/prepare-upload";
pub const PATH_UPLOAD: &str = "/api/otter/v2/upload";
pub const PATH_CANCEL: &str = "/api/otter/v2/cancel";
pub const PATH_PREPARE_DOWNLOAD: &str = "/api/otter/v2/prepare-download";
pub const PATH_DOWNLOAD: &str = "/api/otter/v2/download";
