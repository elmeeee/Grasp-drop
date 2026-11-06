//! C ABI surface for embedding the Otter core in native apps.
//!
//! The Android Capacitor plugin and any other native host can start a node and
//! query peers through these functions.

use crate::protocol::DeviceInfo;
use crate::{start_node, OtterNode};
use std::ffi::{c_char, CStr, CString};
use std::path::PathBuf;
use std::sync::Mutex;

/// Opaque node handle exposed across the FFI boundary.
pub struct OtterNodeHandle {
    node: Mutex<Option<OtterNode>>,
}

/// Starts a Otter node and returns an opaque handle, or null on failure.
///
/// # Safety
/// The returned handle must eventually be released with `otter_node_stop`.
#[no_mangle]
pub unsafe extern "C" fn otter_node_start(
    alias: *const c_char,
    state_dir: *const c_char,
    files_dir: *const c_char,
) -> *mut OtterNodeHandle {
    let alias = if alias.is_null() {
        "Otter Device".to_string()
    } else {
        CStr::from_ptr(alias).to_string_lossy().to_string()
    };
    let state_dir = if state_dir.is_null() {
        PathBuf::from(".")
    } else {
        PathBuf::from(CStr::from_ptr(state_dir).to_str().unwrap_or("."))
    };
    let files_dir = if files_dir.is_null() {
        PathBuf::from(".")
    } else {
        PathBuf::from(CStr::from_ptr(files_dir).to_str().unwrap_or("."))
    };

    match start_node(alias, state_dir, files_dir, None, None) {
        Ok(node) => {
            let handle = Box::new(OtterNodeHandle {
                node: Mutex::new(Some(node)),
            });
            Box::into_raw(handle)
        }
        Err(_) => std::ptr::null_mut(),
    }
}

/// Stops a node and frees its handle.
///
/// # Safety
/// `handle` must have been returned by `otter_node_start` and not used again.
#[no_mangle]
pub unsafe extern "C" fn otter_node_stop(handle: *mut OtterNodeHandle) {
    if handle.is_null() {
        return;
    }
    let boxed = Box::from_raw(handle);
    let node = boxed.node.lock().unwrap().take();
    if let Some(node) = node {
        node.discovery_stop();
    }
}

/// Returns the device fingerprint as a newly allocated C string.
///
/// # Safety
/// `handle` must be a valid pointer from `otter_node_start`. The caller owns the
/// returned string and must release it with `otter_string_free`.
#[no_mangle]
pub unsafe extern "C" fn otter_node_fingerprint(handle: *const OtterNodeHandle) -> *mut c_char {
    let fingerprint = with_node(handle, |node| node.fingerprint().to_string());
    to_c_string(fingerprint.unwrap_or_default())
}

/// Returns the discovered peers as a JSON array string.
///
/// # Safety
/// Same contract as `otter_node_fingerprint`.
#[no_mangle]
pub unsafe extern "C" fn otter_node_peers(handle: *const OtterNodeHandle) -> *mut c_char {
    let json = with_node(handle, |node| {
        let peers: Vec<PeerJson> = node
            .peers()
            .into_iter()
            .map(|peer| PeerJson {
                alias: peer.info.alias,
                ip: peer.ip,
                fingerprint: peer.info.fingerprint,
                device_type: peer.info.device_type,
                port: peer.info.port,
            })
            .collect();
        serde_json::to_string(&peers).unwrap_or_else(|_| "[]".to_string())
    });
    to_c_string(json.unwrap_or_else(|| "[]".to_string()))
}

/// Frees a string returned by the FFI functions above.
///
/// # Safety
/// `value` must come from one of the functions returning `*mut c_char`.
#[no_mangle]
pub unsafe extern "C" fn otter_string_free(value: *mut c_char) {
    if !value.is_null() {
        drop(CString::from_raw(value));
    }
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

fn with_node<T>(handle: *const OtterNodeHandle, f: impl FnOnce(&OtterNode) -> T) -> Option<T> {
    if handle.is_null() {
        return None;
    }
    let handle_ref = unsafe { &*handle };
    let locked = handle_ref.node.lock().ok()?;
    locked.as_ref().map(f)
}

fn to_c_string(value: String) -> *mut c_char {
    CString::new(value).unwrap_or_default().into_raw()
}

/// Placeholder used by documentation; not part of the runtime API.
pub fn device_info_typecheck(_: &DeviceInfo) {}
