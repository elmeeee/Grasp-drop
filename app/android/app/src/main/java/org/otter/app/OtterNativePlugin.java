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
import java.util.Base64;
import java.util.Locale;

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
    private static native String nativeSendFiles(long handle, String targetIp, int port, String filesJson);

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
        call.resolve(result);
    }

    @PluginMethod
    public void stop(PluginCall call) {
        if (nodeHandle != 0L) {
            nativeStop(nodeHandle);
            nodeHandle = 0L;
        }
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
        if (nodeHandle == 0L) {
            call.reject("Service not running");
            return;
        }
        String targetIp = call.getString("targetIp");
        Integer port = call.getInt("port", 53317);
        JSArray files = call.getArray("files");
        if (targetIp == null || files == null) {
            call.reject("Missing targetIp or files");
            return;
        }

        // Materialise each transferred file into the cache dir, then hand the
        // resulting paths to the Rust sender.
        JSArray paths = new JSArray();
        try {
            File cacheDir = getContext().getCacheDir();
            for (int index = 0; index < files.length(); index++) {
                org.json.JSONObject file = files.getJSONObject(index);
                String name = file.getString("name");
                String base64 = file.getString("base64");
                byte[] data = Base64.getDecoder().decode(base64);

                File target = new File(cacheDir, name);
                try (FileOutputStream output = new FileOutputStream(target)) {
                    output.write(data);
                }
                paths.put(target.getAbsolutePath());
            }
        } catch (Exception exception) {
            call.reject("Failed to stage files: " + exception.getMessage());
            return;
        }

        String resultJson = nativeSendFiles(nodeHandle, targetIp, port, paths.toString());
        try {
            call.resolve(new JSObject(resultJson));
        } catch (JSONException exception) {
            JSObject result = new JSObject();
            result.put("sent", 0);
            result.put("total", paths.length());
            call.resolve(result);
        }
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
