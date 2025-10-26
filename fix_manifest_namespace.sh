set -e

cd /workspaces/Auto-Math-OCR

MANIFEST="app/src/main/AndroidManifest.xml"
if [ -f "$MANIFEST" ]; then
  sed -i -E 's/[[:space:]]+package="[^"]*"//g' "$MANIFEST"
fi

if [ -f app/build.gradle ]; then
  grep -q 'namespace ' app/build.gradle || sed -i '0,/^android[[:space:]]*{/{s//android {\n    namespace "com.fares.automathocr"/}' app/build.gradle
  sed -i -E 's/^[[:space:]]*namespace[[:space:]]+".*"/    namespace "com.fares.automathocr"/' app/build.gradle

  if grep -q 'defaultConfig[[:space:]]*{' app/build.gradle; then
    grep -q 'applicationId' app/build.gradle || sed -i '/defaultConfig[[:space:]]*{.*/a\        applicationId "com.fares.automathocr"' app/build.gradle
    sed -i -E 's/^[[:space:]]*applicationId[[:space:]]+".*"/        applicationId "com.fares.automathocr"/' app/build.gradle
    grep -q 'minSdk' app/build.gradle    || sed -i '/defaultConfig[[:space:]]*{.*/a\        minSdk 24' app/build.gradle
    grep -q 'targetSdk' app/build.gradle || sed -i '/defaultConfig[[:space:]]*{.*/a\        targetSdk 34' app/build.gradle
  else
    sed -i '/^android[[:space:]]*{.*/a\    defaultConfig {\n        applicationId "com.fares.automathocr"\n        minSdk 24\n        targetSdk 34\n    }' app/build.gradle
  fi

  grep -q 'compileSdk ' app/build.gradle || sed -i 's/^android[[:space:]]*{.*/&\n    compileSdk 34/' app/build.gradle

  grep -q 'com.google.android.material:material' app/build.gradle || sed -i '/dependencies[[:space:]]*{/a \    implementation "com.google.android.material:material:1.12.0"' app/build.gradle
  grep -q 'androidx.constraintlayout:constraintlayout' app/build.gradle || sed -i '/dependencies[[:space:]]*{/a \    implementation "androidx.constraintlayout:constraintlayout:2.1.4"' app/build.gradle
  grep -q 'androidx.appcompat:appcompat' app/build.gradle || sed -i '/dependencies[[:space:]]*{/a \    implementation "androidx.appcompat:appcompat:1.7.0"' app/build.gradle
fi

if [ -f app/build.gradle.kts ]; then
  grep -q 'namespace ' app/build.gradle.kts || sed -i '0,/^android[[:space:]]*{/{s//android {\n    namespace = "com.fares.automathocr"/}' app/build.gradle.kts
  sed -i -E 's/^[[:space:]]*namespace[[:space:]]*=.*/    namespace = "com.fares.automathocr"/' app/build.gradle.kts

  if grep -q 'defaultConfig[[:space:]]*{' app/build.gradle.kts; then
    grep -q 'applicationId[[:space:]]*=' app/build.gradle.kts || sed -i '/defaultConfig[[:space:]]*{.*/a\        applicationId = "com.fares.automathocr"' app/build.gradle.kts
    sed -i -E 's/^[[:space:]]*applicationId[[:space:]]*=.*/        applicationId = "com.fares.automathocr"/' app/build.gradle.kts
    grep -q 'minSdk[[:space:]]*=' app/build.gradle.kts || sed -i '/defaultConfig[[:space:]]*{.*/a\        minSdk = 24' app/build.gradle.kts
    grep -q 'targetSdk[[:space:]]*=' app/build.gradle.kts || sed -i '/defaultConfig[[:space:]]*{.*/a\        targetSdk = 34' app/build.gradle.kts
  else
    sed -i '/^android[[:space:]]*{.*/a\    defaultConfig {\n        applicationId = "com.fares.automathocr"\n        minSdk = 24\n        targetSdk = 34\n    }' app/build.gradle.kts
  fi

  grep -q 'compileSdk[[:space:]]*=' app/build.gradle.kts || sed -i 's/^android[[:space:]]*{.*/&\n    compileSdk = 34/' app/build.gradle.kts

  grep -q 'com.google.android.material:material' app/build.gradle.kts || sed -i '/dependencies[[:space:]]*{/a \    implementation("com.google.android.material:material:1.12.0")' app/build.gradle.kts
  grep -q 'androidx.constraintlayout:constraintlayout' app/build.gradle.kts || sed -i '/dependencies[[:space:]]*{/a \    implementation("androidx.constraintlayout:constraintlayout:2.1.4")' app/build.gradle.kts
  grep -q 'androidx.appcompat:appcompat' app/build.gradle.kts || sed -i '/dependencies[[:space:]]*{/a \    implementation("androidx.appcompat:appcompat:1.7.0")' app/build.gradle.kts
fi

./gradlew --no-daemon clean assembleDebug

mkdir -p ../BuildOut
cp app/build/outputs/apk/debug/app-debug.apk ../BuildOut/AutoMathOCR-Fixed.apk 2>/dev/null || true
ls -lh ../BuildOut
