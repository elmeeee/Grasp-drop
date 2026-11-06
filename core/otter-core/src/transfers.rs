//! Transfer tracking shared by the server (receive) and sender (send).
//!
//! Active transfers are kept in memory and exposed to the UI through
//! [`snapshot`]. Finished transfers move into a history list that is saved to
//! `transfers.json` in the node's state directory, so history survives restarts.

use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};

/// Keep at most this many finished transfers in history.
const HISTORY_LIMIT: usize = 300;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct TransferRecord {
    pub id: String,
    /// `"in"` for received files, `"out"` for sent files.
    pub direction: String,
    /// Peer alias (device name) on the other side.
    pub peer: String,
    pub file_name: String,
    pub total: i64,
    pub done: i64,
    /// `"active"`, `"done"`, or `"failed"`.
    pub status: String,
    pub started_at: u64,
    #[serde(default)]
    pub finished_at: Option<u64>,
    #[serde(default)]
    pub error: Option<String>,
}

#[derive(Default)]
struct Registry {
    active: Vec<TransferRecord>,
    history: Vec<TransferRecord>,
    path: Option<PathBuf>,
}

static REGISTRY: OnceLock<Mutex<Registry>> = OnceLock::new();

fn registry() -> std::sync::MutexGuard<'static, Registry> {
    REGISTRY
        .get_or_init(|| Mutex::new(Registry::default()))
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// Loads saved history from `state_dir/transfers.json`. Call once at node start.
pub fn init(state_dir: &Path) {
    let path = state_dir.join("transfers.json");
    let history: Vec<TransferRecord> = std::fs::read(&path)
        .ok()
        .and_then(|data| serde_json::from_slice(&data).ok())
        .unwrap_or_default();
    let mut locked = registry();
    locked.history = history;
    locked.path = Some(path);
}

/// Registers a new transfer and returns its id.
pub fn begin(direction: &str, peer: &str, file_name: &str, total: i64) -> String {
    let id = uuid::Uuid::new_v4().to_string();
    let record = TransferRecord {
        id: id.clone(),
        direction: direction.to_string(),
        peer: peer.to_string(),
        file_name: file_name.to_string(),
        total,
        done: 0,
        status: "active".to_string(),
        started_at: now_ms(),
        finished_at: None,
        error: None,
    };
    registry().active.push(record);
    id
}

/// Updates the number of bytes transferred so far.
pub fn progress(id: &str, done: i64) {
    let mut locked = registry();
    if let Some(record) = locked.active.iter_mut().find(|r| r.id == id) {
        record.done = done;
    }
}

/// Marks a transfer finished and moves it into history.
pub fn finish(id: &str, ok: bool, error: Option<String>) {
    let mut locked = registry();
    let index = match locked.active.iter().position(|r| r.id == id) {
        Some(index) => index,
        None => return,
    };
    let mut record = locked.active.remove(index);
    record.status = if ok { "done" } else { "failed" }.to_string();
    if ok && record.total > 0 {
        record.done = record.total;
    }
    record.finished_at = Some(now_ms());
    record.error = error;

    locked.history.insert(0, record);
    locked.history.truncate(HISTORY_LIMIT);
    save_locked(&locked);
}

/// Removes every finished transfer from history.
pub fn clear_history() {
    let mut locked = registry();
    locked.history.clear();
    save_locked(&locked);
}

/// Active and finished transfers, for the UI.
#[derive(Serialize)]
pub struct Snapshot {
    pub active: Vec<TransferRecord>,
    pub history: Vec<TransferRecord>,
}

pub fn snapshot() -> Snapshot {
    let locked = registry();
    Snapshot {
        active: locked.active.clone(),
        history: locked.history.clone(),
    }
}

fn save_locked(registry: &Registry) {
    if let Some(path) = &registry.path {
        if let Ok(data) = serde_json::to_vec(&registry.history) {
            let _ = std::fs::write(path, data);
        }
    }
}
