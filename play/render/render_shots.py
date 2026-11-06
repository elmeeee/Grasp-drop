import json, time
from playwright.sync_api import sync_playwright

BASE = "http://127.0.0.1:8765"
NOW = int(time.time() * 1000)

def tr(id_, direction, peer, name, total, done, status="done", ago_min=0, error=None):
    started = NOW - ago_min * 60000
    return {"id": id_, "direction": direction, "peer": peer, "file_name": name, "total": total,
            "done": done, "status": status, "started_at": started,
            "finished_at": None if status == "active" else started + 4000, "error": error}

SCENE = {
  "live": {
    "active": [
        tr("a1", "in", "Saldoo Macbook M4 Pro", "holiday_beach.mp4", 812000000, 519000000, "active"),
        tr("a2", "out", "Pixel 8", "vacation_photos.zip", 240000000, 96000000, "active"),
    ],
    "history": [
        tr("h1", "in", "Saldoo Macbook M4 Pro", "design_v3.pdf", 4200000, 4200000, ago_min=3),
        tr("h2", "out", "Pixel 8", "IMG_2041.heic", 3800000, 3800000, ago_min=11),
        tr("h3", "in", "Web browser", "notes.txt", 2048, 2048, ago_min=40),
    ],
    "inbox": [], "peers": [
        {"alias": "Saldoo Macbook M4 Pro", "ip": "192.168.1.20", "fingerprint": "f1", "deviceType": "desktop"},
        {"alias": "Pixel 8", "ip": "192.168.1.31", "fingerprint": "f2", "deviceType": "mobile"},
    ],
  },
  "inbox": {
    "active": [], "inbox": [
        {"name": "IMG_2044.jpg", "size": 2480000},
        {"name": "trip_video.mp4", "size": 118000000},
        {"name": "invoice_march.pdf", "size": 412000},
    ],
    "history": [
        tr("h1", "in", "Saldoo Macbook M4 Pro", "IMG_2044.jpg", 2480000, 2480000, ago_min=2),
        tr("h2", "in", "Pixel 8", "trip_video.mp4", 118000000, 118000000, ago_min=9),
        tr("h3", "out", "Saldoo Macbook M4 Pro", "invoice_march.pdf", 412000, 412000, ago_min=60),
    ],
    "peers": [{"alias": "Saldoo Macbook M4 Pro", "ip": "192.168.1.20", "fingerprint": "f1", "deviceType": "desktop"}],
  },
  "send": {
    "active": [], "inbox": [], "history": [], "peers": [
        {"alias": "Saldoo Macbook M4 Pro", "ip": "192.168.1.20", "fingerprint": "f1", "deviceType": "desktop"},
        {"alias": "Pixel 8", "ip": "192.168.1.31", "fingerprint": "f2", "deviceType": "mobile"},
        {"alias": "iPad Air", "ip": "192.168.1.44", "fingerprint": "f3", "deviceType": "mobile"},
    ],
  },
}
WEBHUB_URL = "http://192.168.1.50:7456"

def mock_js(scene):
    return """
    window.__S = %s;
    window.__S.webHub = %s;
    window.Capacitor = { Plugins: { OtterNative: {
      start: async () => ({ alias: 'Redmi 10 2022', running: true, webHub: window.__S.webHub }),
      stop: async () => ({}),
      getPeers: async () => ({ peers: window.__S.peers || [] }),
      getTransfers: async () => ({ active: window.__S.active || [], history: window.__S.history || [] }),
      getReceivedFiles: async () => ({ files: window.__S.inbox || [] }),
      getWebHub: async () => ({ url: window.__S.webHub }),
      scanSubnet: async () => ({}),
      sendFiles: async () => ({ sent: 1, total: 1 }),
      saveReceivedFile: async () => ({ savedTo: 'Pictures/Otter/IMG_2044.jpg' }),
      deleteReceivedFile: async () => ({}),
      clearHistory: async () => ({}),
    }}};
    """ % (json.dumps(scene), json.dumps(WEBHUB_URL))

def open_app(p, scene_key):
    browser = p.chromium.launch()
    ctx = browser.new_context(viewport={"width": 360, "height": 800}, device_scale_factor=3, color_scheme="dark")
    page = ctx.new_page()
    page.add_init_script(mock_js(SCENE[scene_key]))
    page.goto(f"{BASE}/app/www/index.html")
    page.wait_for_timeout(1500)
    return browser, page

def shot(page, name):
    page.screenshot(path=f"play/render/{name}.png")
    print("saved", name)

with sync_playwright() as p:
    # 1) Live activity: home with active transfers
    b, page = open_app(p, "live")
    page.evaluate("document.querySelector('#live-section').scrollIntoView({block:'start'}); window.scrollBy(0,-120)")
    page.wait_for_timeout(800); shot(page, "live")
    b.close()

    # 2) Inbox and history
    b, page = open_app(p, "inbox")
    page.wait_for_timeout(500)
    page.evaluate("document.querySelector('#inbox').scrollIntoView({block:'start'}); window.scrollBy(0,-170)")
    page.wait_for_timeout(800); shot(page, "inbox")
    b.close()

    # 3) Send sheet with several devices
    b, page = open_app(p, "send")
    page.click("[data-action=send-hero]")
    page.wait_for_timeout(700); shot(page, "send")
    b.close()

    # 4) Browser access card
    b, page = open_app(p, "live")
    page.evaluate("document.querySelector('#web-section').scrollIntoView({block:'start'}); window.scrollBy(0,-120)")
    page.wait_for_timeout(800); shot(page, "browser")
    b.close()

    # 5) Toast with Save action after receiving a photo
    b, page = open_app(p, "inbox")
    page.evaluate("window.scrollTo(0,0)")
    page.evaluate("toast({type:'success', title:'Received IMG_2044.jpg', message:'From Saldoo Macbook M4 Pro', duration:0, action:{label:'Save to Gallery', run: async()=>{}}})")
    page.wait_for_timeout(900); shot(page, "toast")
    b.close()

    # 6) Web hub page (the same HTML the Android app serves on port 7456)
    browser = p.chromium.launch()
    ctx = browser.new_context(viewport={"width": 360, "height": 800}, device_scale_factor=3, color_scheme="dark")
    page = ctx.new_page()
    page.route("**/api/files", lambda route: route.fulfill(status=200, content_type="application/json", body=json.dumps([
        {"name": "IMG_2044.jpg", "size": 2480000}, {"name": "trip_video.mp4", "size": 118000000}, {"name": "invoice_march.pdf", "size": 412000}])))
    page.goto(f"{BASE}/core/otter-core/src/webhub.html")
    page.wait_for_timeout(900); shot(page, "webhub")
    browser.close()
