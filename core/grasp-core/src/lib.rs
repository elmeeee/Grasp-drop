//! Grasp core library.
//!
//! A cross-platform local file-transfer engine that is wire-compatible with the
//! LocalSend Protocol v2.2. Used by the Grasp desktop (macOS/Windows/Linux) and
//! mobile (Android) applications.

pub mod discovery;
pub mod ffi;
pub mod identity;
#[cfg(target_os = "android")]
pub mod jni;
pub mod protocol;
pub mod sender;
pub mod server;
pub mod webhub;

use anyhow::Result;
use std::net::Ipv4Addr;
use std::path::PathBuf;
use std::sync::Arc;

use discovery::{Discovery, PeerCallback};
use identity::Identity;
use protocol::DeviceInfo;
use server::GraspServer;

/// Alias of a running node for application code.
pub struct GraspNode {
    server: GraspServer,
    discovery: Arc<Discovery>,
    identity: Identity,
    info: DeviceInfo,
}

impl GraspNode {
    /// Information about this device as reported to peers.
    pub fn info(&self) -> &DeviceInfo {
        &self.info
    }

    /// TLS certificate fingerprint.
    pub fn fingerprint(&self) -> &str {
        &self.identity.fingerprint
    }

    /// Returns a snapshot of discovered peers.
    pub fn peers(&self) -> Vec<protocol::Peer> {
        self.discovery.peers()
    }

    /// Triggers an HTTP subnet scan for peers.
    pub fn scan_subnet(&self, local_ip: Ipv4Addr, on_found: PeerCallback) {
        discovery::scan_subnet(&self.info, local_ip, on_found);
    }

    /// Stops discovery and the server.
    pub fn discovery_stop(&self) {
        self.discovery.stop();
        self.server.shutdown();
    }
}

/// Starts a Grasp node (server + discovery) and returns the handle.
pub fn start_node(
    alias: String,
    state_dir: PathBuf,
    files_dir: PathBuf,
    on_receive: Option<Box<dyn Fn(String, i64) + Send + Sync>>,
    on_peer: Option<PeerCallback>,
) -> Result<GraspNode> {
    let identity = Identity::load_or_create(&state_dir)?;
    let info = DeviceInfo::new(alias, identity.fingerprint.clone());

    let server = GraspServer::start(
        info.clone(),
        files_dir,
        protocol::DEFAULT_PORT,
        &identity,
        on_receive,
    )?;

    let discovery = Discovery::new(info.clone())?;
    discovery.start(on_peer);
    let discovery = Arc::new(discovery);

    Ok(GraspNode {
        server,
        discovery,
        identity,
        info,
    })
}
