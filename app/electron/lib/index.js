const { app, BrowserWindow } = require("electron");
const path = require("path");
const { startCore, stopCore } = require("./core");

let mainWindow = null;

async function createWindow() {
  mainWindow = new BrowserWindow({
    width: 520,
    height: 760,
    minWidth: 420,
    minHeight: 600,
    backgroundColor: "#0b0f19",
    title: "Grasp",
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  const webDir = path.join(__dirname, "..", "..", "www");
  await mainWindow.loadFile(path.join(webDir, "index.html"));
}

app.whenReady().then(async () => {
  // Launch the bundled Rust core sidecar (grasp.exe) so the renderer can reach
  // it over the same local API used on Android.
  startCore();
  await createWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", () => {
  stopCore();
  if (process.platform !== "darwin") app.quit();
});

app.on("before-quit", () => stopCore());
