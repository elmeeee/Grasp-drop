package org.otter.app;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Intent;
import android.media.MediaScannerConnection;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import android.provider.Settings;
import android.webkit.MimeTypeMap;

import org.json.JSONException;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.util.Base64;
import java.util.Collections;
import java.util.Locale;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

import android.app.Notification;
import android.app.NotificationManager;
import org.json.JSONArray;
import org.json.JSONObject;

/**
 * Bridges the Otter Rust core (server + discovery + sender) to the WebView.
 *
 * <p>The Rust core is built as a shared library ({@code libotter_core.so}) and
 * loaded through the JNI functions declared in {@code otter_core.h}. The native
 * node keeps running in its own threads while the plugin polls for state.
 */
@CapacitorPlugin(name = "OtterNative")
public class OtterNativePlugin extends Plugin {

    static {
        System.loadLibrary("otter_core");
    }

    private long nodeHandle = 0L;

    // Native functions implemented in the Rust core (see otter-core/src/jni.rs).
    private static native long nativeStart(String alias, String stateDir, String filesDir);
    private static native void nativeStop(long handle);
    private static native String nativeFingerprint(long handle);
    private static native String nativePeers(long handle);
    private static native void nativeScanSubnet(long handle);
    private static native String nativeSendFiles(long handle, String targetIp, String peerName, int port, String filesJson);
    private static native String nativeTransfers();
    private static native String nativeStartWebHub(long handle, String localIp);
    private static native void nativeStopWebHub(long handle);
    private static native void nativeClearHistory();

    /** Pushes live transfer progress into the foreground-service notification. */
    private ScheduledExecutorService notifier;
    private boolean notificationBusy = false;

    @PluginMethod
    public void start(PluginCall call) {
        String alias = call.getString("alias");
        if (alias == null || alias.trim().isEmpty()) {
            alias = deviceName();
        }
        String baseDir = getContext().getFilesDir().getAbsolutePath();
        String stateDir = baseDir + "/.otter";
        String filesDir = baseDir + "/received";

        new File(stateDir).mkdirs();
        new File(filesDir).mkdirs();

        if (nodeHandle != 0L) {
            nativeStop(nodeHandle);
        }
        nodeHandle = nativeStart(alias, stateDir, filesDir);

        startNotificationLoop();

        // Keep the node alive when the app is backgrounded.
        Intent serviceIntent = new Intent(getContext(), OtterForegroundService.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getContext().startForegroundService(serviceIntent);
        } else {
            getContext().startService(serviceIntent);
        }

        JSObject result = new JSObject();
        result.put("alias", alias);
        result.put("fingerprint", nodeHandle != 0L ? nativeFingerprint(nodeHandle) : "");
        result.put("running", nodeHandle != 0L);
        result.put("webHub", webHubUrl());
        call.resolve(result);
    }

    /** Address of the browser web hub, e.g. http://192.168.1.20:7456. Empty when unavailable. */
    @PluginMethod
    public void getWebHub(PluginCall call) {
        JSObject result = new JSObject();
        result.put("url", webHubUrl());
        call.resolve(result);
    }

    private String webHubUrl() {
        if (nodeHandle == 0L) {
            return "";
        }
        String ip = wifiIPv4();
        if (ip == null) {
            return "";
        }
        String url = nativeStartWebHub(nodeHandle, ip);
        return url == null ? "" : url;
    }

    /** The phone's IPv4 address on Wi-Fi (wlan*), falling back to any other LAN address. */
    private String wifiIPv4() {
        try {
            String fallback = null;
            for (NetworkInterface network : Collections.list(NetworkInterface.getNetworkInterfaces())) {
                if (!network.isUp() || network.isLoopback()) {
                    continue;
                }
                for (InetAddress address : Collections.list(network.getInetAddresses())) {
                    if (address instanceof Inet4Address && !address.isLoopbackAddress()) {
                        String ip = address.getHostAddress();
                        if (network.getName() != null && network.getName().startsWith("wlan")) {
                            return ip;
                        }
                        if (fallback == null) {
                            fallback = ip;
                        }
                    }
                }
            }
            return fallback;
        } catch (Exception exception) {
            return null;
        }
    }

    @PluginMethod
    public void stop(PluginCall call) {
        if (nodeHandle != 0L) {
            nativeStopWebHub(nodeHandle);
            nativeStop(nodeHandle);
            nodeHandle = 0L;
        }
        stopNotificationLoop();
        getContext().stopService(new Intent(getContext(), OtterForegroundService.class));
        call.resolve();
    }

    @PluginMethod
    public void getPeers(PluginCall call) {
        JSObject result = new JSObject();
        if (nodeHandle == 0L) {
            result.put("peers", new JSArray());
            call.resolve(result);
            return;
        }
        try {
            result.put("peers", new JSArray(nativePeers(nodeHandle)));
        } catch (JSONException exception) {
            result.put("peers", new JSArray());
        }
        call.resolve(result);
    }

    @PluginMethod
    public void scanSubnet(PluginCall call) {
        if (nodeHandle != 0L) {
            nativeScanSubnet(nodeHandle);
        }
        call.resolve();
    }

    @PluginMethod
    public void getReceivedFiles(PluginCall call) {
        JSObject result = new JSObject();
        JSArray files = new JSArray();
        File dir = receivedDir();
        File[] entries = dir.listFiles();
        if (entries != null) {
            for (File file : entries) {
                if (!file.isFile() || file.getName().startsWith(".")) {
                    continue;
                }
                JSObject item = new JSObject();
                item.put("name", file.getName());
                item.put("size", file.length());
                files.put(item);
            }
        }
        result.put("files", files);
        call.resolve(result);
    }

    @PluginMethod
    public void sendFiles(PluginCall call) {
        final long handle = nodeHandle;
        if (handle == 0L) {
            call.reject("Service not running");
            return;
        }
        final String targetIp = call.getString("targetIp");
        final String peerName = call.getString("peerName", targetIp);
        final Integer port = call.getInt("port", 53317);
        final JSArray files = call.getArray("files");
        if (targetIp == null || files == null) {
            call.reject("Missing targetIp or files");
            return;
        }

        new Thread(() -> {
            try {
                // Stage each file in the cache dir, then hand the paths to the Rust sender.
                JSArray paths = new JSArray();
                File cacheDir = getContext().getCacheDir();
                for (int index = 0; index < files.length(); index++) {
                    org.json.JSONObject file = files.getJSONObject(index);
                    String name = file.getString("name");
                    byte[] data = Base64.getDecoder().decode(file.getString("base64"));
                    File target = new File(cacheDir, name);
                    try (FileOutputStream output = new FileOutputStream(target)) {
                        output.write(data);
                    }
                    paths.put(target.getAbsolutePath());
                }

                String resultJson = nativeSendFiles(handle, targetIp, peerName, port, paths.toString());
                JSObject result = new JSObject(resultJson);
                call.resolve(result);
            } catch (Exception exception) {
                call.reject("Send failed: " + exception.getMessage());
            }
        }, "otter-send").start();
    }

    /** Active transfers and history, straight from the Rust core. */
    @PluginMethod
    public void getTransfers(PluginCall call) {
        JSObject result = new JSObject();
        try {
            JSObject snapshot = new JSObject(nativeTransfers());
            result.put("active", snapshot.optJSONArray("active") != null ? snapshot.getJSONArray("active") : new JSArray());
            result.put("history", snapshot.optJSONArray("history") != null ? snapshot.getJSONArray("history") : new JSArray());
        } catch (JSONException exception) {
            result.put("active", new JSArray());
            result.put("history", new JSArray());
        }
        call.resolve(result);
    }

    @PluginMethod
    public void clearHistory(PluginCall call) {
        nativeClearHistory();
        call.resolve();
    }

    /** Removes a received file that has not been saved yet. */
    @PluginMethod
    public void deleteReceivedFile(PluginCall call) {
        String name = call.getString("name");
        if (name == null || name.isEmpty() || name.contains("/") || name.startsWith(".")) {
            call.reject("Invalid file name");
            return;
        }
        File file = new File(receivedDir(), name);
        if (file.isFile() && !file.delete()) {
            call.reject("Could not delete file");
            return;
        }
        call.resolve();
    }

    /** Starts the 700 ms loop that mirrors active transfers into the notification. */
    private void startNotificationLoop() {
        stopNotificationLoop();
        notifier = Executors.newSingleThreadScheduledExecutor();
        notifier.scheduleAtFixedRate(this::refreshNotification, 0, 700, TimeUnit.MILLISECONDS);
    }

    private void stopNotificationLoop() {
        if (notifier != null) {
            notifier.shutdownNow();
            notifier = null;
        }
    }

    private void refreshNotification() {
        try {
            if (nodeHandle == 0L) {
                return;
            }
            NotificationManager manager = getContext().getSystemService(NotificationManager.class);
            if (manager == null) {
                return;
            }
            JSONArray active = new JSONObject(nativeTransfers()).optJSONArray("active");
            if (active == null || active.length() == 0) {
                if (notificationBusy) {
                    manager.notify(OtterForegroundService.NOTIFICATION_ID,
                            idleNotification("Visible on your network"));
                    notificationBusy = false;
                }
                return;
            }

            long total = 0;
            long done = 0;
            boolean sending = false;
            String firstName = "";
            for (int index = 0; index < active.length(); index++) {
                JSONObject item = active.getJSONObject(index);
                total += item.optLong("total", 0);
                done += item.optLong("done", 0);
                if ("out".equals(item.optString("direction"))) {
                    sending = true;
                }
                if (index == 0) {
                    firstName = item.optString("file_name", "");
                }
            }
            int percent = total > 0 ? (int) (done * 100 / total) : 0;
            String title = (sending ? "Sending " : "Receiving ")
                    + (active.length() == 1 ? firstName : active.length() + " files");
            String text = percent + "%  ·  " + formatBytes(done) + " of " + formatBytes(total);

            Notification notification = OtterForegroundService.builderFor(getContext())
                    .setContentTitle(title)
                    .setContentText(text)
                    .setSmallIcon(android.R.drawable.stat_sys_upload)
                    .setProgress(100, percent, false)
                    .setOngoing(true)
                    .setOnlyAlertOnce(true)
                    .build();
            manager.notify(OtterForegroundService.NOTIFICATION_ID, notification);
            notificationBusy = true;
        } catch (Exception ignored) {
            // Notification updates are best-effort; the transfer itself is unaffected.
        }
    }

    private Notification idleNotification(String text) {
        return OtterForegroundService.builderFor(getContext())
                .setContentTitle("Otter")
                .setContentText(text)
                .setSmallIcon(android.R.drawable.stat_sys_upload)
                .setOngoing(true)
                .build();
    }

    private static String formatBytes(long bytes) {
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1024L * 1024) return String.format(Locale.US, "%.1f KB", bytes / 1024.0);
        if (bytes < 1024L * 1024 * 1024) return String.format(Locale.US, "%.1f MB", bytes / (1024.0 * 1024));
        return String.format(Locale.US, "%.2f GB", bytes / (1024.0 * 1024 * 1024));
    }

    /** Saves a received file into the shared media collections so it shows up in Gallery/Files. */
    @PluginMethod
    public void saveReceivedFile(PluginCall call) {
        String name = call.getString("name");
        if (name == null || name.isEmpty() || name.contains("/") || name.contains("\\") || name.startsWith(".")) {
            call.reject("Invalid file name");
            return;
        }
        File source = new File(receivedDir(), name);
        if (!source.isFile()) {
            call.reject("File no longer exists");
            return;
        }
        try {
            String savedTo = saveToSharedStorage(source);
            // The copy in Gallery/Downloads is now the file the user keeps.
            source.delete();
            JSObject result = new JSObject();
            result.put("savedTo", savedTo);
            call.resolve(result);
        } catch (Exception exception) {
            call.reject("Save failed: " + exception.getMessage());
        }
    }

    private File receivedDir() {
        return new File(getContext().getFilesDir().getAbsolutePath() + "/received");
    }

    /**
     * Writes the file into MediaStore (API 29+). Images go to Pictures/Otter so they
     * appear in Gallery, videos to Movies/Otter, audio to Music/Otter, everything
     * else to Download/Otter. Older Android versions get a plain copy plus a media scan.
     */
    private String saveToSharedStorage(File source) throws IOException {
        String mime = mimeFor(source.getName());
        ContentResolver resolver = getContext().getContentResolver();

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            Uri collection;
            String folder;
            if (mime.startsWith("image/")) {
                collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI;
                folder = Environment.DIRECTORY_PICTURES;
            } else if (mime.startsWith("video/")) {
                collection = MediaStore.Video.Media.EXTERNAL_CONTENT_URI;
                folder = Environment.DIRECTORY_MOVIES;
            } else if (mime.startsWith("audio/")) {
                collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI;
                folder = Environment.DIRECTORY_MUSIC;
            } else {
                collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI;
                folder = Environment.DIRECTORY_DOWNLOADS;
            }
            String relativePath = folder + "/Otter";

            ContentValues values = new ContentValues();
            values.put(MediaStore.MediaColumns.DISPLAY_NAME, source.getName());
            values.put(MediaStore.MediaColumns.MIME_TYPE, mime);
            values.put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath);
            values.put(MediaStore.MediaColumns.IS_PENDING, 1);

            Uri uri = resolver.insert(collection, values);
            if (uri == null) {
                throw new IOException("MediaStore insert returned null");
            }
            try (InputStream input = new FileInputStream(source);
                 OutputStream output = resolver.openOutputStream(uri)) {
                if (output == null) {
                    throw new IOException("Cannot open output stream");
                }
                copy(input, output);
            } catch (IOException exception) {
                resolver.delete(uri, null, null);
                throw exception;
            }

            ContentValues done = new ContentValues();
            done.put(MediaStore.MediaColumns.IS_PENDING, 0);
            resolver.update(uri, done, null, null);
            return relativePath + "/" + source.getName();
        }

        // Android 8 and older: public directory + media scanner.
        String folder = mime.startsWith("image/") ? Environment.DIRECTORY_PICTURES
                : mime.startsWith("video/") ? Environment.DIRECTORY_MOVIES
                : mime.startsWith("audio/") ? Environment.DIRECTORY_MUSIC
                : Environment.DIRECTORY_DOWNLOADS;
        File dir = new File(Environment.getExternalStoragePublicDirectory(folder), "Otter");
        if (!dir.exists() && !dir.mkdirs()) {
            throw new IOException("Cannot create " + dir.getAbsolutePath());
        }
        File target = uniqueFile(dir, source.getName());
        try (InputStream input = new FileInputStream(source);
             OutputStream output = new FileOutputStream(target)) {
            copy(input, output);
        }
        MediaScannerConnection.scanFile(getContext(), new String[]{target.getAbsolutePath()},
                new String[]{mime}, null);
        return target.getAbsolutePath();
    }

    private static void copy(InputStream input, OutputStream output) throws IOException {
        byte[] buffer = new byte[64 * 1024];
        int read;
        while ((read = input.read(buffer)) != -1) {
            output.write(buffer, 0, read);
        }
    }

    private static File uniqueFile(File dir, String name) {
        File candidate = new File(dir, name);
        if (!candidate.exists()) {
            return candidate;
        }
        int dot = name.lastIndexOf('.');
        String stem = dot > 0 ? name.substring(0, dot) : name;
        String ext = dot > 0 ? name.substring(dot) : "";
        for (int index = 1; index < 10_000; index++) {
            candidate = new File(dir, stem + " (" + index + ")" + ext);
            if (!candidate.exists()) {
                return candidate;
            }
        }
        return candidate;
    }

    private String mimeFor(String name) {
        int dot = name.lastIndexOf('.');
        if (dot < 0) {
            return "application/octet-stream";
        }
        String ext = name.substring(dot + 1).toLowerCase(Locale.ROOT);
        String mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext);
        return mime != null ? mime : "application/octet-stream";
    }

    /** The phone's own name, e.g. "Xiaomi 21121119SG", as shown in Settings > About. */
    private String deviceName() {
        String name = null;
        try {
            name = Settings.Global.getString(getContext().getContentResolver(), Settings.Global.DEVICE_NAME);
        } catch (Exception ignored) {
            // Not readable on this device; fall back below.
        }
        if (name == null || name.trim().isEmpty()) {
            String maker = Build.MANUFACTURER == null ? "" : Build.MANUFACTURER.trim();
            if (!maker.isEmpty()) {
                maker = Character.toUpperCase(maker.charAt(0)) + maker.substring(1);
            }
            name = (maker + " " + Build.MODEL).trim();
        }
        return name;
    }
}
