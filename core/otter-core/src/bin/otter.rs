//! `otter` command-line interface.
//!
//! `otter` runs a Otter node (HTTPS server + discovery) for use on Windows and
//! Linux, or performs a one-shot send with `--send`.

use anyhow::Result;
use otter_core::protocol::{DeviceInfo, Peer, DEFAULT_PORT, SCHEME_HTTPS};
use otter_core::webhub::{WebHub, WEB_HUB_PORT};
use otter_core::{sender, start_node};
use std::path::PathBuf;

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let mut alias = default_alias();
    let mut send_to: Option<String> = None;
    let mut web_hub = true;
    let mut paths: Vec<String> = Vec::new();

    let mut index = 1;
    while index < args.len() {
        match args[index].as_str() {
            "--name" => {
                if index + 1 < args.len() {
                    alias = args[index + 1].clone();
                    index += 1;
                }
            }
            "--send" => {
                if index + 1 < args.len() {
                    send_to = Some(args[index + 1].clone());
                    index += 1;
                }
            }
            "--no-web" => web_hub = false,
            other => paths.push(other.to_string()),
        }
        index += 1;
    }

    if let Some(target) = send_to {
        return run_send(&alias, &target, &paths);
    }

    run_server(&alias, web_hub)
}

fn run_server(alias: &str, web_hub: bool) -> Result<()> {
    let home = dirs_home();
    let files_dir = home.join("Downloads").join("Otter");
    std::fs::create_dir_all(&files_dir).ok();
    let state_dir = files_dir.join(".otter");

    println!("==================================================");
    println!("   OTTER — Node");
    println!("==================================================");
    println!("   Device Name : {alias}");
    println!("   HTTPS Port  : {DEFAULT_PORT}");
    if web_hub {
        println!("   Web Hub     : http://<this-ip>:{WEB_HUB_PORT}");
    }
    println!("   Save Folder : {}", files_dir.display());
    println!("--------------------------------------------------");

    let node = start_node(
        alias.to_string(),
        state_dir,
        files_dir.clone(),
        Some(Box::new(|name, size| {
            println!("[Otter] Received {name} ({size} bytes)");
        })),
        Some(Box::new(|peer| {
            println!("[Otter] Found device: {} ({})", peer.info.alias, peer.ip);
        })),
    )?;

    let hub = if web_hub {
        match WebHub::start(files_dir, WEB_HUB_PORT) {
            Ok(hub) => Some(hub),
            Err(err) => {
                eprintln!("[Otter] Web hub disabled: {err}");
                None
            }
        }
    } else {
        None
    };

    println!("   Fingerprint : {}", node.fingerprint());
    println!("==================================================");
    println!("   Press Ctrl+C to stop.");

    let _keep_alive = hub;
    loop {
        std::thread::park();
    }
}

fn run_send(alias: &str, target: &str, paths: &[String]) -> Result<()> {
    if paths.is_empty() {
        eprintln!("Usage: otter --send <peer-ip> <file> [file...]");
        std::process::exit(1);
    }

    let info = DeviceInfo::new(alias, "cli-sender");
    let peer = Peer {
        info: DeviceInfo {
            alias: target.to_string(),
            version: otter_core::protocol::PROTOCOL_VERSION.to_string(),
            device_model: None,
            device_type: None,
            fingerprint: String::new(),
            port: Some(DEFAULT_PORT),
            protocol: Some(SCHEME_HTTPS.to_string()),
            download: None,
            announce: None,
        },
        ip: target.to_string(),
    };

    println!("Sending {} file(s) to {target}...", paths.len());
    let sent = sender::send_files(
        &info,
        &peer,
        paths,
        Some(&|done, total| println!("  [{done}/{total}] sent")),
    )?;
    println!("Done. {sent}/{} files delivered.", paths.len());
    Ok(())
}

fn default_alias() -> String {
    hostname().unwrap_or_else(|| "Otter Device".to_string())
}

fn hostname() -> Option<String> {
    if let Ok(name) = std::env::var("HOSTNAME") {
        if !name.trim().is_empty() {
            return Some(name.trim().to_string());
        }
    }
    // macOS and Windows have no /etc/hostname; ask the OS.
    let output = std::process::Command::new("hostname").arg("-s").output().ok()?;
    let name = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if name.is_empty() { None } else { Some(name) }
}

fn dirs_home() -> PathBuf {
    std::env::var("HOME")
        .or_else(|_| std::env::var("USERPROFILE"))
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("."))
}
