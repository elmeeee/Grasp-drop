/* Otter web UI. Runs in the Capacitor WebView and talks to the native layer
 * through the OtterNative plugin (Android) or its desktop bridge. */

// ---------------------------------------------------------------- constants

const KEYS = { name: "otter.deviceName", visible: "otter.visible" };
const POLL_FAST_MS = 700;   // live transfers
const POLL_SLOW_MS = 3000;  // devices, inbox
const HISTORY_SHOWN = 50;

// Flat, single-colour icons (feather style). Colour comes from CSS.
const ICONS = {
  send: '<path d="M22 2 11 13"/><path d="M22 2 15 22l-4-9-9-4 20-7z"/>',
  download: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/>',
  upload: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/>',
  check: '<polyline points="20 6 9 17 4 12"/>',
  alert: '<circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/>',
  info: '<circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/>',
  settings: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
  trash: '<polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/><path d="M10 11v6M14 11v6"/><path d="M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/>',
  phone: '<rect x="5" y="2" width="14" height="20" rx="2"/><line x1="12" y1="18" x2="12.01" y2="18"/>',
  desktop: '<rect x="2" y="3" width="20" height="14" rx="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/>',
  file: '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/>',
  image: '<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/>',
  video: '<rect x="2" y="5" width="15" height="14" rx="2"/><polygon points="23 7 16 12 23 17 23 7"/>',
  music: '<path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>',
  x: '<line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>',
  refresh: '<polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/>',
  wifi: '<path d="M5 12.55a11 11 0 0 1 14.08 0"/><path d="M1.42 9a16 16 0 0 1 21.16 0"/><path d="M8.53 16.11a6 6 0 0 1 6.95 0"/><line x1="12" y1="20" x2="12.01" y2="20"/>',
  inbox: '<polyline points="22 12 16 12 14 15 10 15 8 12 2 12"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>',
  sweep: '<path d="M3 6h18"/><path d="M8 6V4h8v2"/><path d="M6 6l1 14h10l1-14"/>',
};

function icon(name, size = 18) {
  return `<svg viewBox="0 0 24 24" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name] || ""}</svg>`;
}

// ---------------------------------------------------------------- state

const state = {
  visible: localStorage.getItem(KEYS.visible) !== "0",
  deviceName: localStorage.getItem(KEYS.name) || "",
  displayName: "",
  running: false,
  peers: [],
  inbox: [],
  active: [],
  history: [],
  speeds: new Map(),        // id -> { done, t, bps }
  knownActive: new Map(),   // id -> last seen record (to detect completion)
  sigs: {},                 // last rendered signature per section
};

const $ = (sel) => document.querySelector(sel);

// ---------------------------------------------------------------- helpers

function esc(value) {
  return String(value ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

function fmtBytes(bytes) {
  const n = Number(bytes) || 0;
  if (n < 1024) return `${n} B`;
  if (n < 1024 ** 2) return `${(n / 1024).toFixed(1)} KB`;
  if (n < 1024 ** 3) return `${(n / 1024 ** 2).toFixed(1)} MB`;
  return `${(n / 1024 ** 3).toFixed(2)} GB`;
}

function fmtRate(bps) {
  return bps > 1 ? `${fmtBytes(bps)}/s` : "";
}

function fmtTime(ms) {
  if (!ms) return "";
  const date = new Date(ms);
  const now = new Date();
  const sameDay = date.toDateString() === now.toDateString();
  const hh = String(date.getHours()).padStart(2, "0");
  const mm = String(date.getMinutes()).padStart(2, "0");
  if (sameDay) return `Today ${hh}:${mm}`;
  const diffDays = Math.round((now - date) / 86400000);
  if (diffDays === 1) return `Yesterday ${hh}:${mm}`;
  return `${date.getDate()}/${date.getMonth() + 1} ${hh}:${mm}`;
}

function kindOf(name) {
  const ext = String(name).split(".").pop().toLowerCase();
  if (["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp"].includes(ext)) return "image";
  if (["mp4", "mov", "mkv", "webm", "3gp", "avi"].includes(ext)) return "video";
  if (["mp3", "m4a", "wav", "ogg", "flac", "aac"].includes(ext)) return "music";
  return "file";
}

function kindIcon(name) {
  return icon(kindOf(name) === "file" ? "file" : kindOf(name), 18);
}

function saveLabel(name) {
  const kind = kindOf(name);
  if (kind === "image") return "Save to Gallery";
  if (kind === "video") return "Save to Videos";
  if (kind === "music") return "Save to Music";
  return "Save to Downloads";
}

/** Re-renders a container only when its content actually changed, so taps are not lost. */
function render(key, el, html) {
  if (state.sigs[key] === html) return;
  state.sigs[key] = html;
  el.innerHTML = html;
}

async function native(method, args = {}) {
  const plugin = window.Capacitor?.Plugins?.OtterNative;
  if (!plugin || typeof plugin[method] !== "function") {
    throw new Error("Otter native service is not available here");
  }
  return plugin[method](args);
}

// ---------------------------------------------------------------- toasts

const TOAST_ICON = { success: "check", error: "alert", info: "info" };

function toast({ type = "info", title, message = "", duration = 3600, action = null }) {
  const root = $("#toasts");
  const el = document.createElement("div");
  el.className = `toast toast-${type}`;
  el.setAttribute("role", "status");
  el.innerHTML = `
    <div class="toast-icon">${icon(TOAST_ICON[type] || "info", 20)}</div>
    <div class="toast-body">
      <div class="toast-title">${esc(title)}</div>
      ${message ? `<div class="toast-msg">${esc(message)}</div>` : ""}
      ${action ? `<button class="toast-action">${esc(action.label)}</button>` : ""}
    </div>
    <button class="toast-x" aria-label="Dismiss">${icon("x", 16)}</button>`;

  const close = () => {
    el.classList.remove("show");
    setTimeout(() => el.remove(), 240);
  };
  el.querySelector(".toast-x").addEventListener("click", close);
  if (action) {
    el.querySelector(".toast-action").addEventListener("click", async () => {
      close();
      try { await action.run(); } catch (error) { toast({ type: "error", title: "Could not complete", message: error.message || String(error) }); }
    });
  }

  root.appendChild(el);
  requestAnimationFrame(() => el.classList.add("show"));
  while (root.children.length > 3) root.firstElementChild.remove();
  if (duration > 0) setTimeout(close, duration);
  return el;
}

// ---------------------------------------------------------------- sheets

let sheetEl = null;

function openSheet(title, html, bind) {
  closeSheet();
  const scrim = document.createElement("div");
  scrim.className = "scrim";
  scrim.innerHTML = `
    <section class="sheet" role="dialog" aria-modal="true" aria-label="${esc(title)}">
      <div class="sheet-grab"></div>
      <header class="sheet-head">
        <h2>${esc(title)}</h2>
        <button class="icon-btn" data-close aria-label="Close">${icon("x", 18)}</button>
      </header>
      <div class="sheet-body">${html}</div>
    </section>`;
  document.body.appendChild(scrim);
  requestAnimationFrame(() => scrim.classList.add("open"));

  scrim.addEventListener("click", (event) => {
    if (event.target === scrim || event.target.closest("[data-close]")) closeSheet();
  });
  if (bind) bind(scrim.querySelector(".sheet-body"), closeSheet);
  sheetEl = scrim;
}

function closeSheet() {
  if (!sheetEl) return;
  const el = sheetEl;
  sheetEl = null;
  el.classList.remove("open");
  setTimeout(() => el.remove(), 220);
}

// ---------------------------------------------------------------- header / visibility

function renderHeader() {
  $("#device-name").textContent = state.displayName || state.deviceName || "This device";
  $("#visible").checked = state.visible;

  const status = $("#status");
  const text = $("#status-text");
  if (!state.visible) {
    status.className = "status off";
    text.textContent = "Hidden from nearby devices";
  } else if (state.running) {
    status.className = "status on";
    text.textContent = state.peers.length
      ? `Visible · ${state.peers.length} device${state.peers.length === 1 ? "" : "s"} nearby`
      : "Visible · looking for devices";
  } else {
    status.className = "status off";
    text.textContent = "Starting…";
  }
  $("#settings-btn").innerHTML = icon("settings", 20);
  document.querySelectorAll("[data-icon]").forEach((el) => {
    if (el.id !== "settings-btn") el.innerHTML = icon(el.dataset.icon, 18);
  });
}

async function startNode() {
  try {
    const result = await native("start", state.deviceName ? { alias: state.deviceName } : {});
    state.running = true;
    state.displayName = result.alias || state.deviceName;
  } catch (error) {
    state.running = false;
    toast({ type: "error", title: "Could not go visible", message: error.message || String(error) });
  }
  renderHeader();
}

async function stopNode() {
  try { await native("stop"); } catch (_) { /* already stopped */ }
  state.running = false;
  state.peers = [];
  renderHeader();
  renderPeers();
}

async function setVisible(on) {
  state.visible = on;
  localStorage.setItem(KEYS.visible, on ? "1" : "0");
  if (on) {
    await startNode();
    toast({ type: "success", title: "You're visible", message: "Nearby devices can find and send to you." });
  } else {
    await stopNode();
    toast({ type: "info", title: "Hidden", message: "Nearby devices can't see you now." });
  }
}

// ---------------------------------------------------------------- live activity

function liveCard(t) {
  const out = t.direction === "out";
  const pct = t.total > 0 ? Math.min(100, Math.round((t.done / t.total) * 100)) : 0;
  const speed = state.speeds.get(t.id)?.bps || 0;
  const foot = speed > 1
    ? `${fmtRate(speed)} · ${pct}%`
    : (t.done === 0 ? "Starting…" : `${pct}%`);
  return `
    <article class="live ${out ? "is-out" : "is-in"}">
      <div class="live-top">
        <span class="badge ${out ? "primary" : "success"}">${icon(out ? "upload" : "download", 18)}</span>
        <div class="live-meta">
          <div class="live-name">${esc(t.file_name)}</div>
          <div class="live-sub">${out ? "To" : "From"} ${esc(t.peer)} · ${fmtBytes(t.done)} of ${fmtBytes(t.total)}</div>
        </div>
        <span class="pct">${pct}%</span>
      </div>
      <div class="bar"><span style="width:${pct}%"></span></div>
      <div class="live-foot">${esc(foot)}</div>
    </article>`;
}

function renderLive() {
  const section = $("#live-section");
  section.hidden = state.active.length === 0;
  $("#live-count").textContent = state.active.length ? `${state.active.length} active` : "";
  render("live", $("#live"), state.active.map(liveCard).join(""));
}

// ---------------------------------------------------------------- devices

function deviceIcon(peer) {
  return icon(peer.deviceType === "mobile" ? "phone" : "desktop", 18);
}

function renderPeers() {
  const html = state.peers.length
    ? state.peers.map((peer) => `
        <div class="card">
          <span class="badge muted">${deviceIcon(peer)}</span>
          <div class="row-body">
            <div class="row-title">${esc(peer.alias || peer.ip)}</div>
            <div class="row-sub">${esc(peer.ip)}</div>
          </div>
          <div class="row-actions">
            <button class="btn primary small" data-action="send-peer" data-fp="${esc(peer.fingerprint)}">${icon("send", 14)}<span>Send</span></button>
          </div>
        </div>`).join("")
    : `<div class="empty"><span class="empty-icon">${icon("wifi", 18)}</span>
         <span>No devices yet. Open Otter on another device on the same Wi-Fi.</span></div>`;
  render("peers", $("#peers"), html);
}

// ---------------------------------------------------------------- inbox

function renderInbox() {
  $("#inbox-count").textContent = state.inbox.length ? String(state.inbox.length) : "";
  const html = state.inbox.length
    ? state.inbox.map((file) => `
        <div class="card">
          <span class="badge muted">${kindIcon(file.name)}</span>
          <div class="row-body">
            <div class="row-title">${esc(file.name)}</div>
            <div class="row-sub">${fmtBytes(file.size)}</div>
          </div>
          <div class="row-actions">
            <button class="btn ghost small" data-action="save" data-name="${esc(file.name)}">${esc(saveLabel(file.name))}</button>
            <button class="icon-btn" data-action="delete" data-name="${esc(file.name)}" aria-label="Delete">${icon("trash", 17)}</button>
          </div>
        </div>`).join("")
    : `<div class="empty"><span class="empty-icon">${icon("inbox", 18)}</span><span>Nothing waiting. Received files show up here.</span></div>`;
  render("inbox", $("#inbox"), html);
}

// ---------------------------------------------------------------- history

function historyRow(item) {
  const received = item.direction === "in";
  const failed = item.status === "failed";
  const badge = failed ? "danger" : received ? "success" : "primary";
  const chip = failed
    ? '<span class="chip danger">Failed</span>'
    : received
      ? '<span class="chip success">Received</span>'
      : '<span class="chip primary">Sent</span>';
  const sub = [
    received ? `From ${item.peer}` : `To ${item.peer}`,
    fmtTime(item.finished_at || item.started_at),
  ].filter(Boolean).join(" · ");
  return `
    <div class="card">
      <span class="badge ${badge}">${icon(failed ? "alert" : received ? "download" : "upload", 18)}</span>
      <div class="row-body">
        <div class="row-title">${esc(item.file_name)}</div>
        <div class="row-sub">${esc(sub)}</div>
      </div>
      ${chip}
    </div>`;
}

function renderHistory() {
  const shown = state.history.slice(0, HISTORY_SHOWN);
  const html = shown.length
    ? shown.map(historyRow).join("")
    : `<div class="empty"><span class="empty-icon">${icon("sweep", 18)}</span><span>No transfers yet.</span></div>`;
  render("history", $("#history"), html);
  $("#clear-history").hidden = state.history.length === 0;
}

// ---------------------------------------------------------------- polling

function updateSpeeds(list) {
  const now = performance.now();
  for (const t of list) {
    const prev = state.speeds.get(t.id);
    if (!prev) {
      state.speeds.set(t.id, { done: t.done, t: now, bps: 0 });
      continue;
    }
    const dt = now - prev.t;
    if (dt > 0) {
      const instant = ((t.done - prev.done) / dt) * 1000;
      prev.bps = prev.bps ? prev.bps * 0.6 + instant * 0.4 : instant;
      prev.done = t.done;
      prev.t = now;
    }
  }
  const live = new Set(list.map((t) => t.id));
  for (const id of [...state.speeds.keys()]) if (!live.has(id)) state.speeds.delete(id);
}

/** Announces transfers that just finished (received or failed). Sent files are
 *  announced by sendFiles() once the whole batch completes. */
async function announceFinished(history) {
  const nowActive = new Set(state.active.map((t) => t.id));
  const finished = [...state.knownActive.keys()].filter((id) => !nowActive.has(id));
  state.knownActive = new Map(state.active.map((t) => [t.id, t]));
  if (!finished.length) return;

  for (const id of finished) {
    const record = history.find((h) => h.id === id);
    if (!record) continue;
    if (record.direction === "in" && record.status === "done") {
      toast({
        type: "success",
        title: `Received ${record.file_name}`,
        message: `From ${record.peer}`,
        duration: 6000,
        action: kindOf(record.file_name) === "file" ? null : {
          label: saveLabel(record.file_name),
          run: () => saveFile(record.file_name),
        },
      });
    } else if (record.status === "failed") {
      toast({
        type: "error",
        title: record.direction === "in" ? "Transfer failed" : "Could not send",
        message: `${record.file_name}${record.error ? ` · ${record.error}` : ""}`,
        duration: 6000,
      });
    }
  }
  await refreshInbox();
}

async function refreshTransfers() {
  try {
    const snapshot = await native("getTransfers");
    state.active = snapshot.active || [];
    state.history = snapshot.history || [];
    updateSpeeds(state.active);
    await announceFinished(state.history);
    renderLive();
    renderHistory();
  } catch (_) {
    // Native service not running yet; keep the last view.
  }
}

async function refreshPeers() {
  try {
    const { peers } = await native("getPeers");
    state.peers = peers || [];
    renderPeers();
    renderHeader();
  } catch (_) { /* not available */ }
}

async function refreshInbox() {
  try {
    const { files } = await native("getReceivedFiles");
    state.inbox = files || [];
    renderInbox();
  } catch (_) { /* not available */ }
}

function startPolling() {
  setInterval(refreshTransfers, POLL_FAST_MS);
  setInterval(() => { refreshPeers(); refreshInbox(); }, POLL_SLOW_MS);
}

// ---------------------------------------------------------------- send

const fileInput = $("#file-input");

function readAsBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result).split(",")[1] || "");
    reader.onerror = () => reject(reader.error || new Error("Could not read file"));
    reader.readAsDataURL(file);
  });
}

async function sendFiles(peer, files) {
  if (!files.length) return;
  const label = files.length === 1 ? files[0].name : `${files.length} files`;
  toast({ type: "info", title: `Sending to ${peer.alias || peer.ip}`, message: label, duration: 2200 });

  try {
    const payloads = [];
    for (const file of files) {
      payloads.push({ name: file.name, type: file.type || "application/octet-stream", base64: await readAsBase64(file) });
    }
    const result = await native("sendFiles", {
      targetIp: peer.ip,
      peerName: peer.alias || peer.ip,
      port: peer.port || 53317,
      files: payloads,
    });
    const sent = result.sent ?? 0;
    const total = result.total ?? files.length;
    if (sent === total) {
      toast({ type: "success", title: `Sent ${sent} ${sent === 1 ? "file" : "files"}`, message: `To ${peer.alias || peer.ip}` });
    } else {
      toast({ type: "error", title: "Some files were not sent", message: `${sent} of ${total} delivered` });
    }
  } catch (error) {
    toast({ type: "error", title: "Send failed", message: error.message || String(error) });
  } finally {
    refreshTransfers();
  }
}

function pickFilesFor(peer) {
  fileInput.value = "";
  fileInput.onchange = () => {
    const files = Array.from(fileInput.files || []);
    fileInput.value = "";
    sendFiles(peer, files);
  };
  fileInput.click();
}

function chooseDeviceAndSend() {
  if (state.peers.length === 0) {
    toast({ type: "info", title: "No devices yet", message: "Make sure the other device has Otter open on the same Wi-Fi." });
    return;
  }
  if (state.peers.length === 1) {
    pickFilesFor(state.peers[0]);
    return;
  }
  const options = state.peers.map((peer) => `
    <button class="option" data-pick="${esc(peer.fingerprint)}">
      <span class="badge muted">${deviceIcon(peer)}</span>
      <span class="row-body"><span class="row-title" style="display:block">${esc(peer.alias || peer.ip)}</span>
      <span class="row-sub" style="display:block">${esc(peer.ip)}</span></span>
    </button>`).join("");
  openSheet("Send to", options, (body, close) => {
    body.addEventListener("click", (event) => {
      const button = event.target.closest("[data-pick]");
      if (!button) return;
      const peer = state.peers.find((p) => p.fingerprint === button.dataset.pick);
      close();
      if (peer) pickFilesFor(peer);
    });
  });
}

// ---------------------------------------------------------------- inbox actions

async function saveFile(name) {
  try {
    const result = await native("saveReceivedFile", { name });
    const where = result.savedTo ? result.savedTo.replace(/\/[^/]*$/, "") : "";
    toast({ type: "success", title: "Saved", message: where ? `${name} → ${where}` : name });
  } catch (error) {
    toast({ type: "error", title: "Could not save", message: error.message || String(error) });
  } finally {
    refreshInbox();
  }
}

async function deleteFile(name) {
  try {
    await native("deleteReceivedFile", { name });
    toast({ type: "info", title: "Deleted", message: name, duration: 2400 });
  } catch (error) {
    toast({ type: "error", title: "Could not delete", message: error.message || String(error) });
  } finally {
    refreshInbox();
  }
}

// ---------------------------------------------------------------- history actions

function confirmClearHistory() {
  if (!state.history.length) return;
  openSheet("Clear history?",
    `<p>This removes the list of sent and received transfers. Files you saved or received stay where they are.</p>
     <div class="row-actions end">
       <button class="btn ghost" data-close>Cancel</button>
       <button class="btn danger" id="confirm-clear">Clear history</button>
     </div>`,
    (body, close) => {
      body.querySelector("#confirm-clear").addEventListener("click", async () => {
        close();
        try {
          await native("clearHistory");
          state.history = [];
          renderHistory();
          toast({ type: "success", title: "History cleared" });
        } catch (error) {
          toast({ type: "error", title: "Could not clear history", message: error.message || String(error) });
        }
      });
    });
}

// ---------------------------------------------------------------- settings

function openSettings() {
  const current = state.deviceName || state.displayName || "";
  openSheet("Settings",
    `<div class="field">
       <label for="device-input">Device name</label>
       <input id="device-input" maxlength="40" value="${esc(current)}" placeholder="e.g. My Phone" autocomplete="off" />
       <span class="help">Shown to other devices when they look for you. Leave empty to use the phone's name.</span>
     </div>
     <div class="row-actions end">
       <button class="btn ghost" data-close>Cancel</button>
       <button class="btn primary" id="save-name">Save name</button>
     </div>
     <div class="field" style="margin-top:6px">
       <span class="help">Received files are saved to Gallery (images, videos) or Downloads (everything else) when you tap Save.</span>
     </div>`,
    (body, close) => {
      const input = body.querySelector("#device-input");
      body.querySelector("#save-name").addEventListener("click", async () => {
        const next = input.value.trim();
        close();
        if (next === state.deviceName) return;
        state.deviceName = next;
        if (next) localStorage.setItem(KEYS.name, next);
        else localStorage.removeItem(KEYS.name);
        if (state.visible) {
          await startNode();
        } else {
          state.displayName = next || state.displayName;
          renderHeader();
        }
        toast({ type: "success", title: "Device name updated", message: next || "Using the phone's name" });
      });
    });
}

// ---------------------------------------------------------------- wiring

function wire() {
  const bar = document.querySelector(".topbar-sticky");
  window.addEventListener("scroll", () => bar.classList.toggle("scrolled", window.scrollY > 4), { passive: true });

  document.addEventListener("click", (event) => {
    const el = event.target.closest("[data-action]");
    if (!el) return;
    const action = el.dataset.action;
    if (action === "send-hero") chooseDeviceAndSend();
    else if (action === "send-peer") {
      const peer = state.peers.find((p) => p.fingerprint === el.dataset.fp);
      if (peer) pickFilesFor(peer);
    }
    else if (action === "save") saveFile(el.dataset.name);
    else if (action === "delete") deleteFile(el.dataset.name);
    else if (action === "clear-history") confirmClearHistory();
    else if (action === "settings") openSettings();
    else if (action === "refresh") {
      native("scanSubnet").catch(() => {});
      setTimeout(refreshPeers, 2500);
      toast({ type: "info", title: "Looking for devices…", message: "This takes a few seconds", duration: 2200 });
    }
  });

  $("#visible").addEventListener("change", (event) => setVisible(event.target.checked));
}

async function main() {
  wire();
  renderHeader();
  startPolling();
  if (state.visible) await startNode();
  else renderHeader();
  await Promise.all([refreshTransfers(), refreshPeers(), refreshInbox()]);
}

main();
