package com.example.tvplay;

/** JNI 包装：C 内核（NDK MediaCodec + AAudio）。 */
public class NativePlayer {
    static {
        System.loadLibrary("native_player");
    }

    public static native int nativeInit(Object surface, String url);

    public static native void nativePause(boolean on);

    public static native void nativeSeek(long positionMs);

    public static native long nativePosition();

    public static native void nativeStop();
}
