package com.jsm.core

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import android.content.Intent
import android.content.Context
import android.media.projection.MediaProjectionManager
import com.jsm.core.sensory.SensoryFeedbackManager
import com.jsm.core.signaling.NsdBroadcaster
import com.jsm.core.signaling.SignalingServer
import com.jsm.core.webrtc.CaptureForegroundService
import com.jsm.core.webrtc.RTCClient
import org.webrtc.IceCandidate
import org.webrtc.MediaStream
import org.webrtc.PeerConnection
import org.webrtc.SessionDescription
import org.webrtc.DataChannel
import org.webrtc.RtpReceiver

class MainActivity : ComponentActivity() {

    private lateinit var nsdBroadcaster: NsdBroadcaster
    private lateinit var sensoryFeedback: SensoryFeedbackManager
    private var rtcClient: RTCClient? = null
    private var signalingServer: SignalingServer? = null
    
    private val RECORD_REQUEST_CODE = 999
    private var isBroadcastingState = mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        nsdBroadcaster = NsdBroadcaster(this)
        sensoryFeedback = SensoryFeedbackManager(this)

        setContent {
            MaterialTheme(colorScheme = darkColorScheme(background = Color(0xFF0F0F13))) {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    CyberPunkControlPanel()
                }
            }
        }
    }

    private fun startMediaProjectionRequest() {
        val mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        startActivityForResult(mediaProjectionManager.createScreenCaptureIntent(), RECORD_REQUEST_CODE)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == RECORD_REQUEST_CODE && resultCode == RESULT_OK && data != null) {
            bootWebRTC(data)
        } else {
            isBroadcastingState.value = false
        }
    }

    private fun bootWebRTC(projectionData: Intent) {
        val pcObserver = object : PeerConnection.Observer {
            override fun onIceCandidate(candidate: IceCandidate) {}
            override fun onAddStream(stream: MediaStream) {}
            override fun onSignalingChange(p0: PeerConnection.SignalingState?) {}
            override fun onIceConnectionChange(p0: PeerConnection.IceConnectionState?) {}
            override fun onIceConnectionReceivingChange(p0: Boolean) {}
            override fun onIceGatheringChange(p0: PeerConnection.IceGatheringState?) {}
            override fun onIceCandidatesRemoved(p0: Array<out IceCandidate>?) {}
            override fun onRemoveStream(p0: MediaStream?) {}
            override fun onDataChannel(p0: DataChannel?) {}
            override fun onRenegotiationNeeded() {}
            override fun onAddTrack(p0: RtpReceiver?, p1: Array<out MediaStream>?) {}
        }

        rtcClient = RTCClient(this, pcObserver)
        rtcClient?.startStreaming(projectionData)

        signalingServer = SignalingServer(
            port = 9999,
            onOfferRequested = { sendOffer ->
                rtcClient?.createOffer { sdp ->
                    sendOffer(sdp.description)
                }
            },
            onAnswerReceived = { sdpAnswer ->
                rtcClient?.setRemoteDescription(SessionDescription(SessionDescription.Type.ANSWER, sdpAnswer))
                sensoryFeedback.triggerPairingSuccess()
            }
        )
        signalingServer?.start()
    }

    @Composable
    fun CyberPunkControlPanel() {
        var isBroadcasting by isBroadcastingState

        Column(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = "Elysium Vanguard Link",
                color = Color(0xFF00E5FF),
                style = MaterialTheme.typography.headlineLarge.copy(fontWeight = FontWeight.Bold)
            )
            
            Spacer(modifier = Modifier.height(60.dp))
            
            Button(
                onClick = {
                    isBroadcasting = !isBroadcasting
                    if (isBroadcasting) {
                        nsdBroadcaster.startBroadcasting(9999)
                        
                        // Encender Inmunidad de Sistema Android 14+
                        val serviceIntent = Intent(this@MainActivity, CaptureForegroundService::class.java)
                        startForegroundService(serviceIntent)
                        
                        // Solicitar captura de pantalla
                        startMediaProjectionRequest()
                    } else {
                        nsdBroadcaster.stopBroadcasting()
                        signalingServer?.stop()
                        stopService(Intent(this@MainActivity, CaptureForegroundService::class.java))
                    }
                },
                shape = RoundedCornerShape(12.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (isBroadcasting) Color(0xFF00E5FF).copy(alpha = 0.2f) else Color.DarkGray
                ),
                elevation = ButtonDefaults.buttonElevation(
                    defaultElevation = if (isBroadcasting) 20.dp else 0.dp
                ),
                modifier = Modifier
                    .width(200.dp)
                    .height(60.dp)
            ) {
                Text(
                    text = if (isBroadcasting) "Sincronizando..." else "Iniciar Enlace WebRTC",
                    color = if (isBroadcasting) Color(0xFF00E5FF) else Color.White
                )
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        nsdBroadcaster.stopBroadcasting()
    }
}
