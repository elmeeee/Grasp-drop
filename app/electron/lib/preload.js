// Preload script exposing a `GraspNative` bridge to the renderer. On Windows the
// heavy lifting happens in the Rust core sidecar; this bridge adapts the local
// HTTPS API into the same promise-based shape used by the Android plugin.

const { contextBridge, ipcRenderer } = require("electron");

const BASE = "https://127.0.0.1:53317";

async function jsonFetch(url, options) {
  const response = await fetch(url, options);
  if (!response.ok && response.status !== 204) {
    throw new Error(`HTTP ${response.status}`);
  }
  if (response.status === 204) return {};
  return response.json();
}

contextBridge.exposeInMainWorld("Capacitor", {
  Plugins: {
    GraspNative: {
      async start({ alias }) {
        const info = await jsonFetch(`${BASE}/api/localsend/v2/info`);
        return { alias: alias || info.alias, fingerprint: info.fingerprint, running: true };
      },
      async stop() {
        return {};
      },
      async getPeers() {
        // Peer discovery is exposed by the Rust core's info endpoint in a
        // future revision; return an empty list when unavailable.
        try {
          const peers = await jsonFetch(`${BASE}/api/localsend/v2/register`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ alias: "Grasp", version: "2.2", fingerprint: "" }),
          });
          return { peers: peers ? [peers] : [] };
        } catch (_) {
          return { peers: [] };
        }
      },
      async scanSubnet() {
        return {};
      },
      async getReceivedFiles() {
        try {
          const response = await jsonFetch(`${BASE}/api/localsend/v2/prepare-download`, {
            method: "POST",
          });
          const files = Object.values(response.files || {}).map((file) => ({
            name: file.fileName,
            size: file.size,
          }));
          return { files };
        } catch (_) {
          return { files: [] };
        }
      },
      async sendFiles() {
        throw new Error("Sending from the desktop app is not wired yet");
      },
      async saveReceivedFile() {
        return { savedTo: "" };
      },
    },
  },
});
