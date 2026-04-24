package com.jsm.core.webrtc

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.net.wifi.WifiManager
import androidx.core.app.NotificationCompat
import com.jsm.core.R

/**
 * Servicio Militarizado de Android para mantener el flujo WebRTC vivo en Background.
 * Obligatorio en Android 14+ para operar MediaProjection.
 * Adicionalmente, mantiene bloqueos de energía y WiFi para streaming ininterrumpido.
 */
class CaptureForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "ElysiumVanguard_CaptureChannel"
        const val NOTIFICATION_ID = 999
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        acquireLocks()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()
        startForeground(NOTIFICATION_ID, notification)
        
        // El servicio se queda corriendo para mantener ScreenCapturerHook vivo
        return START_NOT_STICKY
    }

    private fun acquireLocks() {
        // Evita que la CPU entre en sueño profundo (Doze) y mate el hilo C++ de WebRTC
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ElysiumVanguard::StreamingWakeLock")
        wakeLock?.acquire(24 * 60 * 60 * 1000L /*24 horas max para seguridad*/)

        // Mantiene el chip de WiFi activo a máxima potencia, crucial para WebRTC P2P
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        wifiLock = wifiManager.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "ElysiumVanguard::StreamingWifiLock")
        wifiLock?.acquire()
    }

    private fun releaseLocks() {
        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
        }
        if (wifiLock?.isHeld == true) {
            wifiLock?.release()
        }
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Elysium Vanguard Active")
            .setContentText("Transmitiendo a macOS (Zero-Latency P2P)")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_MAX) // Prioridad máxima para evitar ser asesinado
            .setOngoing(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Elysium Vanguard Stream",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Mantiene activa la conexión P2P local."
                lightColor = Color.CYAN
            }
            
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null // Usado exclusivamente para Background Lifecycle, no binding IPC.
    }

    override fun onDestroy() {
        super.onDestroy()
        releaseLocks()
    }
}
