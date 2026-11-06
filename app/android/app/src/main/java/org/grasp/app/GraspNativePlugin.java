package org.grasp.app;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import android.content.Intent;
import android.os.Build;

import org.json.JSONException;

import java.io.File;
import java.io.FileOutputStream;
import java.util.Base64;

/**
 * Bridges the Grasp Rust core (server + discovery + sender) to the WebView.
 *
 * <p>The Rust core is built as a shared library ({@code libgrasp_core.so}) and
 * loaded through the JNI functions declared in {@code grasp_core.h}. The native
 * node keeps running in its own threads while the plugin polls for state.
 */
@CapacitorPlugin(name = "GraspNative")
public class GraspNativePlugin extends Plugin {

    static {
        System.loadLibrary("grasp_core");
    }

    private long nodeHandle = 0L;

    // Native functions implemented in the Rust core (see grasp-core/src/jni.rs).
    private static native long nativeStart(String alias, String stateDir, String filesDir);
    private static native void nativeStop(long handle);
    private static native String nativeFingerprint(long handle);
    private static native String nativePeers(long handle);
    private static native void nativeScanSubnet(long handle);
    private static native String nativeSendFiles(long handle, String targetIp, int port, String filesJson);

    @PluginMethod
    public void start(PluginCall call) {
        String alias = call.getString("alias", "Grasp Device");
        String baseDir = getContext().getFilesDir().getAbsolutePath();
        String stateDir = baseDir + "/.grasp";
        String filesDir = baseDir + "/received";

        new File(stateDir).mkdirs();
        new File(filesDir).mkdirs();

        if (nodeHandle != 0L) {
            nativeStop(nodeHandle);
        }
        nodeHandle = nativeStart(alias, stateDir, filesDir);

        // Keep the node alive when the app is backgrounded.
        Intent serviceIntent = new Intent(getContext(), GraspForegroundService.class);
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
        getContext().stopService(new Intent(getContext(), GraspForegroundService.class));
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
        File dir = new File(getContext().getFilesDir().getAbsolutePath() + "/received");
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
}
