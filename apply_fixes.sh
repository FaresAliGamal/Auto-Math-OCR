set -e

cd /workspaces/Auto-Math-OCR

TS=$(date +%Y%m%d_%H%M%S)
BK="backup_conflicts_$TS"
mkdir -p "$BK"
[ -d app/src/main/java/com/math/app ] && mv app/src/main/java/com/math/app "$BK/" || true

mkdir -p app/src/main/res/layout
cat > app/src/main/res/layout/activity_main.xml <<'XML'
<androidx.constraintlayout.widget.ConstraintLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent">

    <FrameLayout
        android:id="@+id/blackBox"
        android:layout_width="0dp"
        android:layout_height="200dp"
        android:background="@android:color/black"
        app:layout_constraintTop_toTopOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        android:layout_margin="16dp">

        <ScrollView
            android:layout_width="match_parent"
            android:layout_height="match_parent">

            <TextView
                android:id="@+id/blackBoxText"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:textColor="@android:color/white"
                android:textSize="14sp"
                android:padding="12dp"
                android:text="هنا النص..." />
        </ScrollView>
    </FrameLayout>

    <Button
        android:id="@+id/btnUpload"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="رفع صورة"
        app:layout_constraintTop_toBottomOf="@id/blackBox"
        app:layout_constraintStart_toStartOf="parent"
        android:layout_marginTop="16dp"
        android:layout_marginStart="16dp"/>

    <ImageView
        android:id="@+id/previewImage"
        android:layout_width="0dp"
        android:layout_height="200dp"
        app:layout_constraintTop_toBottomOf="@id/btnUpload"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        android:layout_margin="16dp"
        android:scaleType="centerCrop"
        android:adjustViewBounds="true"/>
</androidx.constraintlayout.widget.ConstraintLayout>
XML

mkdir -p app/src/main/java/com/fares/automathocr
cat > app/src/main/java/com/fares/automathocr/MainActivity.kt <<'KOT'
package com.fares.automathocr

import android.net.Uri
import android.os.Bundle
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {

    private lateinit var blackBoxText: TextView
    private lateinit var previewImage: ImageView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        blackBoxText = findViewById(R.id.blackBoxText)
        previewImage = findViewById(R.id.previewImage)
        val btnUpload = findViewById<Button>(R.id.btnUpload)

        val pickImageLauncher = registerForActivityResult(
            ActivityResultContracts.GetContent()
        ) { uri: Uri? ->
            if (uri != null) {
                previewImage.setImageURI(uri)
                blackBoxText.text = "تم اختيار الصورة بنجاح ✅"
            } else {
                Toast.makeText(this, "لم يتم اختيار أي صورة", Toast.LENGTH_SHORT).show()
            }
        }

        btnUpload.setOnClickListener {
            pickImageLauncher.launch("image/*")
        }
    }
}
KOT

mkdir -p app/src/main/res/values
cat > app/src/main/res/values/styles.xml <<'XML'
<resources>
    <style name="Theme.AutoMathOCR" parent="Theme.MaterialComponents.DayNight.NoActionBar">
        <item name="android:windowBackground">@android:color/white</item>
    </style>
</resources>
XML

mkdir -p app/src/main
cat > app/src/main/AndroidManifest.xml <<'XML'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:allowBackup="true"
        android:theme="@style/Theme.AutoMathOCR"
        android:label="AutoMathOCR">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
XML

if [ -f app/build.gradle ]; then
  grep -q 'namespace ' app/build.gradle || sed -i '0,/^android\s*{/{s//android {\n    namespace "com.fares.automathocr"\n    compileSdk 34\n    defaultConfig {\n        minSdk 24\n        targetSdk 34\n    }\n/}' app/build.gradle
  grep -q 'compileSdk ' app/build.gradle || sed -i 's/^android\s*{.*/&\n    compileSdk 34/' app/build.gradle
  grep -q 'defaultConfig\s*{' app/build.gradle || sed -i '/^android\s*{.*/a\    defaultConfig {\n        minSdk 24\n        targetSdk 34\n    }' app/build.gradle
  grep -q 'com.google.android.material:material' app/build.gradle || sed -i '/dependencies\s*{/a \    implementation "com.google.android.material:material:1.12.0"' app/build.gradle
  grep -q 'androidx.constraintlayout:constraintlayout' app/build.gradle || sed -i '/dependencies\s*{/a \    implementation "androidx.constraintlayout:constraintlayout:2.1.4"' app/build.gradle
fi

if [ -f app/build.gradle.kts ]; then
  grep -q 'namespace ' app/build.gradle.kts || sed -i '0,/^android\s*{/{s//android {\n    namespace = "com.fares.automathocr"\n    compileSdk = 34\n    defaultConfig {\n        minSdk = 24\n        targetSdk = 34\n    }\n/}' app/build.gradle.kts
  grep -q 'compileSdk\s*=' app/build.gradle.kts || sed -i 's/^android\s*{.*/&\n    compileSdk = 34/' app/build.gradle.kts
  grep -q 'defaultConfig\s*{' app/build.gradle.kts || sed -i '/^android\s*{.*/a\    defaultConfig {\n        minSdk = 24\n        targetSdk = 34\n    }' app/build.gradle.kts
  grep -q 'com.google.android.material:material' app/build.gradle.kts || sed -i '/dependencies\s*{/a \    implementation("com.google.android.material:material:1.12.0")' app/build.gradle.kts
  grep -q 'androidx.constraintlayout:constraintlayout' app/build.gradle.kts || sed -i '/dependencies\s*{/a \    implementation("androidx.constraintlayout:constraintlayout:2.1.4")' app/build.gradle.kts
fi

./gradlew --no-daemon clean assembleDebug

mkdir -p ../BuildOut
cp app/build/outputs/apk/debug/app-debug.apk ../BuildOut/AutoMathOCR-Fixed.apk 2>/dev/null || true
ls -lh ../BuildOut
