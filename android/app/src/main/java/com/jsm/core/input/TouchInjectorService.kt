package com.jsm.core.input

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Build
import android.util.Log
import android.view.accessibility.AccessibilityEvent

/**
 * Servicio de Accesibilidad para inyección de touch events remotos.
 * Recibe coordenadas normalizadas (0.0-1.0) del Mac vía DataChannel
 * y las convierte en gestos nativos de Android.
 *
 * El usuario debe habilitar este servicio en:
 * Settings → Accessibility → Elysium Remote Control → Enable
 */
class TouchInjectorService : AccessibilityService() {

    companion object {
        private const val TAG = "TouchInjector"
        
        // Referencia estática para acceso desde DataChannel handler
        var instance: TouchInjectorService? = null
        
        /**
         * Inyecta un tap en coordenadas normalizadas (0.0-1.0)
         */
        fun injectTap(normX: Float, normY: Float) {
            instance?.performTap(normX, normY)
        }
        
        /**
         * Inyecta un swipe entre dos puntos normalizados
         */
        fun injectSwipe(fromX: Float, fromY: Float, toX: Float, toY: Float, durationMs: Long = 300) {
            instance?.performSwipe(fromX, fromY, toX, toY, durationMs)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.d(TAG, "✅ TouchInjectorService conectado — control remoto ACTIVO")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // No necesitamos procesar eventos de accesibilidad
    }

    override fun onInterrupt() {
        Log.d(TAG, "⚠️ TouchInjectorService interrumpido")
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        Log.d(TAG, "🛑 TouchInjectorService destruido")
    }

    /**
     * Ejecuta un tap nativo en la pantalla.
     * Coordenadas normalizadas (0.0-1.0) se convierten a píxeles reales.
     */
    private fun performTap(normX: Float, normY: Float) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            Log.w(TAG, "dispatchGesture requiere API 24+")
            return
        }

        val displayMetrics = resources.displayMetrics
        val screenW = displayMetrics.widthPixels.toFloat()
        val screenH = displayMetrics.heightPixels.toFloat()
        
        val x = normX * screenW
        val y = normY * screenH
        
        val path = Path().apply {
            moveTo(x, y)
        }
        
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 100))
            .build()
        
        dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                Log.d(TAG, "👆 Tap dispatched at (${x.toInt()}, ${y.toInt()})")
            }
            override fun onCancelled(gestureDescription: GestureDescription?) {
                Log.w(TAG, "⚠️ Tap cancelled at (${x.toInt()}, ${y.toInt()})")
            }
        }, null)
    }

    /**
     * Ejecuta un swipe nativo en la pantalla.
     */
    private fun performSwipe(fromX: Float, fromY: Float, toX: Float, toY: Float, durationMs: Long) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return

        val displayMetrics = resources.displayMetrics
        val screenW = displayMetrics.widthPixels.toFloat()
        val screenH = displayMetrics.heightPixels.toFloat()
        
        val path = Path().apply {
            moveTo(fromX * screenW, fromY * screenH)
            lineTo(toX * screenW, toY * screenH)
        }
        
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, durationMs))
            .build()
        
        dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                Log.d(TAG, "👆 Swipe dispatched")
            }
        }, null)
    }
}
