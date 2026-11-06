// Manages the Otter Rust core sidecar process on Windows.
//
// The `otter.exe` binary is the same Rust core used on macOS/Linux/Android. It
// runs a LocalSend-compatible HTTPS server + discovery on the local machine, and
// the renderer talks to it through the plugin bridge exposed in preload.js.

const { spawn } = require("child_process");
const path = require("path");
const fs = require("fs");

let coreProcess = null;

function resolveBinary() {
  const candidates = [
    path.join(process.resourcesPath || "", "bin", "otter.exe"),
    path.join(__dirname, "..", "resources", "bin", "otter.exe"),
    path.join(__dirname, "..", "..", "..", "bin", "otter.exe"),
  ];
  return candidates.find((candidate) => candidate && fs.existsSync(candidate));
}

function startCore() {
  if (coreProcess) return;

  const binary = resolveBinary();
  if (!binary) {
    console.error("[Otter] Rust core binary not found; skipping sidecar launch");
    return;
  }

  coreProcess = spawn(binary, ["--name", "Otter"], {
    stdio: ["ignore", "pipe", "pipe"],
  });

  coreProcess.stdout.on("data", (data) =>
    process.stdout.write(`[otter] ${data}`)
  );
  coreProcess.stderr.on("data", (data) =>
    process.stderr.write(`[otter] ${data}`)
  );
  coreProcess.on("exit", (code) => {
    console.log(`[Otter] core exited with code ${code}`);
    coreProcess = null;
  });
}

function stopCore() {
  if (coreProcess) {
    coreProcess.kill();
    coreProcess = null;
  }
}

module.exports = { startCore, stopCore };
