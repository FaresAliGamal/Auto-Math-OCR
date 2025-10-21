#!/usr/bin/env bash
set -euo pipefail

echo "==> Android SDK setup + Build (fixed cmdline-tools path)"

export ANDROID_SDK_ROOT="$HOME/android-sdk"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
cd "$ANDROID_SDK_ROOT/cmdline-tools"

if [ ! -d "latest" ]; then
echo "==> Downloading cmdline-tools..."
curl -L -o cmdtools.zip "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
mkdir -p latest
unzip -q cmdtools.zip -d latest
rm -f cmdtools.zip
fi

if [ -d "latest/cmdline-tools" ]; then
echo "==> Normalizing cmdline-tools layout..."
if [ -d "latest/cmdline-tools/bin" ]; then
if [ ! -d "latest/bin" ]; then
mv latest/cmdline-tools/* latest/
rmdir latest/cmdline-tools || true
fi
fi
fi

export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"
chmod +x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" || true

echo "==> Accepting licenses..."
yes | sdkmanager --licenses || true

echo "==> Installing platform-tools, platform 34, build-tools 34.0.0..."
yes | sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"

cd /workspaces/Auto-Math-OCR

echo "sdk.dir=$ANDROID_SDK_ROOT" > local.properties
echo "==> local.properties:"
cat local.properties

echo "==> Building APK (debug)..."
chmod +x ./gradlew || true
./gradlew --no-daemon clean assembleDebug

echo "==> Build outputs:"
ls -lh app/build/outputs/apk/debug/ || true
