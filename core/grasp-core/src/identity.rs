//! Self-signed TLS identity for the Grasp/LocalSend HTTPS layer.
//!
//! The fingerprint is the SHA-256 hash of the DER certificate, matching the
//! protocol requirement. The identity is persisted so peers can remember us.

use anyhow::{Context, Result};
use rcgen::{CertificateParams, KeyPair};
use sha2::{Digest, Sha256};
use std::path::{Path, PathBuf};

/// A persisted self-signed identity.
pub struct Identity {
    pub cert_pem: String,
    pub key_pem: String,
    pub fingerprint: String,
}

impl Identity {
    /// Loads a persisted identity from a state directory, or creates a new one.
    pub fn load_or_create(state_dir: &Path) -> Result<Self> {
        std::fs::create_dir_all(state_dir).ok();
        let path = state_dir.join("grasp-identity.json");

        if let Ok(data) = std::fs::read(&path) {
            if let Ok(identity) = serde_json::from_slice::<StoredIdentity>(&data) {
                if !identity.cert_pem.is_empty() {
                    return Ok(Identity {
                        cert_pem: identity.cert_pem,
                        key_pem: identity.key_pem,
                        fingerprint: identity.fingerprint,
                    });
                }
            }
        }

        let identity = Self::generate()?;
        let stored = StoredIdentity {
            cert_pem: identity.cert_pem.clone(),
            key_pem: identity.key_pem.clone(),
            fingerprint: identity.fingerprint.clone(),
        };
        if let Ok(json) = serde_json::to_vec(&stored) {
            let _ = std::fs::write(&path, json);
        }
        Ok(identity)
    }

    /// Generates a fresh P-256 self-signed identity.
    pub fn generate() -> Result<Self> {
        let key_pair = KeyPair::generate().context("generate P-256 key pair")?;
        let mut params = CertificateParams::new(vec!["grasp".to_string()])?;
        params
            .distinguished_name
            .push(rcgen::DnType::CommonName, "Grasp");

        let cert = params.self_signed(&key_pair)?;
        let cert_pem = cert.pem();
        let key_pem = key_pair.serialize_pem();

        let fingerprint = fingerprint_of(&cert.der());
        Ok(Identity {
            cert_pem,
            key_pem,
            fingerprint,
        })
    }

    /// Paths for writing the PEM pair to disk (used by TLS adapters).
    pub fn write_pem(&self, dir: &Path) -> Result<(PathBuf, PathBuf)> {
        std::fs::create_dir_all(dir).ok();
        let cert_path = dir.join("grasp-cert.pem");
        let key_path = dir.join("grasp-key.pem");
        std::fs::write(&cert_path, &self.cert_pem)?;
        std::fs::write(&key_path, &self.key_pem)?;
        Ok((cert_path, key_path))
    }
}

/// Returns the SHA-256 hash of a DER certificate as lowercase hex.
pub fn fingerprint_of(der: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(der);
    hex::encode(hasher.finalize())
}

#[derive(serde::Serialize, serde::Deserialize)]
struct StoredIdentity {
    cert_pem: String,
    key_pem: String,
    fingerprint: String,
}
