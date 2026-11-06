#!/bin/bash
# Membuat seluruh proyek Android HandCursor + mengunduh model tangan.
set -e
mkdir -p app/src/main/java/com/zinsch/handcursor app/src/main/res/xml app/src/main/res/values app/src/main/assets

cat > settings.gradle.kts <<'EOF'
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "HandCursor"
include(":app")
EOF

cat > build.gradle.kts <<'EOF'
plugins {
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}
EOF

cat > gradle.properties <<'EOF'
android.useAndroidX=true
org.gradle.jvmargs=-Xmx3g
kotlin.code.style=official
EOF

cat > app/build.gradle.kts <<'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}
android {
    namespace = "com.zinsch.handcursor"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.zinsch.handcursor"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    androidResources { noCompress += listOf("task") }
}
dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.camera:camera-core:1.3.4")
    implementation("androidx.camera:camera-camera2:1.3.4")
    implementation("androidx.camera:camera-lifecycle:1.3.4")
    implementation("androidx.lifecycle:lifecycle-service:2.8.4")
    implementation("com.google.mediapipe:tasks-vision:0.10.14")
}
EOF

cat > app/src/main/AndroidManifest.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_CAMERA" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-feature android:name="android.hardware.camera.front" android:required="false" />
    <application
        android:label="@string/app_name"
        android:allowBackup="false"
        android:theme="@android:style/Theme.DeviceDefault.NoActionBar">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <service android:name=".HandService" android:exported="false"
            android:foregroundServiceType="camera" />
        <service android:name=".GestureService" android:exported="true"
            android:label="@string/app_name"
            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE">
            <intent-filter>
                <action android:name="android.accessibilityservice.AccessibilityService" />
            </intent-filter>
            <meta-data android:name="android.accessibilityservice" android:resource="@xml/a11y" />
        </service>
    </application>
</manifest>
EOF

cat > app/src/main/res/values/strings.xml <<'EOF'
<resources>
    <string name="app_name">HandCursor</string>
    <string name="a11y_desc">Dipakai untuk mengetuk dan menggulir layar berdasarkan gerakan tangan Anda.</string>
</resources>
EOF

cat > app/src/main/res/xml/a11y.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:accessibilityEventTypes="typeWindowStateChanged"
    android:accessibilityFeedbackType="feedbackGeneric"
    android:canPerformGestures="true"
    android:description="@string/a11y_desc"
    android:notificationTimeout="100" />
EOF

cat > app/src/main/java/com/zinsch/handcursor/GestureService.kt <<'EOF'
package com.zinsch.handcursor

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Intent
import android.graphics.Path
import android.view.accessibility.AccessibilityEvent

class GestureService : AccessibilityService() {
    companion object {
        @Volatile var inst: GestureService? = null
        fun tap(x: Float, y: Float) { inst?.gesture(x, y, x, y, 50) }
        fun scroll(down: Boolean, w: Int, h: Int) {
            val cx = w / 2f; val a = h * .65f; val b = h * .35f
            if (down) inst?.gesture(cx, a, cx, b, 200) else inst?.gesture(cx, b, cx, a, 200)
        }
    }

    private fun gesture(x1: Float, y1: Float, x2: Float, y2: Float, dur: Long) {
        val p = Path().apply { moveTo(x1, y1); if (x1 != x2 || y1 != y2) lineTo(x2, y2) }
        val g = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(p, 0, dur)).build()
        dispatchGesture(g, null, null)
    }

    override fun onServiceConnected() { inst = this }
    override fun onUnbind(intent: Intent?): Boolean { inst = null; return super.onUnbind(intent) }
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}
}
EOF

cat > app/src/main/java/com/zinsch/handcursor/HandService.kt <<'EOF'
package com.zinsch.handcursor

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.DisplayMetrics
import android.util.Size
import android.view.Choreographer
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleService
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max

/** Filter One Euro: halus saat diam, responsif saat bergerak cepat. */
class OneEuro(private val mc: Float, private val beta: Float) {
    private var x = 0f; private var r = 0f; private var dx = 0f; private var t = 0L; private var init = false
    private fun a(c: Float, dt: Float): Float { val tau = 1f / (2f * Math.PI.toFloat() * c); return 1f / (1f + tau / dt) }
    fun f(v: Float, now: Long): Float {
        if (!init) { init = true; x = v; r = v; dx = 0f; t = now; return v }
        val dt = max(.001f, (now - t) / 1000f); t = now
        val d = (v - r) / dt; r = v
        dx += a(1f, dt) * (d - dx)
        x += a(mc + beta * abs(dx), dt) * (v - x)
        return x
    }
    fun reset() { init = false }
}

class HandService : LifecycleService() {
    private lateinit var wm: WindowManager
    private lateinit var cursor: View
    private lateinit var lp: WindowManager.LayoutParams
    @Volatile private var landmarker: HandLandmarker? = null
    private var usingGpu = true
    private val exec = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var sw = 1080
    private var sh = 2400
    private val fx = OneEuro(.8f, 10f)
    private val fy = OneEuro(.8f, 10f)
    @Volatile private var tx = -1f
    @Volatile private var ty = -1f
    private var dispX = 0f
    private var dispY = 0f
    private var pinched = false
    private var ps = 1f
    private var lastY = -1f
    private var scrollAcc = 0f
    private var lastScrollT = 0L
    private var lastTs = 0L
    private var lostAt = 0L
    private var mode = "gerak"
    private var cand = "gerak"
    private var candN = 0
    private var paintKey = -1
    private val hist = ArrayDeque<Triple<Long, Float, Float>>()

    private val frame = object : Choreographer.FrameCallback {
        override fun doFrame(t: Long) {
            if (tx >= 0) {
                dispX += (tx - dispX) * .45f; dispY += (ty - dispY) * .45f
                val nx = (dispX - 45).toInt(); val ny = (dispY - 45).toInt()
                if (nx != lp.x || ny != lp.y) {
                    lp.x = nx; lp.y = ny
                    try { wm.updateViewLayout(cursor, lp) } catch (e: Exception) {}
                }
            }
            Choreographer.getInstance().postFrameCallback(this)
        }
    }

    private fun build(delegate: Delegate) = HandLandmarker.createFromOptions(this,
        HandLandmarker.HandLandmarkerOptions.builder()
            .setBaseOptions(BaseOptions.builder().setModelAssetPath("hand_landmarker.task").setDelegate(delegate).build())
            .setNumHands(1)
            .setMinHandDetectionConfidence(.5f).setMinHandPresenceConfidence(.5f).setMinTrackingConfidence(.5f)
            .setRunningMode(RunningMode.VIDEO).build())

    @Suppress("DEPRECATION")
    override fun onCreate() {
        super.onCreate()
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val dm = DisplayMetrics()
        wm.defaultDisplay.getRealMetrics(dm)
        sw = dm.widthPixels; sh = dm.heightPixels

        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel("hc", "HandCursor", NotificationManager.IMPORTANCE_LOW))
        val stop = PendingIntent.getService(this, 0,
            Intent(this, HandService::class.java).setAction("STOP"), PendingIntent.FLAG_IMMUTABLE)
        val n = Notification.Builder(this, "hc")
            .setContentTitle("HandCursor aktif")
            .setContentText("Ketuk Berhenti untuk mematikan")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .addAction(android.R.drawable.ic_delete, "Berhenti", stop)
            .build()
        if (Build.VERSION.SDK_INT >= 29) startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA)
        else startForeground(1, n)

        cursor = View(this).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL; setStroke(8, Color.YELLOW); setColor(Color.TRANSPARENT)
            }
        }
        lp = WindowManager.LayoutParams(90, 90, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS, PixelFormat.TRANSLUCENT
        ).apply { gravity = Gravity.TOP or Gravity.START; x = sw / 2; y = sh / 2 }
        try { wm.addView(cursor, lp) } catch (e: Exception) { stopSelf(); return }

        landmarker = try { build(Delegate.GPU) } catch (e: Exception) {
            usingGpu = false
            try { build(Delegate.CPU) } catch (e2: Exception) { stopSelf(); return }
        }
        Choreographer.getInstance().postFrameCallback(frame)

        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            val provider = future.get()
            val analysis = ImageAnalysis.Builder()
                .setTargetResolution(Size(480, 640))
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                .build()
            analysis.setAnalyzer(exec) { analyze(it) }
            provider.unbindAll()
            provider.bindToLifecycle(this@HandService, CameraSelector.DEFAULT_FRONT_CAMERA, analysis)
        }, ContextCompat.getMainExecutor(this))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        if (intent?.action == "STOP") stopSelf()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        Choreographer.getInstance().removeFrameCallback(frame)
        exec.shutdown()
        landmarker?.close()
        try { wm.removeView(cursor) } catch (e: Exception) {}
    }

    private fun analyze(p: ImageProxy) {
        try {
            val lm = landmarker ?: return
            val now = SystemClock.uptimeMillis()
            if (now <= lastTs) return
            lastTs = now
            var bmp = p.toBitmap()
            val rot = p.imageInfo.rotationDegrees
            if (rot != 0) {
                val m = Matrix(); m.postRotate(rot.toFloat())
                bmp = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
            }
            val res = lm.detectForVideo(BitmapImageBuilder(bmp).build(), now)
            handle(res.landmarks().firstOrNull(), now)
        } catch (e: Exception) {
            if (usingGpu) { // GPU bermasalah di perangkat ini, pindah ke CPU
                usingGpu = false
                try { val old = landmarker; landmarker = build(Delegate.CPU); old?.close() } catch (e2: Exception) {}
            }
        } finally { p.close() }
    }

    private fun d(a: NormalizedLandmark, b: NormalizedLandmark): Float =
        hypot((a.x() - b.x()).toDouble(), (a.y() - b.y()).toDouble()).toFloat()
    private fun ext(l: List<NormalizedLandmark>, t: Int, p: Int) = d(l[0], l[t]) > d(l[0], l[p]) * 1.08f

    private fun paint(color: Int, fill: Boolean) {
        val key = color * 2 + (if (fill) 1 else 0)
        if (key == paintKey) return
        paintKey = key
        main.post {
            (cursor.background as GradientDrawable).apply {
                setStroke(8, color)
                setColor(if (fill) Color.argb(120, 79, 195, 161) else Color.TRANSPARENT)
            }
        }
    }

    private fun vote(m: String): String {
        if (m == mode) { candN = 0; return mode }
        if (m == cand) { if (++candN >= 3) { mode = m; candN = 0 } } else { cand = m; candN = 1 }
        return mode
    }

    private fun handle(l: List<NormalizedLandmark>?, now: Long) {
        if (l == null || l.size < 21) {
            lastY = -1f
            if (lostAt == 0L) lostAt = now
            if (now - lostAt > 400) { fx.reset(); fy.reset(); pinched = false; hist.clear(); paint(Color.YELLOW, false) }
            return
        }
        lostAt = 0L
        val idx = ext(l, 8, 6); val mid = ext(l, 12, 10); val rng = ext(l, 16, 14); val pky = ext(l, 20, 18)
        val raw = if (!idx && !mid && !rng && !pky) "jeda" else if (idx && mid && !rng && !pky) "gulir" else "gerak"
        val m = vote(raw)

        if (m == "jeda") { lastY = -1f; paint(Color.GRAY, false); return }

        if (m == "gulir") {
            val y = (l[8].y() + l[12].y()) / 2f
            if (lastY >= 0) {
                scrollAcc += (y - lastY) * sh * 3f
                if (abs(scrollAcc) > 120 && now - lastScrollT > 250) {
                    GestureService.scroll(scrollAcc > 0, sw, sh); scrollAcc = 0f; lastScrollT = now
                }
            }
            lastY = y; paint(Color.rgb(106, 169, 255), false); return
        }

        lastY = -1f; scrollAcc = 0f
        val nx = ((1f - l[8].x() - .15f) / .7f).coerceIn(0f, 1f)
        val ny = ((l[8].y() - .12f) / .68f).coerceIn(0f, 1f)
        val pinch = d(l[4], l[8]) / max(d(l[0], l[9]), 1e-6f)
        ps = ps * .5f + pinch * .5f

        if (!pinched) {
            val x = fx.f(nx, now) * sw; val y = fy.f(ny, now) * sh
            tx = x; ty = y
            if (dispX == 0f && dispY == 0f) { dispX = x; dispY = y }
            hist.addLast(Triple(now, x, y))
            while (hist.isNotEmpty() && now - hist.first().first > 400) hist.removeFirst()
        }
        if (!pinched && ps < .22f) {
            pinched = true
            val h = hist.firstOrNull { now - it.first <= 130 } ?: hist.lastOrNull()
            if (h != null) { tx = h.second; ty = h.third; GestureService.tap(h.second, h.third) }
        } else if (pinched && ps > .38f) pinched = false
        paint(if (pinched) Color.rgb(79, 195, 161) else Color.YELLOW, pinched)
    }
}
EOF

cat > app/src/main/java/com/zinsch/handcursor/MainActivity.kt <<'EOF'
package com.zinsch.handcursor

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast

class MainActivity : Activity() {
    private lateinit var status: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val box = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(48, 96, 48, 48) }
        fun text(s: String, size: Float = 16f) = TextView(this).apply { this.text = s; textSize = size; setPadding(0, 12, 0, 12) }
        fun btn(s: String, f: () -> Unit) = Button(this).apply { text = s; setOnClickListener { f() } }
        box.addView(text("HandCursor", 28f))
        box.addView(text("Gerak: telunjuk. Klik: cubit jempol+telunjuk. Gulir: telunjuk+jari tengah naik/turun. Jeda: kepalkan tangan."))
        status = text("")
        box.addView(status)
        box.addView(btn("1. Izinkan kamera") {
            val p = mutableListOf(Manifest.permission.CAMERA)
            if (Build.VERSION.SDK_INT >= 33) p.add(Manifest.permission.POST_NOTIFICATIONS)
            requestPermissions(p.toTypedArray(), 1)
        })
        box.addView(btn("2. Izinkan tampil di atas aplikasi lain") {
            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
        })
        box.addView(btn("3. Aktifkan layanan aksesibilitas") {
            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        })
        box.addView(btn("4. MULAI") {
            when {
                checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED -> toast("Izin kamera belum diberikan")
                !Settings.canDrawOverlays(this) -> toast("Izin tampil di atas aplikasi lain belum diberikan")
                GestureService.inst == null -> toast("Layanan aksesibilitas belum aktif")
                else -> { startForegroundService(Intent(this, HandService::class.java)); toast("HandCursor berjalan. Buka aplikasi lain.") }
            }
        })
        box.addView(btn("Berhenti") { stopService(Intent(this, HandService::class.java)) })
        setContentView(ScrollView(this).apply { addView(box) })
    }

    override fun onResume() {
        super.onResume()
        fun ok(b: Boolean) = if (b) "OK" else "belum"
        status.text = "Kamera: ${ok(checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED)}\n" +
            "Tampil di atas aplikasi: ${ok(Settings.canDrawOverlays(this))}\n" +
            "Aksesibilitas: ${ok(GestureService.inst != null)}"
    }

    private fun toast(s: String) = Toast.makeText(this, s, Toast.LENGTH_LONG).show()
}
EOF

# unduh model tangan MediaPipe (dijalankan di GitHub Actions, yang punya internet)
curl -fL -o app/src/main/assets/hand_landmarker.task \
  https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task
echo "Proyek selesai dibuat."
