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
    private var silentMediaPlayer: android.media.MediaPlayer? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        acquireLocks()
        startSilentAudioHack()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val type = android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION or 
                       android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            startForeground(NOTIFICATION_ID, notification, type)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        
        // El servicio se queda corriendo para mantener ScreenCapturerHook vivo
        return START_NOT_STICKY
    }

    private var silentAudioTrack: android.media.AudioTrack? = null
    private var isPlayingSilence = false

    /**
     * HACK DEFINITIVO PARA HONOR/HUAWEI (MagicOS / EMUI):
     * Power Genie (PG_ash) ignora WakeLocks y ForegroundServices, congelando el Virtual Display
     * y matando sockets a los pocos segundos de pasar al background.
     * La única forma de evitarlo a nivel kernel es simular que somos una app de reproducción de audio activo.
     */
    private fun startSilentAudioHack() {
        try {
            val minSize = android.media.AudioTrack.getMinBufferSize(
                44100, 
                android.media.AudioFormat.CHANNEL_OUT_MONO, 
                android.media.AudioFormat.ENCODING_PCM_16BIT
            )
            silentAudioTrack = android.media.AudioTrack(
                android.media.AudioManager.STREAM_MUSIC,
                44100,
                android.media.AudioFormat.CHANNEL_OUT_MONO,
                android.media.AudioFormat.ENCODING_PCM_16BIT,
                minSize,
                android.media.AudioTrack.MODE_STREAM
            )
            silentAudioTrack?.play()
            isPlayingSilence = true
            
            Thread {
                val silence = ByteArray(minSize)
                while (isPlayingSilence && silentAudioTrack?.playState == android.media.AudioTrack.PLAYSTATE_PLAYING) {
                    silentAudioTrack?.write(silence, 0, silence.size)
                }
            }.start()
        } catch (e: Exception) {
            // Ignorar
        }
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
        isPlayingSilence = false
        silentAudioTrack?.stop()
        silentAudioTrack?.release()
        silentAudioTrack = null
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
