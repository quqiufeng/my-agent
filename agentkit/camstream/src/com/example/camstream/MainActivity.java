package com.example.camstream;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.widget.TextView;

public class MainActivity extends Activity {
    private static final int REQ = 1;
    private TextView tv;

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        tv = new TextView(this);
        tv.setTextSize(18);
        tv.setPadding(40, 80, 40, 40);
        setContentView(tv);
        tv.setText("CamStream\n\n启动中…\n\n启动后：\n  视频 http://<手机IP>:8080/video\n  音频 http://<手机IP>:8080/audio\n");
        if (Build.VERSION.SDK_INT >= 23 &&
            (checkSelfPermission(android.Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED ||
             checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED)) {
            requestPermissions(new String[]{
                android.Manifest.permission.CAMERA,
                android.Manifest.permission.RECORD_AUDIO}, REQ);
        } else {
            start();
        }
    }

    private void start() {
        Intent i = new Intent(this, StreamService.class);
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(i); else startService(i);
    }

    @Override public void onRequestPermissionsResult(int r, String[] p, int[] g) { start(); }
}
