//! Multicast UDP discovery on 224.0.0.167:53317 (LocalSend v2 section 3).

use crate::protocol::*;
use anyhow::Result;
use socket2::{Domain, Protocol, Socket, Type};
use std::collections::HashMap;
use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4, UdpSocket};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

/// A callback invoked whenever a new peer is discovered.
pub type PeerCallback = Box<dyn Fn(Peer) + Send + Sync>;

/// Multicast discovery service.
pub struct Discovery {
    info: DeviceInfo,
    running: Arc<Mutex<bool>>,
    peers: Arc<Mutex<HashMap<String, Peer>>>,
    socket: Option<Arc<UdpSocket>>,
}

impl Discovery {
    /// Creates a discovery service and binds the multicast socket.
    pub fn new(info: DeviceInfo) -> Result<Self> {
        let socket = bind_multicast()?;
        Ok(Self {
            info,
            running: Arc::new(Mutex::new(true)),
            peers: Arc::new(Mutex::new(HashMap::new())),
            socket: Some(Arc::new(socket)),
        })
    }

    /// Starts listening for announcements and sends the initial announce.
    pub fn start(&self, on_found: Option<PeerCallback>) {
        let socket = match &self.socket {
            Some(socket) => Arc::clone(socket),
            None => return,
        };

        self.send_announce(true);

        let info = self.info.clone();
        let running = Arc::clone(&self.running);
        let peers = Arc::clone(&self.peers);

        thread::spawn(move || {
            let mut buffer = vec![0u8; 64 * 1024];
            loop {
                if !*running.lock().unwrap() {
                    break;
                }
                match socket.recv_from(&mut buffer) {
                    Ok((size, src)) => {
                        if let Ok(incoming) =
                            serde_json::from_slice::<DeviceInfo>(&buffer[..size])
                        {
                            if incoming.fingerprint.is_empty()
                                || incoming.fingerprint == info.fingerprint
                            {
                                continue;
                            }
                            let ip = match src {
                                SocketAddr::V4(v4) => v4.ip().to_string(),
                                SocketAddr::V6(v6) => v6.ip().to_string(),
                            };
                            let peer = Peer { info: incoming, ip };
                            let mut locked = peers.lock().unwrap();
                            let is_new = !locked.contains_key(&peer.info.fingerprint);
                            locked.insert(peer.info.fingerprint.clone(), peer.clone());
                            drop(locked);

                            if is_new {
                                if let Some(callback) = &on_found {
                                    callback(peer);
                                }
                            }
                        }
                    }
                    Err(_) => {
                        if !*running.lock().unwrap() {
                            break;
                        }
                    }
                }
            }
        });
    }

    /// Sends a multicast announcement to the group.
    pub fn send_announce(&self, announce: bool) {
        let socket = match &self.socket {
            Some(socket) => socket,
            None => return,
        };
        let mut message = self.info.clone();
        message.announce = Some(announce);
        if let Ok(payload) = serde_json::to_vec(&message) {
            let group = SocketAddrV4::new(
                MULTICAST_GROUP.parse().unwrap(),
                DEFAULT_PORT,
            );
            let _ = socket.send_to(&payload, group);
        }
    }

    /// Stores a peer found outside multicast (for example by a subnet scan).
    pub fn record(&self, peer: Peer) {
        self.peers.lock().unwrap().insert(peer.info.fingerprint.clone(), peer);
    }

    /// Returns the discovered peers.
    pub fn peers(&self) -> Vec<Peer> {
        self.peers.lock().unwrap().values().cloned().collect()
    }

    /// Stops discovery.
    pub fn stop(&self) {
        *self.running.lock().unwrap() = false;
    }
}

fn bind_multicast() -> Result<UdpSocket> {
    let socket = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))?;
    socket.set_reuse_address(true)?;

    let addr: SocketAddr = SocketAddrV4::new(Ipv4Addr::UNSPECIFIED, DEFAULT_PORT).into();
    socket.bind(&addr.into())?;

    let group: Ipv4Addr = MULTICAST_GROUP.parse().unwrap();
    socket.join_multicast_v4(&group, &Ipv4Addr::UNSPECIFIED)?;

    Ok(socket.into())
}

/// Fallback: probes every host on the local /24 via HTTP register, in parallel.
/// Each probe times out quickly so unused addresses do not stall the scan.
pub fn scan_subnet(info: &DeviceInfo, local_ip: Ipv4Addr, on_found: PeerCallback) {
    let octets = local_ip.octets();
    let prefix = format!("{}.{}.{}", octets[0], octets[1], octets[2]);
    let info = info.clone();
    let on_found: std::sync::Arc<dyn Fn(Peer) + Send + Sync> = std::sync::Arc::from(on_found);

    thread::spawn(move || {
        let client = match reqwest::blocking::Client::builder()
            .danger_accept_invalid_certs(true)
            .connect_timeout(Duration::from_millis(700))
            .timeout(Duration::from_millis(1500))
            .build()
        {
            Ok(client) => client,
            Err(_) => return,
        };

        // 16 workers, each covering a slice of the 1..=254 host range.
        let workers: Vec<_> = (0..16u8)
            .map(|worker| {
                let client = client.clone();
                let info = info.clone();
                let prefix = prefix.clone();
                let on_found = std::sync::Arc::clone(&on_found);
                let own_ip = local_ip.to_string();
                thread::spawn(move || {
                    for host in (1..=254u8).filter(|h| h % 16 == worker) {
                        let ip = format!("{}.{}", prefix, host);
                        if ip == own_ip {
                            continue;
                        }
                        let url = format!("https://{}:{}{}", ip, DEFAULT_PORT, PATH_REGISTER);
                        let response = match client.post(&url).json(&info).send() {
                            Ok(response) => response,
                            Err(_) => continue,
                        };
                        if let Ok(remote) = response.json::<DeviceInfo>() {
                            if !remote.fingerprint.is_empty() && remote.fingerprint != info.fingerprint {
                                on_found(Peer { info: remote, ip });
                            }
                        }
                    }
                })
            })
            .collect();
        for worker in workers {
            let _ = worker.join();
        }
    });
}
