#!/bin/bash
# 构建 CamStream APK（无需 Gradle）
set -e
SDK=${ANDROID_SDK:-/opt/android-sdk}
BT=$SDK/build-tools/34.0.0
PLAT=$SDK/platforms/android-30/android.jar
JAVAC=/usr/lib/jvm/java-17-openjdk-amd64/bin/javac
[ -x "$JAVAC" ] || JAVAC=javac
DIR=$(cd "$(dirname "$0")" && pwd)
cd "$DIR"

rm -rf build && mkdir -p build/classes build/dex
"$JAVAC" -source 8 -target 8 -bootclasspath "$PLAT" -d build/classes \
  $(find src -name '*.java')

"$BT/d8" --lib "$PLAT" --min-api 24 --output build/dex $(find build/classes -name '*.class')

mkdir -p build/res
"$BT/aapt2" compile --dir res -o build/res.zip
"$BT/aapt2" link -o build/app.unsigned.apk -I "$PLAT" \
  --manifest AndroidManifest.xml --min-sdk-version 24 --target-sdk-version 30 build/res.zip

( cd build && zip -q -j app.unsigned.apk dex/classes.dex )

"$BT/zipalign" -f 4 build/app.unsigned.apk build/app.aligned.apk

if [ ! -f debug.keystore ]; then
  keytool -genkeypair -keystore debug.keystore -alias androiddebugkey \
    -storepass android -keypass android -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi
"$BT/apksigner" sign --ks debug.keystore --ks-pass pass:android --key-pass pass:android \
  --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true \
  --out build/camstream.apk build/app.aligned.apk

echo "built: $DIR/build/camstream.apk"
