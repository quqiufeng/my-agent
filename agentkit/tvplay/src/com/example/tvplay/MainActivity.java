package com.example.tvplay;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.media.MediaPlayer;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.view.KeyEvent;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.View;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.TextView;

/**
 * tvplay — 极简全屏拉流播放器（系统 MediaPlayer / 硬件解码）。
 *
 * 用法：
 *   am start -n com.example.tvplay/.MainActivity -a android.intent.action.VIEW -d "http://host:port/a.mkv"
 *   或 -e url "http://..."   （也可用 SharedPreferences 记住上次地址）
 */
public class MainActivity extends Activity implements SurfaceHolder.Callback {
    private MediaPlayer mp;
    private SurfaceView surface;
    private TextView status;
    private String url;
    private boolean prepared = false;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        hideSystemUi();

        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);

        surface = new SurfaceView(this);
        surface.getHolder().addCallback(this);
        root.addView(surface, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));

        status = new TextView(this);
        status.setTextColor(Color.WHITE);
        status.setTextSize(22);
        status.setPadding(40, 40, 40, 40);
        root.addView(status, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT));

        setContentView(root);

        url = resolveUrl(getIntent());
        if (url == null) {
            status.setText("没有播放地址\n用 adb am start -d <url> 传入");
        } else {
            status.setText("加载中…\n" + url);
            getSharedPreferences("tvplay", 0).edit().putString("last", url).apply();
        }
    }

    private String resolveUrl(Intent it) {
        if (it != null) {
            Uri d = it.getData();
            if (d != null && d.toString().length() > 0) return d.toString();
            String e = it.getStringExtra("url");
            if (e != null && e.length() > 0) return e;
        }
        return getSharedPreferences("tvplay", 0).getString("last", null);
    }

    private void hideSystemUi() {
        getWindow().getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                        | View.SYSTEM_UI_FLAG_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
    }

    private void play() {
        if (url == null) return;
        release();
        try {
            mp = new MediaPlayer();
            mp.setDataSource(url);
            mp.setDisplay(surface.getHolder());
            mp.setOnPreparedListener(new MediaPlayer.OnPreparedListener() {
                public void onPrepared(MediaPlayer m) {
                    prepared = true;
                    status.setText("");
                    m.start();
                }
            });
            mp.setOnErrorListener(new MediaPlayer.OnErrorListener() {
                public boolean onError(MediaPlayer m, int what, int extra) {
                    prepared = false;
                    status.setText("播放失败 (" + what + "/" + extra + ")\n" + url);
                    release();
                    return true;
                }
            });
            mp.setOnCompletionListener(new MediaPlayer.OnCompletionListener() {
                public void onCompletion(MediaPlayer m) {
                    status.setText("播放结束");
                }
            });
            mp.setOnInfoListener(new MediaPlayer.OnInfoListener() {
                public boolean onInfo(MediaPlayer m, int what, int extra) {
                    if (what == MediaPlayer.MEDIA_INFO_BUFFERING_START) status.setText("缓冲中…");
                    else if (what == MediaPlayer.MEDIA_INFO_BUFFERING_END) status.setText("");
                    return false;
                }
            });
            mp.prepareAsync();
        } catch (Exception e) {
            status.setText("打不开: " + e.getMessage());
        }
    }

    private void release() {
        prepared = false;
        if (mp != null) {
            try { mp.reset(); mp.release(); } catch (Exception ignored) { }
            mp = null;
        }
    }

    @Override
    public void surfaceCreated(SurfaceHolder h) { }

    @Override
    public void surfaceChanged(SurfaceHolder h, int f, int w, int ht) {
        if (!prepared) play();
    }

    @Override
    public void surfaceDestroyed(SurfaceHolder h) { release(); }

    @Override
    protected void onNewIntent(Intent it) {
        super.onNewIntent(it);
        String u = resolveUrl(it);
        if (u != null && !u.equals(url)) {
            url = u;
            status.setText("加载中…\n" + url);
            play();
        }
    }

    @Override
    public boolean onKeyDown(int code, KeyEvent ev) {
        if (code == KeyEvent.KEYCODE_DPAD_CENTER || code == KeyEvent.KEYCODE_ENTER
                || code == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE) {
            if (mp != null) {
                if (mp.isPlaying()) mp.pause(); else mp.start();
            }
            return true;
        }
        if (code == KeyEvent.KEYCODE_BACK) {
            finish();
            return true;
        }
        return super.onKeyDown(code, ev);
    }

    @Override
    protected void onPause() {
        super.onPause();
        if (mp != null && mp.isPlaying()) mp.pause();
    }

    @Override
    protected void onDestroy() {
        release();
        super.onDestroy();
    }
}
