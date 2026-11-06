// Manages the Grasp Rust core sidecar process on Windows.
//
// The `grasp.exe` binary is the same Rust core used on macOS/Linux/Android. It
// runs a LocalSend-compatible HTTPS server + discovery on the local machine, and
// the renderer talks to it through the plugin bridge exposed in preload.js.

const { spawn } = require("child_process");
const path = require("path");
const fs = require("fs");

let coreProcess = null;

function resolveBinary() {
  const candidates = [
    path.join(process.resourcesPath || "", "bin", "grasp.exe"),
    path.join(__dirname, "..", "resources", "bin", "grasp.exe"),
    path.join(__dirname, "..", "..", "..", "bin", "grasp.exe"),
  ];
  return candidates.find((candidate) => candidate && fs.existsSync(candidate));
}

function startCore() {
  if (coreProcess) return;

  const binary = resolveBinary();
  if (!binary) {
    console.error("[Grasp] Rust core binary not found; skipping sidecar launch");
    return;
  }

  coreProcess = spawn(binary, ["--name", "Grasp"], {
    stdio: ["ignore", "pipe", "pipe"],
  });

  coreProcess.stdout.on("data", (data) =>
    process.stdout.write(`[grasp] ${data}`)
  );
  coreProcess.stderr.on("data", (data) =>
    process.stderr.write(`[grasp] ${data}`)
  );
  coreProcess.on("exit", (code) => {
    console.log(`[Grasp] core exited with code ${code}`);
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
