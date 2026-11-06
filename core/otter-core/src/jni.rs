//! JNI bindings for the Android Otter app.
//!
//! These functions back `org.otter.app.OtterNativePlugin` and expose the same
//! node lifecycle as the C FFI, adapted to Java strings.

#![cfg(target_os = "android")]

use crate::protocol::{DeviceInfo, Peer, PROTOCOL_VERSION, SCHEME_HTTPS};
use crate::{sender, start_node, OtterNode};
use jni::objects::{JClass, JString};
use jni::sys::{jint, jlong, jstring};
use jni::JNIEnv;
use std::path::PathBuf;
use std::sync::Mutex;

struct NodeState {
    node: Mutex<Option<OtterNode>>,
}

/// Starts a node and returns an opaque handle (0 on failure).
#[no_mangle]
pub extern "system" fn Java_org_otter_app_OtterNativePlugin_nativeStart(
    mut env: JNIEnv,
    _class: JClass,
    alias: JString,
    state_dir: JString,
    files_dir: JString,
) -> jlong {
    let alias: String = env
        .get_string(&alias)
        .map(|s| s.into())
        .unwrap_or_else(|_| "Otter Device".to_string());
    let state_dir: String = env
        .get_string(&state_dir)
        .map(|s| s.into())
        .unwrap_or_else(|_| ".".to_string());
    let files_dir: String = env
        .get_string(&files_dir)
        .map(|s| s.into())
        .unwrap_or_else(|_| ".".to_string());

    match start_node(
        alias,
        PathBuf::from(state_dir),
        PathBuf::from(files_dir),
        None,
        None,
    ) {
        Ok(node) => {
            let boxed = Box::new(NodeState {
                node: Mutex::new(Some(node)),
            });
            Box::into_raw(boxed) as jlong
        }
        Err(_) => 0,
    }
}

/// Stops a node and releases its handle.
#[no_mangle]
pub extern "system" fn Java_org_otter_app_OtterNativePlugin_nativeStop(
    _env: JNIEnv,
    _class: JClass,
    handle: jlong,
) {
    if handle == 0 {
        return;
    }
    let boxed = unsafe { Box::from_raw(handle as *mut NodeState) };
    let node = boxed.node.lock().unwrap().take();
    if let Some(node) = node {
        node.discovery_stop();
    }
}

/// Returns the fingerprint of the running node.
#[no_mangle]
pub extern "system" fn Java_org_otter_app_OtterNativePlugin_nativeFingerprint(
    env: JNIEnv,
    _class: JClass,
    handle: jlong,
) -> jstring {
    let value = with_node(&handle, |node| node.fingerprint().to_string()).unwrap_or_default();
    env.new_string(value)
        .map(|s| s.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// Returns discovered peers as a JSON array string.
#[no_mangle]
pub extern "system" fn Java_org_otter_app_OtterNativePlugin_nativePeers(
    env: JNIEnv,
    _class: JClass,
    handle: jlong,
) -> jstring {
    let json = with_node(&handle, |node| {
        let peers: Vec<PeerJson> = node
            .peers()
            .into_iter()
            .map(PeerJson::from)
            .collect();
        serde_json::to_string(&peers).unwrap_or_else(|_| "[]".to_string())
    })
    .unwrap_or_else(|| "[]".to_string());

    env.new_string(json)
        .map(|s| s.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// Triggers an HTTP subnet scan for peers.
#[no_mangle]
pub extern "system" fn Java_org_otter_app_OtterNativePlugin_nativeScanSubnet(
    _env: JNIEnv,
    _class: JClass,
    handle: jlong,
) {
    with_node(&handle, |node| {
        if let Some(ip) = local_ipv4() {
            node.scan_subnet(ip, Box::new(|_| {}));
        }
    });
}

/// Sends the given files (JSON array of paths) to a peer.
#[no_mangle]
pub extern "system" fn Java_org_otter_app_OtterNativePlugin_nativeSendFiles(
    mut env: JNIEnv,
    _class: JClass,
    handle: jlong,
    target_ip: JString,
    peer_name: JString,
    port: jint,
    files_json: JString,
) -> jstring {
    let target_ip: String = env
        .get_string(&target_ip)
        .map(|s| s.into())
        .unwrap_or_default();
    let peer_name: String = env
        .get_string(&peer_name)
        .map(|s| s.into())
        .unwrap_or_else(|_| target_ip.clone());
    let files_json: String = env
        .get_string(&files_json)
        .map(|s| s.into())
        .unwrap_or_else(|_| "[]".to_string());

    let paths: Vec<String> = serde_json::from_str(&files_json).unwrap_or_default();
    let total = paths.len();

    let peer = Peer {
        info: DeviceInfo {
            alias: peer_name,
            version: PROTOCOL_VERSION.to_string(),
            device_model: None,
            device_type: None,
            fingerprint: String::new(),
            port: Some(port as u16),
            protocol: Some(SCHEME_HTTPS.to_string()),
            download: None,
            announce: None,
        },
        ip: target_ip,
    };

    let result = with_node(&handle, |node| {
        sender::send_files(node.info(), &peer, &paths, None)
    });

    let sent = match result {
        Some(Ok(sent)) => sent,
        Some(Err(_)) | None => 0,
    };

    let json = serde_json::json!({ "sent": sent, "total": total }).to_string();
    env.new_string(json)
        .map(|s| s.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

#[derive(serde::Serialize)]
struct PeerJson {
    alias: String,
    ip: String,
    fingerprint: String,
    #[serde(rename = "deviceType")]
    device_type: Option<String>,
    port: Option<u16>,
}

impl From<Peer> for PeerJson {
    fn from(peer: Peer) -> Self {
        Self {
            alias: peer.info.alias,
            ip: peer.ip,
            fingerprint: peer.info.fingerprint,
            device_type: peer.info.device_type,
            port: peer.info.port,
        }
    }
}

fn with_node<T>(handle: &jlong, f: impl FnOnce(&OtterNode) -> T) -> Option<T> {
    if *handle == 0 {
        return None;
    }
    let state = unsafe { &*(*handle as *const NodeState) };
    let locked = state.node.lock().ok()?;
    locked.as_ref().map(f)
}

fn local_ipv4() -> Option<std::net::Ipv4Addr> {
    let socket = std::net::UdpSocket::bind("0.0.0.0:0").ok()?;
    socket.connect("8.8.8.8:80").ok()?;
    match socket.local_addr().ok()? {
        std::net::SocketAddr::V4(addr) => Some(*addr.ip()),
        _ => None,
    }
}

/// Returns active and finished transfers as JSON: `{"active":[...],"history":[...]}`.
#[no_mangle]
pub extern "system" fn Java_org_otter_app_OtterNativePlugin_nativeTransfers(
    env: JNIEnv,
    _class: JClass,
) -> jstring {
    let json = serde_json::to_string(&crate::transfers::snapshot())
        .unwrap_or_else(|_| "{\"active\":[],\"history\":[]}".to_string());
    env.new_string(json)
        .map(|s| s.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// Clears finished transfers from history.
#[no_mangle]
pub extern "system" fn Java_org_otter_app_OtterNativePlugin_nativeClearHistory(
    _env: JNIEnv,
    _class: JClass,
) {
    crate::transfers::clear_history();
}
