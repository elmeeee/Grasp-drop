// Otter web UI. Runs inside a Capacitor WebView (Windows/Android) and talks to
// the native layer through the `OtterNative` plugin. The plugin exposes the
// Rust core (server + discovery + sender) to JavaScript.

const { OtterNative } = window.Capacitor?.Plugins ?? {};

const state = {
  peers: [],
  running: false,
};

const els = {
  alias: document.getElementById("device-alias"),
  toggle: document.getElementById("toggle-service"),
  refresh: document.getElementById("refresh"),
  dropZone: document.getElementById("drop-zone"),
  fileInput: document.getElementById("file-input"),
  peerList: document.getElementById("peer-list"),
  fileList: document.getElementById("file-list"),
  fileCount: document.getElementById("file-count"),
  toast: document.getElementById("toast"),
};

let toastTimer = null;
function toast(message) {
  els.toast.textContent = message;
  els.toast.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => els.toast.classList.remove("show"), 2600);
}

function formatSize(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1073741824) return `${(bytes / 1048576).toFixed(1)} MB`;
  return `${(bytes / 1073741824).toFixed(2)} GB`;
}

function peerIcon(deviceType) {
  switch (deviceType) {
    case "mobile": return "📱";
    case "desktop": return "🖥️";
    case "web": return "🌐";
    default: return "💻";
  }
}

function renderPeers() {
  if (state.peers.length === 0) {
    els.peerList.innerHTML = '<p class="empty">Searching for devices on your network…</p>';
    return;
  }
  els.peerList.innerHTML = state.peers
    .map(
      (peer) => `
      <div class="peer">
        <div class="peer-info">
          <div class="peer-name">${peerIcon(peer.deviceType)} ${escapeHtml(peer.alias || peer.ip)}</div>
          <div class="peer-meta">${escapeHtml(peer.ip)}</div>
        </div>
        <button data-send="${escapeHtml(peer.fingerprint)}">Send</button>
      </div>`
    )
    .join("");

  els.peerList.querySelectorAll("button[data-send]").forEach((button) => {
    button.addEventListener("click", () => pickFilesAndSend(button.dataset.send));
  });
}

function renderFiles(files) {
  els.fileCount.textContent = `${files.length} file${files.length === 1 ? "" : "s"}`;
  if (!files.length) {
    els.fileList.innerHTML = '<p class="empty">No files yet</p>';
    return;
  }
  els.fileList.innerHTML = files
    .map(
      (file) => `
      <div class="file">
        <div class="file-info">
          <div class="file-name">${escapeHtml(file.name)}</div>
          <div class="file-meta">${formatSize(file.size)}</div>
        </div>
        <a href="#" data-save="${escapeHtml(file.name)}">Save</a>
      </div>`
    )
    .join("");

  els.fileList.querySelectorAll("a[data-save]").forEach((link) => {
    link.addEventListener("click", async (event) => {
      event.preventDefault();
      await saveFile(link.dataset.save);
    });
  });
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (char) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[char]));
}

async function refreshPeers() {
  if (!OtterNative) return;
  try {
    const { peers } = await OtterNative.getPeers();
    state.peers = peers || [];
    renderPeers();
  } catch (error) {
    console.error("getPeers failed", error);
  }
}

async function refreshFiles() {
  if (!OtterNative) return;
  try {
    const { files } = await OtterNative.getReceivedFiles();
    renderFiles(files || []);
  } catch (error) {
    console.error("getReceivedFiles failed", error);
  }
}

async function startService() {
  if (!OtterNative) {
    toast("Native plugin unavailable");
    return;
  }
  try {
    const result = await OtterNative.start({ alias: "Otter Desktop" });
    state.running = true;
    els.alias.textContent = result.alias || "Otter Device";
    toast("Visible on the network");
    refreshPeers();
  } catch (error) {
    toast(`Failed to start: ${error.message || error}`);
  }
}

async function stopService() {
  if (!OtterNative) return;
  await OtterNative.stop();
  state.running = false;
  els.alias.textContent = "Receiver off";
  state.peers = [];
  renderPeers();
  toast("Receiver stopped");
}

function pickFilesAndSend(fingerprint) {
  const peer = state.peers.find((item) => item.fingerprint === fingerprint);
  if (!peer) return;
  els.fileInput.onchange = async () => {
    const files = Array.from(els.fileInput.files || []);
    els.fileInput.value = "";
    if (!files.length) return;
    await sendFiles(peer, files);
  };
  els.fileInput.click();
}

async function sendFiles(peer, files) {
  toast(`Sending ${files.length} file(s) to ${peer.alias || peer.ip}…`);
  try {
    const payloads = await Promise.all(files.map(readFilePayload));
    const result = await OtterNative.sendFiles({
      targetIp: peer.ip,
      port: peer.port || 53317,
      files: payloads,
    });
    toast(`Sent ${result.sent}/${result.total} file(s)`);
  } catch (error) {
    toast(`Send failed: ${error.message || error}`);
  }
}

function readFilePayload(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () =>
      resolve({
        name: file.name,
        type: file.type || "application/octet-stream",
        base64: String(reader.result).split(",")[1],
      });
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}

async function saveFile(name) {
  try {
    const result = await OtterNative.saveReceivedFile({ name });
    toast(result.savedTo ? `Saved to ${result.savedTo}` : "File saved");
  } catch (error) {
    toast(`Save failed: ${error.message || error}`);
  }
}

function wireDropZone() {
  els.dropZone.addEventListener("click", () => {
    if (state.peers.length === 0) {
      toast("No device selected — pick a device first");
      return;
    }
    pickFilesAndSend(state.peers[0].fingerprint);
  });

  ["dragover", "dragenter"].forEach((type) =>
    els.dropZone.addEventListener(type, (event) => {
      event.preventDefault();
      els.dropZone.classList.add("dragover");
    })
  );
  ["dragleave", "drop"].forEach((type) =>
    els.dropZone.addEventListener(type, (event) => {
      event.preventDefault();
      els.dropZone.classList.remove("dragover");
    })
  );
  els.dropZone.addEventListener("drop", async (event) => {
    const files = Array.from(event.dataTransfer?.files || []);
    if (!files.length || !state.peers.length) return;
    await sendFiles(state.peers[0], files);
  });
}

function wireControls() {
  els.toggle.addEventListener("change", () => {
    if (els.toggle.checked) startService();
    else stopService();
  });
  els.refresh.addEventListener("click", async () => {
    await OtterNative?.scanSubnet?.();
    refreshPeers();
  });
}

function startPolling() {
  setInterval(() => {
    refreshPeers();
    refreshFiles();
  }, 3000);
}

async function main() {
  wireControls();
  wireDropZone();
  startPolling();
  await startService();
  await refreshFiles();
}

main();
