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
        fun swipe(x1: Float, y1: Float, x2: Float, y2: Float, dur: Long) { inst?.gesture(x1, y1, x2, y2, dur, true) }
        fun scroll(down: Boolean, w: Int, h: Int, frac: Float = .3f) {
            val cx = w / 2f; val a = h * (.5f + frac / 2); val b = h * (.5f - frac / 2)
            if (down) inst?.gesture(cx, a, cx, b, 200, true) else inst?.gesture(cx, b, cx, a, 200, true)
        }
    }

    private fun gesture(x1: Float, y1: Float, x2: Float, y2: Float, dur: Long, safe: Boolean = false) {
        // Android menolak usapan yang keluar dari layar, jadi koordinat dibatasi.
        val dm = resources.displayMetrics
        val w = dm.widthPixels.toFloat(); val h = dm.heightPixels.toFloat()
        // ketukan boleh sampai tepi; usapan dijauhkan dari tepi agar tidak memicu Kembali/Beranda sistem
        fun px(v: Float) = if (safe) v.coerceIn(48f, w - 48f) else v.coerceIn(2f, w - 2f)
        fun py(v: Float) = if (safe) v.coerceIn(60f, h - 120f) else v.coerceIn(2f, h - 2f)
        val p = Path().apply { moveTo(px(x1), py(y1)); if (x1 != x2 || y1 != y2) lineTo(px(x2), py(y2)) }
        val g = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(p, 0, dur)).build()
        dispatchGesture(g, null, null)
    }

    override fun onServiceConnected() { inst = this }
    override fun onUnbind(intent: Intent?): Boolean { inst = null; return super.onUnbind(intent) }
    override fun onDestroy() { inst = null; super.onDestroy() }
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
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import android.graphics.RectF
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
import android.widget.Toast
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleService
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.sqrt

/** Titik 3D. */
internal class P(val x: Float, val y: Float, val z: Float)

internal fun dist(a: P, b: P): Float {
    val dx = a.x - b.x; val dy = a.y - b.y; val dz = a.z - b.z
    return sqrt(dx * dx + dy * dy + dz * dz)
}

/** Kursor ringan: satu cincin + titik, digambar ulang hanya saat status berubah. */
class HudView(c: Context) : View(c) {
    var state = 0      // 0 gerak, 1 cubit, 2 jeda, 3 gulir, 4 seret
        set(v) { if (field != v) { field = v; invalidate() } }
    private val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = 5f }
    private val f = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    override fun onDraw(cv: Canvas) {
        val cx = width / 2f; val cy = height / 2f; val r = minOf(cx, cy) - 4f
        val col = when (state) {
            1 -> Color.parseColor("#4FC3A1"); 2 -> Color.parseColor("#8899A6")
            3 -> Color.parseColor("#6AA9FF"); 4 -> Color.parseColor("#FFB347")
            else -> Color.parseColor("#FFD166")
        }
        val pinch = state == 1 || state == 4
        p.color = col
        cv.drawCircle(cx, cy, if (pinch) r * .7f else r, p)
        f.color = col
        if (pinch) { f.alpha = 110; cv.drawCircle(cx, cy, r * .7f, f) }
        f.color = col; f.alpha = 255
        cv.drawCircle(cx, cy, if (pinch) 6f else 4f, f)
    }
}

/** Filter One Euro: halus saat diam, responsif saat bergerak cepat. */
class OneEuro(private var mc: Float, private var beta: Float) {
    private var x = 0f; private var r = 0f; private var dx = 0f; private var t = 0L; private var init = false
    private fun a(c: Float, dt: Float): Float { val tau = 1f / (2f * Math.PI.toFloat() * c); return 1f / (1f + tau / dt) }
    fun set(mc: Float, beta: Float) { this.mc = mc; this.beta = beta }
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
    private lateinit var cursor: HudView
    private lateinit var lp: WindowManager.LayoutParams
    private lateinit var prefs: SharedPreferences
    private val prefListener = SharedPreferences.OnSharedPreferenceChangeListener { _, _ -> applyPrefs() }
    @Volatile private var landmarker: HandLandmarker? = null
    @Volatile private var analysis: ImageAnalysis? = null
    private var usingGpu = true
    @Volatile private var stopping = false
    private var provider: ProcessCameraProvider? = null
    @Volatile private var debug = false
    private var dbgView: android.widget.TextView? = null
    private var lastDbg = 0L
    private val ext = BooleanArray(4)   // telunjuk, tengah, manis, kelingking (dengan histeresis)
    private var errCount = 0
    private val exec = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    @Volatile private var sw = 1080
    @Volatile private var sh = 2400

    // pengaturan (bisa diubah langsung dari aplikasi)
    @Volatile private var regionK = 1f
    @Volatile private var pinchClose = .30f
    @Volatile private var dragThr = 130f
    @Volatile private var dragGain = 1.1f
    @Volatile private var twoFinger = false

    private val fx = OneEuro(.5f, 18f)
    private val fy = OneEuro(.5f, 18f)
    @Volatile private var tx = -1f
    @Volatile private var ty = -1f
    private var dispX = 0f
    private var dispY = 0f
    private var hasDisp = false

    private var pinched = false
    private var pinchN = 0
    private var releaseN = 0
    private var ps = 1f
    private var dragged = false
    private var ox = 0f
    private var oy = 0f
    private var dragX = 0f
    private var dragY = 0f
    private var lastDragT = 0L
    private var pinchStartT = 0L
    private var lastTapT = 0L
    private var stickyUntil = 0L
    private var tappedAtStart = false

    private var wasScroll = false
    private var scrollArmAt = 0L
    private var anchorY = -1f
    private var lastScrollT = 0L

    private var lastTs = 0L
    private var frameN = 0
    private var lastProcT = 0L
    private var lastDarkWarn = 0L
    @Volatile private var lum = 128f
    private var prevWx = 0f
    private var prevWy = 0f
    private var prevT = 0L
    private var jumpN = 0
    private var lostAt = 0L
    private var mode = "gerak"
    private var cand = "gerak"
    private var candN = 0
    private var paintKey = -1
    private val hist = ArrayDeque<Triple<Long, Float, Float>>()

    @Volatile private var chasing = false
    private var velX = 0f
    private var velY = 0f
    private var lastFrameNs = 0L

    /** SmoothDamp: gerak halus tanpa overshoot, hasilnya sama di layar 60/90/120 Hz. */
    private fun smoothDamp(cur: Float, target: Float, axis: Int, dt: Float): Float {
        val omega = 2f / .055f
        val x = omega * dt
        val e = 1f / (1f + x + .48f * x * x + .235f * x * x * x)
        val v = if (axis == 0) velX else velY
        val change = cur - target
        val temp = (v + omega * change) * dt
        val nv = (v - omega * temp) * e
        if (axis == 0) velX = nv else velY = nv
        return target + (change + temp) * e
    }

    private val frame = object : Choreographer.FrameCallback {
        override fun doFrame(t: Long) {
            if (tx >= 0) {
                if (!hasDisp) { dispX = tx; dispY = ty; hasDisp = true; velX = 0f; velY = 0f }
                val dt = if (lastFrameNs == 0L) 1f / 60f else ((t - lastFrameNs) / 1e9f).coerceIn(.004f, .05f)
                lastFrameNs = t
                dispX = smoothDamp(dispX, tx, 0, dt); dispY = smoothDamp(dispY, ty, 1, dt)
                val nx = (dispX - 55).toInt(); val ny = (dispY - 55).toInt()
                if (nx != lp.x || ny != lp.y) {
                    lp.x = nx; lp.y = ny
                    try { wm.updateViewLayout(cursor, lp) } catch (e: Exception) {}
                }
                if (abs(tx - dispX) > .4f || abs(ty - dispY) > .4f || abs(velX) > 5f || abs(velY) > 5f) {
                    Choreographer.getInstance().postFrameCallback(this); return
                }
            }
            lastFrameNs = 0L
            chasing = false
        }
    }

    /** Jalankan pengejaran posisi hanya kalau target berubah; berhenti sendiri saat sudah sampai. */
    private fun kick() {
        if (!chasing) { chasing = true; main.post { Choreographer.getInstance().postFrameCallback(frame) } }
    }

    private fun toast(s: String) { main.post { Toast.makeText(applicationContext, s, Toast.LENGTH_LONG).show() } }

    private fun applyPrefs() {
        fun v(k: String) = prefs.getInt(k, 50) / 100f
        regionK = 1.4f - .8f * v("spd")                                   // jangkauan kursor
        val sm = 2.0.pow((50 - prefs.getInt("smooth", 50)) / 25.0).toFloat() * .5f
        fx.set(sm, 18f); fy.set(sm, 18f)                                  // kehalusan
        pinchClose = .18f + .24f * v("pinch")                             // sensitivitas cubit
        debug = prefs.getBoolean("dbg", false)
        main.post { dbgView?.visibility = if (debug) View.VISIBLE else View.GONE }
        dragThr = 180f - 100f * v("drag")                                 // jarak mulai seret
        dragGain = .5f + 1.2f * v("gain")                                 // kecepatan seret
        twoFinger = prefs.getBoolean("two", false)
    }

    @Suppress("DEPRECATION")
    private fun refreshMetrics() {
        val dm = DisplayMetrics()
        wm.defaultDisplay.getRealMetrics(dm)
        sw = dm.widthPixels; sh = dm.heightPixels
        try { analysis?.targetRotation = wm.defaultDisplay.rotation } catch (e: Exception) {}
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        refreshMetrics()
    }

    private fun build(delegate: Delegate) = HandLandmarker.createFromOptions(this,
        HandLandmarker.HandLandmarkerOptions.builder()
            .setBaseOptions(BaseOptions.builder().setModelAssetPath("hand_landmarker.task").setDelegate(delegate).build())
            .setNumHands(1)
            .setMinHandDetectionConfidence(.6f).setMinHandPresenceConfidence(.6f).setMinTrackingConfidence(.5f)
            .setRunningMode(RunningMode.VIDEO).build())

    override fun onCreate() {
        super.onCreate()
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        prefs = getSharedPreferences("hc", MODE_PRIVATE)
        applyPrefs()
        prefs.registerOnSharedPreferenceChangeListener(prefListener)
        refreshMetrics()

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

        cursor = HudView(this)
        // FLAG_LAYOUT_IN_SCREEN: koordinat overlay = koordinat layar (sama dengan koordinat ketukan)
        lp = WindowManager.LayoutParams(110, 110, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START; x = sw / 2; y = sh / 2
            if (Build.VERSION.SDK_INT >= 28)
                layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        try { wm.addView(cursor, lp) } catch (e: Exception) {
            toast("Gagal menampilkan kursor. Periksa izin 'tampil di atas aplikasi lain'."); stopSelf(); return
        }

        dbgView = android.widget.TextView(this).apply {
            textSize = 12f; setTextColor(Color.WHITE); setBackgroundColor(Color.argb(170, 0, 0, 0))
            setPadding(16, 8, 16, 8); text = "debug"; visibility = if (debug) View.VISIBLE else View.GONE
        }
        val dlp = WindowManager.LayoutParams(WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN, PixelFormat.TRANSLUCENT
        ).apply { gravity = Gravity.TOP or Gravity.START; x = 8; y = 120 }
        try { wm.addView(dbgView, dlp) } catch (e: Exception) {}

        landmarker = try { build(Delegate.GPU) } catch (e: Exception) {
            usingGpu = false
            try { build(Delegate.CPU) } catch (e2: Exception) {
                toast("Gagal memuat model tangan: ${e2.message}"); stopSelf(); return
            }
        }

        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            try {
                val pv = future.get()
                provider = pv
                val a = ImageAnalysis.Builder()
                    .setTargetResolution(Size(480, 640))
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                    .build()
                a.setAnalyzer(exec) { analyze(it) }
                analysis = a
                refreshMetrics()
                pv.unbindAll()
                pv.bindToLifecycle(this@HandService, CameraSelector.DEFAULT_FRONT_CAMERA, a)
            } catch (e: Exception) {
                toast("Kamera gagal dibuka: ${e.message}"); stopSelf()
            }
        }, ContextCompat.getMainExecutor(this))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        if (intent?.action == "STOP") stopSelf()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        stopping = true
        super.onDestroy()
        try { analysis?.clearAnalyzer() } catch (e: Exception) {}
        try { provider?.unbindAll() } catch (e: Exception) {}
        prefs.unregisterOnSharedPreferenceChangeListener(prefListener)
        Choreographer.getInstance().removeFrameCallback(frame)
        val lm = landmarker
        landmarker = null
        exec.execute { try { lm?.close() } catch (e: Exception) {} }   // tutup setelah analisis terakhir selesai
        exec.shutdown()
        try { wm.removeView(cursor) } catch (e: Exception) {}
        try { wm.removeView(dbgView) } catch (e: Exception) {}
    }

    // bitmap dipakai ulang tiap frame: tidak ada alokasi besar berulang, GC jarang jalan
    private var srcBuf: Bitmap? = null
    private var rotBuf: Bitmap? = null
    private var enhBuf: Bitmap? = null
    private val rotMatrix = Matrix()
    private val enhPaint = Paint()

    private fun analyze(p: ImageProxy) {
        try {
            if (stopping) return
            val lm = landmarker ?: return
            val now = SystemClock.uptimeMillis()
            if (now <= lastTs) return
            // tidak ada tangan > 2 detik: turunkan ke ~10 fps untuk menghemat baterai
            if (lostAt != 0L && now - lostAt > 2000 && now - lastProcT < 100) return
            lastProcT = now
            lastTs = now

            val plane = p.planes[0]
            val src: Bitmap
            if (plane.rowStride == p.width * 4) {
                var sb = srcBuf
                if (sb == null || sb.width != p.width || sb.height != p.height) {
                    sb = Bitmap.createBitmap(p.width, p.height, Bitmap.Config.ARGB_8888); srcBuf = sb
                }
                plane.buffer.rewind()
                sb.copyPixelsFromBuffer(plane.buffer)
                src = sb
            } else {
                src = p.toBitmap()                 // cadangan kalau tata letak memori tak lazim
            }

            var bmp: Bitmap = src
            val deg = p.imageInfo.rotationDegrees
            if (deg != 0) {
                val rw = if (deg == 90 || deg == 270) src.height else src.width
                val rh = if (deg == 90 || deg == 270) src.width else src.height
                var dst = rotBuf
                if (dst == null || dst.width != rw || dst.height != rh) {
                    dst = Bitmap.createBitmap(rw, rh, Bitmap.Config.ARGB_8888); rotBuf = dst
                }
                rotMatrix.reset(); rotMatrix.setRotate(deg.toFloat())
                when (deg) {
                    90 -> rotMatrix.postTranslate(src.height.toFloat(), 0f)
                    180 -> rotMatrix.postTranslate(src.width.toFloat(), src.height.toFloat())
                    270 -> rotMatrix.postTranslate(0f, src.width.toFloat())
                }
                Canvas(dst).drawBitmap(src, rotMatrix, null)
                bmp = dst
            }

            if (++frameN % 8 == 0) lum = luma(bmp)      // cukup dicek tiap 8 frame
            if (lum < 70f) {                            // ruangan gelap: terangkan gambar sebelum dideteksi
                var eb = enhBuf
                if (eb == null || eb.width != bmp.width || eb.height != bmp.height) {
                    eb = Bitmap.createBitmap(bmp.width, bmp.height, Bitmap.Config.ARGB_8888); enhBuf = eb
                }
                enhanceInto(bmp, eb, (100f / max(lum, 15f)).coerceIn(1f, 2.8f))
                bmp = eb
                if (lum < 40f && now - lastDarkWarn > 20000) {
                    lastDarkWarn = now; toast("Ruangan terlalu gelap, pelacakan bisa kurang akurat. Tambah cahaya.")
                }
            }

            val mp = BitmapImageBuilder(bmp).build()
            val res = try { lm.detectForVideo(mp, now) } finally { mp.close() }
            errCount = 0
            handle(res, bmp.width, bmp.height, now)
        } catch (e: Exception) {
            // pindah ke CPU hanya kalau error berulang (bukan karena satu frame bermasalah)
            if (usingGpu && ++errCount >= 5) {
                usingGpu = false
                try { val old = landmarker; landmarker = build(Delegate.CPU); old?.close() } catch (e2: Exception) {}
            }
        } finally {
            p.close()
        }
    }

    private fun paint(state: Int) {
        if (state == paintKey) return
        paintKey = state
        main.post { cursor.state = state }
    }

    private fun doTap(x: Float, y: Float) {
        GestureService.tap(x, y)
    }

    /** Di 6% tepi layar, 3% terluar dipetakan tepat ke tepi supaya tombol di pinggir mudah dicapai. */
    private fun snap(v: Float, size: Float): Float {
        val m = size * .06f; val e = m * .5f
        return when {
            v < m -> max(0f, v - e) * (m / (m - e))
            v > size - m -> size - max(0f, (size - v) - e) * (m / (m - e))
            else -> v
        }
    }

    private fun luma(b: Bitmap): Float {
        var sum = 0f; var n = 0
        val sx = max(1, b.width / 24); val sy = max(1, b.height / 32)
        var y = 0
        while (y < b.height) {
            var x = 0
            while (x < b.width) {
                val c = b.getPixel(x, y)
                sum += .299f * Color.red(c) + .587f * Color.green(c) + .114f * Color.blue(c); n++
                x += sx
            }
            y += sy
        }
        return if (n > 0) sum / n else 128f
    }

    private fun enhanceInto(src: Bitmap, dst: Bitmap, gain: Float) {
        enhPaint.colorFilter = ColorMatrixColorFilter(ColorMatrix(floatArrayOf(
            gain, 0f, 0f, 0f, 0f,  0f, gain, 0f, 0f, 0f,  0f, 0f, gain, 0f, 0f,  0f, 0f, 0f, 1f, 0f)))
        Canvas(dst).drawBitmap(src, 0f, 0f, enhPaint)
    }

    private fun vote(m: String): String {
        if (m == mode) { candN = 0; return mode }
        if (m == cand) { if (++candN >= (when (m) { "jeda" -> 5; "gulir" -> 6; else -> 2 })) { mode = m; candN = 0 } } else { cand = m; candN = 1 }
        return mode
    }

    private fun resetState() {
        fx.reset(); fy.reset()
        pinched = false; pinchN = 0; releaseN = 0; dragged = false; ps = 1f
        wasScroll = false; anchorY = -1f; stickyUntil = 0L
        mode = "gerak"; cand = "gerak"; candN = 0
        hist.clear()
        ext.fill(false)
        paint(0)
    }

    private fun onLost(now: Long) {
        if (lostAt == 0L) lostAt = now
        if (now - lostAt > 400) resetState()
    }

    private fun handle(res: HandLandmarkerResult, w: Int, h: Int, now: Long) {
        val norm = res.landmarks().firstOrNull()
        if (norm == null || norm.size < 21) { onLost(now); return }
        // Saring deteksi meragukan: skor rendah, tangan terlalu kecil (latar jauh) atau terlalu besar
        val hs = res.handednesses().firstOrNull()?.firstOrNull()?.score() ?: 1f
        val hsz = hypot(((norm[0].x() - norm[9].x()) * w).toDouble(), ((norm[0].y() - norm[9].y()) * h).toDouble()).toFloat() / h
        if (hs < .4f || hsz < .05f || hsz > .55f) { onLost(now); return }
        // Buang lonjakan mendadak satu frame (deteksi salah ke objek lain)
        val wx = norm[0].x(); val wy = norm[0].y()
        if (prevT != 0L && now - prevT < 150) {
            val jump = hypot(((wx - prevWx) * w).toDouble(), ((wy - prevWy) * h).toDouble()).toFloat() / h
            if (jump > .30f && jumpN < 2) { jumpN++; return }
        }
        jumpN = 0; prevWx = wx; prevWy = wy; prevT = now
        lostAt = 0L

        // Koordinat dunia 3D (meter) tahan terhadap rotasi tangan dan rasio layar;
        // cadangan: koordinat gambar yang sudah dikoreksi rasio.
        val world = res.worldLandmarks().firstOrNull()
        val q: List<P> = if (world != null && world.size >= 21) world.map { P(it.x(), it.y(), it.z()) }
        else norm.map { P(it.x() * w, it.y() * h, it.z() * w) }

        val size = max(dist(q[0], q[9]), 1e-6f)
        // Kelurusan jari = jarak pangkal-ujung / panjang tulang jari. ~1.0 lurus, ~0.5 menekuk.
        // Tidak bergantung arah tangan, dan memakai histeresis supaya tidak berkedip.
        fun st(a: Int, b: Int, c: Int, d: Int) =
            dist(q[a], q[d]) / max(dist(q[a], q[b]) + dist(q[b], q[c]) + dist(q[c], q[d]), 1e-6f)
        val sv = floatArrayOf(st(5, 6, 7, 8), st(9, 10, 11, 12), st(13, 14, 15, 16), st(17, 18, 19, 20))
        for (i in 0..3) {
            val on = if (i == 0) .80f else .84f      // telunjuk lebih toleran: tidak mudah dianggap terlipat
            val off = if (i == 0) .62f else .70f
            if (sv[i] > on) ext[i] = true else if (sv[i] < off) ext[i] = false
        }
        val idx = ext[0]; val mid = ext[1]; val rng = ext[2]; val pky = ext[3]
        val sI = sv[0]
        ps = ps * .4f + (dist(q[4], q[8]) / size) * .6f
        val openThr = pinchClose * 1.6f

        // Kursor hanya bergerak kalau TELUNJUK terangkat (atau sedang mencubit).
        // Pose lain (kepalan, hanya jari tengah/manis/kelingking terangkat) = jeda.
        val near = ps < pinchClose * 1.3f || pinched
        val rawMode = when {
            near -> "gerak"
            twoFinger && idx && mid && !rng && !pky -> "gulir"
            idx -> "gerak"
            else -> "jeda"
        }
        if (debug && now - lastDbg > 150) {
            lastDbg = now
            fun f(i: Int, n: String) = n + (if (ext[i]) "+" else "-") + "%.2f".format(sv[i])
            val t = f(0, "T") + "  " + f(1, "J") + "  " + f(2, "M") + "  " + f(3, "K") +
                "\ncubit %.2f (batas %.2f)  mode %s\nterang %.0f  skor %.2f  ukuran %.2f".format(ps, pinchClose, mode, lum, hs, hsz)
            main.post { dbgView?.text = t }
        }
        val m = vote(rawMode)

        if (m == "jeda") {
            pinched = false; pinchN = 0; releaseN = 0; dragged = false; wasScroll = false
            paint(2); return
        }

        if (m == "gulir") {                              // gulir dua jari (opsional)
            pinched = false; pinchN = 0; releaseN = 0; dragged = false
            val y = (norm[8].y() + norm[12].y()) / 2f
            if (!wasScroll) { wasScroll = true; scrollArmAt = now + 350; anchorY = -1f }
            if (now >= scrollArmAt) {
                if (anchorY < 0) anchorY = y
                val diff = y - anchorY
                if (abs(diff) > .05f && now - lastScrollT > 220) {
                    GestureService.scroll(diff > 0, sw, sh, (abs(diff) * 3f).coerceIn(.2f, .55f))
                    lastScrollT = now
                }
            }
            paint(3); return
        }
        wasScroll = false

        // posisi kursor: titik tengah jangkauan, ukuran sesuai pengaturan
        val k = regionK
        // titik kursor: dari sendi PIP ke ujung jari. Makin dekat cubit, makin berat ke PIP
        // (sendi ini hampir tidak bergerak saat mencubit, jadi kursor tidak ikut bergeser)
        val wgt = .65f
        val px = norm[6].x() + (norm[8].x() - norm[6].x()) * wgt
        val py = norm[6].y() + (norm[8].y() - norm[6].y()) * wgt
        val nx = (((1f - px) - .5f) / (.7f * k) + .5f).coerceIn(0f, 1f)
        val ny = ((py - .46f) / (.68f * k) + .5f).coerceIn(0f, 1f)
        val x = snap(((fx.f(nx, now) - .5f) * 1.10f + .5f).coerceIn(0f, 1f) * sw, sw.toFloat())
        val y = snap(((fy.f(ny, now) - .5f) * 1.10f + .5f).coerceIn(0f, 1f) * sh, sh.toFloat())

        if (!pinched) {
            // setelah klik, kursor ditahan sebentar di titik klik supaya klik ganda tepat sasaran
            if (now < stickyUntil && hypot(x - ox, y - oy) < 60f) { tx = ox; ty = oy }
            else {
                stickyUntil = 0L
                if (tx < 0f || hypot(x - tx, y - ty) > 4f) { tx = x; ty = y }   // abaikan getaran kecil saat diam
            }
            hist.addLast(Triple(now, x, y))
            while (hist.isNotEmpty() && now - hist.first().first > 400) hist.removeFirst()

            // mulai cubit: harus terdeteksi 2 frame berturut-turut dan telunjuk tidak terlipat penuh
            if (ps < pinchClose && sI > .55f) pinchN++ else pinchN = 0
            if (pinchN >= 2) {
                val keep = now < stickyUntil
                pinched = true; pinchN = 0; releaseN = 0; dragged = false; pinchStartT = now
                if (!keep) {
                    val hh = hist.firstOrNull { now - it.first <= 200 } ?: hist.lastOrNull()
                    ox = hh?.second ?: x; oy = hh?.third ?: y
                }
                tx = ox; ty = oy; dragX = ox; dragY = oy; lastDragT = now
                tappedAtStart = false
                if (keep && now - lastTapT < 450) {      // cubit kedua cepat = ketukan kedua langsung
                    doTap(ox, oy); tappedAtStart = true; lastTapT = now
                }
            }
        } else {
            if (ps > openThr) releaseN++ else releaseN = 0
            if (releaseN >= 2) {                         // lepas cubit
                if (!dragged && !tappedAtStart) { doTap(ox, oy); lastTapT = now }
                stickyUntil = if (dragged) 0L else now + 450
                pinched = false; releaseN = 0; dragged = false
            } else {
                // cubit singkat butuh geseran jauh lebih besar untuk dianggap seret
                val thr = if (now - pinchStartT < 250) dragThr * 2.5f else dragThr
                if (!dragged && hypot(x - ox, y - oy) > thr) { dragged = true; dragX = ox; dragY = oy }
                if (dragged) {                           // cubit + geser = seret / gulir
                    tx = x; ty = y
                    if (now - lastDragT > 120) {
                        val ex = (dragX + (x - dragX) * dragGain).coerceIn(2f, sw - 2f)
                        val ey = (dragY + (y - dragY) * dragGain).coerceIn(2f, sh - 2f)
                        if (hypot(ex - dragX, ey - dragY) > 25f) {
                            GestureService.swipe(dragX, dragY, ex, ey, 100)
                            dragX = x; dragY = y; lastDragT = now
                        }
                    }
                }
            }
        }
        kick()
        paint(if (dragged) 4 else if (pinched) 1 else 0)
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
import android.widget.SeekBar
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast

class MainActivity : Activity() {
    private lateinit var status: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val prefs = getSharedPreferences("hc", MODE_PRIVATE)
        val box = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(48, 96, 48, 96) }
        fun text(s: String, size: Float = 16f) = TextView(this).apply { this.text = s; textSize = size; setPadding(0, 12, 0, 12) }
        fun btn(s: String, f: () -> Unit) = Button(this).apply { text = s; setOnClickListener { f() } }
        fun slider(title: String, key: String, hint: String) {
            val label = text("$title: ${prefs.getInt(key, 50)}")
            val sb = SeekBar(this).apply {
                max = 100; progress = prefs.getInt(key, 50)
                setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                    override fun onProgressChanged(s: SeekBar?, p: Int, fromUser: Boolean) {
                        label.text = "$title: $p"; prefs.edit().putInt(key, p).apply()
                    }
                    override fun onStartTrackingTouch(s: SeekBar?) {}
                    override fun onStopTrackingTouch(s: SeekBar?) {}
                })
            }
            box.addView(label); box.addView(sb); box.addView(text(hint, 12f))
        }
        fun toggle(title: String, key: String) = Switch(this).apply {
            text = title
            isChecked = prefs.getBoolean(key, false)
            setOnCheckedChangeListener { _, c -> prefs.edit().putBoolean(key, c).apply() }
        }

        box.addView(text("HandCursor", 28f))
        box.addView(text("Gerak: acungkan telunjuk. Klik: cubit jempol+telunjuk lalu lepas. Seret/gulir: cubit, tahan, geser tangan. Jeda: kepalkan tangan."))
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

        box.addView(text("Sensitivitas (berlaku langsung)", 20f))
        slider("Jangkauan kursor", "spd", "Naikkan agar gerakan tangan kecil menjangkau seluruh layar, termasuk tepi.")
        slider("Kehalusan kursor", "smooth", "Naikkan kalau kursor goyang saat diam. Turunkan kalau terasa lambat.")
        slider("Sensitivitas cubit", "pinch", "Naikkan kalau cubit sulit terdeteksi. Turunkan kalau terdeteksi padahal tidak mencubit.")
        slider("Jarak mulai seret", "drag", "Naikkan agar seret lebih cepat dimulai. Turunkan kalau klik sering jadi seret.")
        slider("Kecepatan seret", "gain", "Naikkan agar gulir lebih jauh per gerakan tangan.")
        box.addView(toggle("Gulir dua jari (alternatif)", "two"))
        box.addView(toggle("Info debug (untuk menyetel)", "dbg"))
        box.addView(btn("Atur ulang sensitivitas") { prefs.edit().clear().apply(); recreate() })
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
URL=https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task
OUT=app/src/main/assets/hand_landmarker.task
ok=0
for i in 1 2 3 4; do
  if curl -fL --connect-timeout 20 --max-time 180 -o "$OUT" "$URL"; then
    if [ "$(stat -c%s "$OUT")" -gt 3000000 ]; then ok=1; break; fi
    echo "Ukuran model tidak wajar, mengulang..."
  fi
  echo "Unduhan gagal (percobaan $i), mengulang..."; sleep 5
done
[ "$ok" = 1 ] || { echo "GAGAL: model tangan tidak bisa diunduh"; exit 1; }
echo "Proyek selesai dibuat."
