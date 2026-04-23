package com.jsm.core.signaling

import android.util.Log
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.PrintWriter
import java.net.ServerSocket
import java.net.Socket
import kotlin.concurrent.thread

class SignalingServer(
    private val port: Int,
    private val onOfferRequested: (sendOffer: (String) -> Unit) -> Unit,
    private val onAnswerReceived: (String) -> Unit
) {
    private var serverSocket: ServerSocket? = null
    private var isRunning = false

    fun start() {
        isRunning = true
        thread {
            try {
                serverSocket = ServerSocket(port)
                Log.d("SignalingServer", "Listening on port $port")
                while (isRunning) {
                    val clientSocket = serverSocket?.accept()
                    clientSocket?.let { handleClient(it) }
                }
            } catch (e: Exception) {
                Log.e("SignalingServer", "Server error", e)
            }
        }
    }

    private fun handleClient(socket: Socket) {
        thread {
            try {
                val reader = BufferedReader(InputStreamReader(socket.getInputStream()))
                val writer = PrintWriter(socket.getOutputStream(), true)

                // Flujo Pro: En cuanto se conecta la Mac, le enviamos la Offer.
                Log.d("SignalingServer", "Mac connected. Requesting WebRTC Offer...")
                
                onOfferRequested { sdpOffer ->
                    val b64Offer = android.util.Base64.encodeToString(sdpOffer.toByteArray(Charsets.UTF_8), android.util.Base64.NO_WRAP)
                    writer.println(b64Offer)
                    Log.d("SignalingServer", "SDP Offer sent to Mac (Base64).")
                }

                // Esperamos la Answer de la Mac (Codificada en Base64 Lineal)
                val sdpAnswerB64 = reader.readLine()
                if (sdpAnswerB64 != null) {
                    val decodedBytes = android.util.Base64.decode(sdpAnswerB64, android.util.Base64.DEFAULT)
                    val sdpAnswer = String(decodedBytes, Charsets.UTF_8)
                    Log.d("SignalingServer", "SDP Answer received from Mac.")
                    onAnswerReceived(sdpAnswer)
                }

            } catch (e: Exception) {
                Log.e("SignalingServer", "Client handling error", e)
            } finally {
                // socket.close() // Mantendremos vivo el stream en v1 si es necesario
            }
        }
    }

    fun stop() {
        isRunning = false
        serverSocket?.close()
    }
}
