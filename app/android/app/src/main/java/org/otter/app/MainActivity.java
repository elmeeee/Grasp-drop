package org.otter.app;

import android.os.Bundle;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(OtterNativePlugin.class);
        super.onCreate(savedInstanceState);
    }
}
