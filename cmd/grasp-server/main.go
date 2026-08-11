package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"
)

type FileItem struct {
	Name string `json:"name"`
	Size int64  `json:"size"`
	Date int64  `json:"date"`
}

var (
	clipboardLock    sync.Mutex
	currentClipboard string
)

func main() {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		homeDir = "."
	}
	downloadDir := filepath.Join(homeDir, "Downloads", "Grasp")
	os.MkdirAll(downloadDir, 0755)

	ip := getLocalIP()
	port := "7456"
	serverURL := fmt.Sprintf("http://%s:%s", ip, port)

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/" && r.Method == "GET" {
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			w.Write([]byte(getWebHTML()))
			return
		}
		if r.URL.Path == "/api/files" && r.Method == "GET" {
			handleFileList(w, r, downloadDir)
			return
		}
		if r.URL.Path == "/api/clipboard" {
			handleClipboard(w, r)
			return
		}
		if strings.HasPrefix(r.URL.Path, "/download/") && r.Method == "GET" {
			filename := strings.TrimPrefix(r.URL.Path, "/download/")
			handleFileDownload(w, r, downloadDir, filename)
			return
		}
		if r.URL.Path == "/upload" && r.Method == "POST" {
			handleFileUpload(w, r, downloadDir)
			return
		}
		http.NotFound(w, r)
	})

	fmt.Println("==================================================")
	fmt.Println("   GRASP STANDALONE SERVER (WINDOWS & LINUX)")
	fmt.Println("==================================================")
	fmt.Printf("   Save Folder : %s\n", downloadDir)
	fmt.Printf("   Web Hub URL : %s\n", serverURL)
	fmt.Println("--------------------------------------------------")
	fmt.Println("   Android & iPhone: Scan QR or open URL in browser")
	fmt.Println("   Windows & Linux: Upload & download files from URL")
	fmt.Println("==================================================")

	// Auto open browser on local machine
	go func() {
		time.Sleep(1 * time.Second)
		openBrowser(fmt.Sprintf("http://localhost:%s", port))
	}()

	err = http.ListenAndServe(":"+port, nil)
	if err != nil {
		fmt.Printf("Error starting server: %v\n", err)
	}
}

func getLocalIP() string {
	addrs, err := net.InterfaceAddrs()
	if err != nil {
		return "127.0.0.1"
	}
	for _, addr := range addrs {
		if ipnet, ok := addr.(*net.IPNet); ok && !ipnet.IP.IsLoopback() {
			if ipnet.IP.To4() != nil {
				return ipnet.IP.String()
			}
		}
	}
	return "127.0.0.1"
}

func handleClipboard(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	if r.Method == "GET" {
		clipboardLock.Lock()
		text := currentClipboard
		clipboardLock.Unlock()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"text": text})
		return
	}
	if r.Method == "POST" {
		body, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, "Read error", http.StatusBadRequest)
			return
		}
		clipboardLock.Lock()
		currentClipboard = string(body)
		clipboardLock.Unlock()
		fmt.Printf("[Clipboard Synced] %s\n", string(body))
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
		return
	}
	http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
}

func handleFileList(w http.ResponseWriter, r *http.Request, downloadDir string) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")

	entries, err := os.ReadDir(downloadDir)
	if err != nil {
		json.NewEncoder(w).Encode([]FileItem{})
		return
	}

	var files []FileItem
	for _, entry := range entries {
		if entry.IsDir() || strings.HasPrefix(entry.Name(), ".") {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			continue
		}
		files = append(files, FileItem{
			Name: entry.Name(),
			Size: info.Size(),
			Date: info.ModTime().Unix(),
		})
	}

	sort.Slice(files, func(i, j int) bool {
		return files[i].Date > files[j].Date
	})

	json.NewEncoder(w).Encode(files)
}

func handleFileDownload(w http.ResponseWriter, r *http.Request, downloadDir string, filename string) {
	cleanName := filepath.Base(filename)
	filePath := filepath.Join(downloadDir, cleanName)

	file, err := os.Open(filePath)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	defer file.Close()

	w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=\"%s\"", cleanName))
	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	io.Copy(w, file)
}

func handleFileUpload(w http.ResponseWriter, r *http.Request, downloadDir string) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	r.ParseMultipartForm(500 << 20) // 500 MB max memory

	file, handler, err := r.FormFile("file")
	if err != nil {
		http.Error(w, "Upload Error", http.StatusBadRequest)
		return
	}
	defer file.Close()

	filename := filepath.Base(handler.Filename)
	targetPath := filepath.Join(downloadDir, filename)

	dst, err := os.Create(targetPath)
	if err != nil {
		http.Error(w, "Write Error", http.StatusInternalServerError)
		return
	}
	defer dst.Close()

	_, err = io.Copy(dst, file)
	if err != nil {
		http.Error(w, "Save Error", http.StatusInternalServerError)
		return
	}

	fmt.Printf("[Received File] Saved: %s (%d bytes)\n", filename, handler.Size)
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
}

func openBrowser(url string) {
	var cmd string
	var args []string

	switch runtime.GOOS {
	case "windows":
		cmd = "cmd"
		args = []string{"/c", "start", url}
	case "darwin":
		cmd = "open"
		args = []string{url}
	default: // linux
		cmd = "xdg-open"
		args = []string{url}
	}
	exec.Command(cmd, args...).Start()
}

func getWebHTML() string {
	return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Grasp — Cross-Platform File Hub & Clipboard Sync</title>
    <style>
        :root { --bg: #0b0f19; --card: #151c2c; --primary: #4f46e5; --accent: #06b6d4; --text: #f8fafc; --muted: #94a3b8; }
        * { box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: var(--bg); color: var(--text); display: flex; flex-direction: column; align-items: center; min-height: 100vh; margin: 0; padding: 24px 16px; }
        .container { max-width: 520px; width: 100%; display: flex; flex-direction: column; gap: 20px; }
        .card { background: var(--card); border-radius: 20px; padding: 24px; border: 1px solid rgba(255,255,255,0.08); box-shadow: 0 15px 30px rgba(0,0,0,0.4); }
        .header { text-align: center; }
        .logo-bar { width: 56px; height: 56px; display: inline-flex; align-items: center; justify-content: center; margin-bottom: 10px; filter: drop-shadow(0 4px 12px rgba(79,70,229,0.4)); }
        .logo-bar svg { width: 48px; height: 48px; }
        h1 { font-size: 20px; margin: 0 0 4px; font-weight: 700; }
        p { color: var(--muted); font-size: 13px; margin: 0; }
        .drop-zone { border: 2px dashed rgba(6,182,212,0.4); border-radius: 16px; padding: 28px 16px; background: rgba(6,182,212,0.03); cursor: pointer; text-align: center; transition: all 0.2s; }
        .drop-zone:hover { background: rgba(6,182,212,0.08); border-color: var(--accent); }
        .btn { background: linear-gradient(135deg, var(--primary), var(--accent)); color: white; border: none; padding: 10px 20px; border-radius: 10px; font-size: 13px; font-weight: 600; cursor: pointer; margin-top: 10px; }
        input[type="file"] { display: none; }
        .status { margin-top: 12px; font-size: 13px; color: #22c55e; font-weight: 600; text-align: center; }
        .section-title { font-size: 14px; font-weight: 700; margin-bottom: 12px; display: flex; justify-content: space-between; align-items: center; }
        .file-list { display: flex; flex-direction: column; gap: 8px; max-height: 220px; overflow-y: auto; }
        .file-item { display: flex; align-items: center; justify-content: space-between; padding: 10px 14px; background: rgba(255,255,255,0.04); border-radius: 12px; border: 1px solid rgba(255,255,255,0.05); }
        .file-info { display: flex; flex-direction: column; gap: 2px; }
        .file-name { font-size: 13px; font-weight: 600; word-break: break-all; }
        .file-meta { font-size: 11px; color: var(--muted); }
        .dl-btn { background: rgba(255,255,255,0.1); color: white; text-decoration: none; padding: 6px 12px; border-radius: 8px; font-size: 12px; font-weight: 600; transition: background 0.2s; }
        .dl-btn:hover { background: var(--accent); }
        textarea { width: 100%; height: 90px; background: rgba(0,0,0,0.3); border: 1px solid rgba(255,255,255,0.1); border-radius: 12px; padding: 12px; color: white; font-family: inherit; font-size: 13px; resize: none; margin-bottom: 8px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="card header">
            <div class="logo-bar">
                <svg width="48" height="48" viewBox="0 0 24 24" fill="none">
                    <defs>
                        <linearGradient id="barGrad" x1="0" y1="0" x2="24" y2="24" gradientUnits="userSpaceOnUse">
                            <stop offset="0%" stop-color="#4f46e5"/>
                            <stop offset="100%" stop-color="#06b6d4"/>
                        </linearGradient>
                    </defs>
                    <path d="M 13.5 7.5 C 16.538 7.5 19 9.962 19 13 C 19 16.038 16.538 18.5 13.5 18.5 C 10.462 18.5 8 16.038 8 13 M 8 13 L 15 13" stroke="url(#barGrad)" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>
                    <path d="M 10.5 16.5 C 7.462 16.5 5 14.038 5 11 C 5 7.962 7.462 5.5 10.5 5.5 C 13.538 5.5 16 7.962 16 11" stroke="#06b6d4" stroke-opacity="0.6" stroke-width="2.2" stroke-linecap="round"/>
                </svg>
            </div>
            <h1>Grasp File Hub & Clipboard</h1>
            <p>Cross-Platform File Transfer & Text Sync</p>
        </div>

        <div class="card">
            <div class="section-title">📋 Clipboard Text & Links Sync</div>
            <textarea id="clipText" placeholder="Paste text or links here to send to Mac clipboard..."></textarea>
            <button class="btn" onclick="sendClipboard()" style="width: 100%;">Sync Text to Clipboard</button>
            <div class="status" id="cs"></div>
        </div>

        <div class="card">
            <div class="section-title">📤 Upload Files</div>
            <div class="drop-zone" onclick="document.getElementById('f').click()">
                <div style="font-size: 14px; font-weight: 600; margin-bottom: 4px;">Click or Drag Files Here</div>
                <div style="font-size: 12px; color: var(--muted);">Supports photos, videos, documents & archives</div>
                <button class="btn" type="button">Choose Files</button>
                <input type="file" id="f" multiple onchange="upload(this.files)">
            </div>
            <div class="status" id="s"></div>
        </div>

        <div class="card">
            <div class="section-title">
                <span>📥 Received / Shared Files</span>
                <span style="font-size: 11px; color: var(--muted);" id="file-count">Loading...</span>
            </div>
            <div class="file-list" id="fl">
                <div style="text-align: center; color: var(--muted); font-size: 12px; padding: 12px;">Fetching files...</div>
            </div>
        </div>
    </div>

    <script>
        function sendClipboard() {
            const txt = document.getElementById('clipText').value;
            if (!txt) return;
            const cs = document.getElementById('cs');
            cs.innerText = "Syncing clipboard...";
            fetch('/api/clipboard', { method: 'POST', body: txt })
                .then(r => {
                    if (r.ok) cs.innerText = "✓ Clipboard Synced Successfully!";
                    else cs.innerText = "✕ Sync Failed!";
                })
                .catch(e => cs.innerText = "✕ Error: " + e);
        }

        function upload(files) {
            if (!files || files.length === 0) return;
            const status = document.getElementById('s');
            let completed = 0;
            const total = files.length;
            
            function processNext(index) {
                if (index >= total) {
                    status.innerText = "✓ All " + total + " Files Uploaded!";
                    loadFiles();
                    return;
                }
                const f = files[index];
                status.innerText = "Uploading (" + (index + 1) + "/" + total + "): " + f.name;
                const formData = new FormData();
                formData.append('file', f);
                fetch('/upload', { method: 'POST', body: formData })
                    .then(res => {
                        if (res.ok) processNext(index + 1);
                        else status.innerText = "✕ Failed at file: " + f.name;
                    })
                    .catch(err => status.innerText = "✕ Upload Error: " + err);
            }
            processNext(0);
        }

        function formatSize(bytes) {
            if (bytes < 1024) return bytes + ' B';
            if (bytes < 1048576) return (bytes / 1024).toFixed(1) + ' KB';
            return (bytes / 1048576).toFixed(1) + ' MB';
        }

        function loadFiles() {
            fetch('/api/files')
                .then(r => r.json())
                .then(files => {
                    const fl = document.getElementById('fl');
                    const count = document.getElementById('file-count');
                    count.innerText = files.length + " files";
                    if (files.length === 0) {
                        fl.innerHTML = '<div style="text-align: center; color: var(--muted); font-size: 12px; padding: 12px;">No files available yet.</div>';
                        return;
                    }
                    fl.innerHTML = files.map(function(f) {
                        return '<div class="file-item">' +
                            '<div class="file-info">' +
                                '<div class="file-name">' + f.name + '</div>' +
                                '<div class="file-meta">' + formatSize(f.size) + '</div>' +
                            '</div>' +
                            '<a class="dl-btn" href="/download/' + encodeURIComponent(f.name) + '" download="' + f.name + '">Download</a>' +
                        '</div>';
                    }).join('');
                })
                .catch(e => console.error(e));
        }

        loadFiles();
        setInterval(loadFiles, 5000);
    </script>
</body>
</html>`
}
