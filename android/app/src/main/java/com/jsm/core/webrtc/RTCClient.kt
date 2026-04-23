package com.jsm.core.webrtc

import android.content.Context
import android.content.Intent
import android.util.Log
import org.webrtc.*

class RTCClient(
    private val context: Context,
    private val observer: PeerConnection.Observer
) {
    private val rootEglBase: EglBase = EglBase.create()
    private var pcFactory: PeerConnectionFactory? = null
    private var peerConnection: PeerConnection? = null
    private var screenCapturerHook = ScreenCapturerHook(context)

    init {
        initPeerConnectionFactory(context)
        pcFactory = createPeerConnectionFactory()
    }

    private fun initPeerConnectionFactory(context: Context) {
        val options = PeerConnectionFactory.InitializationOptions.builder(context)
            .setEnableInternalTracer(true)
            .setFieldTrials("WebRTC-H264HighProfile/Enabled/")
            .createInitializationOptions()
        PeerConnectionFactory.initialize(options)
    }

    private fun createPeerConnectionFactory(): PeerConnectionFactory {
        return PeerConnectionFactory.builder()
            .setVideoEncoderFactory(DefaultVideoEncoderFactory(rootEglBase.eglBaseContext, true, true))
            .setVideoDecoderFactory(DefaultVideoDecoderFactory(rootEglBase.eglBaseContext))
            .createPeerConnectionFactory()
    }

    fun startStreaming(projectionData: Intent) {
        val rtcConfig = PeerConnection.RTCConfiguration(emptyList()).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
        }
        
        peerConnection = pcFactory?.createPeerConnection(rtcConfig, observer)
        
        val videoTrack = screenCapturerHook.createVideoTrack(
            pcFactory!!,
            rootEglBase.eglBaseContext,
            projectionData
        )
        
        videoTrack?.let {
            peerConnection?.addTrack(it, listOf("JSM_STREAM"))
            Log.d("RTCClient", "Video track added to PeerConnection")
        }
    }

    fun createOffer(callback: (SessionDescription) -> Unit) {
        val constraints = MediaConstraints()
        peerConnection?.createOffer(object : SdpObserver {
            override fun onCreateSuccess(sdp: SessionDescription) {
                peerConnection?.setLocalDescription(object : SdpObserver {
                    override fun onSetSuccess() = callback(sdp)
                    override fun onSetFailure(s: String?) { Log.e("RTCClient", "Local SDP Error: $s") }
                    override fun onCreateSuccess(sdp: SessionDescription) {}
                    override fun onCreateFailure(s: String?) {}
                }, sdp)
            }
            override fun onCreateFailure(p0: String?) {}
            override fun onSetSuccess() {}
            override fun onSetFailure(p0: String?) {}
        }, constraints)
    }

    fun setRemoteDescription(sdp: SessionDescription) {
        peerConnection?.setRemoteDescription(object : SdpObserver {
            override fun onSetSuccess() { Log.d("RTCClient", "Remote Answer Set Success") }
            override fun onSetFailure(s: String?) { Log.e("RTCClient", "Remote SDP Error: $s") }
            override fun onCreateSuccess(p0: SessionDescription?) {}
            override fun onCreateFailure(p0: String?) {}
        }, sdp)
    }
}
