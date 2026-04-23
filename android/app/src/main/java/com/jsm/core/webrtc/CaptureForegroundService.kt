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
import androidx.core.app.NotificationCompat
import com.jsm.core.R

/**
 * Servicio Militarizado de Android para mantener el flujo WebRTC vivo en Background.
 * Obligatorio en Android 14+ para operar MediaProjection.
 */
class CaptureForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "ElysiumVanguard_CaptureChannel"
        const val NOTIFICATION_ID = 999
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()
        startForeground(NOTIFICATION_ID, notification)
        
        // El servicio se queda corriendo para mantener ScreenCapturerHook vivo
        return START_NOT_STICKY
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Elysium Vanguard Active")
            .setContentText("Transmitiendo a macOS (Zero-Latency P2P)")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
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
}
