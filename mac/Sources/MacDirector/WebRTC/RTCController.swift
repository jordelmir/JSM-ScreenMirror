import Foundation
import WebRTC

/// Gestor completo del PeerConnection WebRTC para la Mac (lado receptor).
/// Maneja: SDP negociación, ICE candidate exchange, DataChannel para metadatos, video track.
class RTCController: NSObject, ObservableObject {
    private var peerConnectionFactory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection?
    let videoSink = RTCVideoSink()
    
    // ICE candidate callback — se conecta al SignalingClient
    var onLocalIceCandidate: ((RTCIceCandidate) -> Void)?
    
    // Estado observable de la conexión P2P
    @Published var iceConnectionState: RTCIceConnectionState = .new
    @Published var isP2PConnected = false
    @Published var currentVideoTrack: RTCVideoTrack?
    @Published var latestPixelBuffer: CVPixelBuffer?
    
    // DataChannel callback para metadatos del Android (fold state, orientación)
    var onDataChannelMessage: ((String) -> Void)?
    
    // Configuración base P2P (Sin STUN en v1 para latencia pura LAN)
    private let rtcConfig: RTCConfiguration = {
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        // Bloqueamos priorización externa, todo candidato será interno (LAN Host)
        config.iceServers = []
        return config
    }()
    
    override init() {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        
        // El factor importante: el SDK intentará delegar esto a VideoToolbox si puede.
        self.peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: videoEncoderFactory,
            decoderFactory: videoDecoderFactory
        )
        super.init()
    }
    
    func createPeerConnection() {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        peerConnection = peerConnectionFactory.peerConnection(with: rtcConfig, constraints: constraints, delegate: self)
        print("WebRTC PeerConnection creado. Preparado para recibir Offer/SDP.")
    }
    
    /// Recibe el SDP Offer del Android y genera la Answer
    func handleRemoteOffer(sdp: String, completion: @escaping (String) -> Void) {
        // [Crítico]: Forzar H264 para que el engine en Mac use aceleración por hardware (VideoToolbox)
        // y nos devuelva RTCCVPixelBuffer en lugar de RTCI420Buffer.
        var modifiedSdp = sdp
            .replacingOccurrences(of: "VP8", with: "DISABLE_VP8")
            .replacingOccurrences(of: "VP9", with: "DISABLE_VP9")
        
        let sessionDescription = RTCSessionDescription(type: .offer, sdp: modifiedSdp)
        
        peerConnection?.setRemoteDescription(sessionDescription) { [weak self] error in
            guard error == nil else {
                print("Error seteando Remote SDP: \(error!)")
                return
            }
            self?.createAnswer(completion: completion)
        }
    }
    
    private func createAnswer(completion: @escaping (String) -> Void) {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        peerConnection?.answer(for: constraints) { [weak self] sdp, error in
            guard let sdp = sdp, error == nil else { return }
            
            self?.peerConnection?.setLocalDescription(sdp) { error in
                if error == nil {
                    completion(sdp.sdp)
                } else {
                    print("Error seteando Local SDP: \(error!)")
                }
            }
        }
    }
    
    /// Aplica un ICE candidate recibido del Android via signaling
    func addRemoteIceCandidate(candidate: String, sdpMid: String?, sdpMLineIndex: Int) {
        let iceCandidate = RTCIceCandidate(
            sdp: candidate,
            sdpMLineIndex: Int32(sdpMLineIndex),
            sdpMid: sdpMid
        )
        peerConnection?.add(iceCandidate) { error in
            if let error = error {
                print("Error aplicando ICE candidate remoto: \(error)")
            } else {
                print("ICE candidate remoto aplicado exitosamente")
            }
        }
    }
    
    /// Limpieza completa de recursos WebRTC.
    /// Debe llamarse antes de liberar la instancia.
    func dispose() {
        peerConnection?.close()
        peerConnection = nil
        onLocalIceCandidate = nil
        onDataChannelMessage = nil
        RTCCleanupSSL()
        print("RTCController disposed.")
    }
}

// MARK: - PeerConnection Delegate
extension RTCController: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("Signaling State: \(stateChanged.rawValue)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        // [Crítico]: WebRTC ejecuta esto en su hilo C++ worker interno (Signaling Thread)
        DispatchQueue.main.async {
            print("✅ Track de video inyectado desde Android. Tracks: \(stream.videoTracks.count)")
            if let videoTrack = stream.videoTracks.first {
                videoTrack.add(self.videoSink)
                self.currentVideoTrack = videoTrack
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("Stream removido del Android")
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("Renegociación necesaria")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        let stateName: String
        switch newState {
        case .new: stateName = "NEW"
        case .checking: stateName = "CHECKING"
        case .connected: stateName = "CONNECTED"
        case .completed: stateName = "COMPLETED"
        case .failed: stateName = "FAILED"
        case .disconnected: stateName = "DISCONNECTED"
        case .closed: stateName = "CLOSED"
        case .count: stateName = "COUNT"
        @unknown default: stateName = "UNKNOWN"
        }
        
        print("ICE Connection State: \(stateName)")
        
        DispatchQueue.main.async {
            self.iceConnectionState = newState
            self.isP2PConnected = (newState == .connected || newState == .completed)
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        let stateName: String
        switch newState {
        case .new: stateName = "NEW"
        case .gathering: stateName = "GATHERING"
        case .complete: stateName = "COMPLETE"
        @unknown default: stateName = "UNKNOWN"
        }
        print("ICE Gathering State: \(stateName)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        print("ICE candidate local generado: \(candidate.sdp.prefix(60))...")
        // Enviar ICE a Android vía Signaling Socket
        onLocalIceCandidate?(candidate)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("✅ DataChannel P2P abierto: '\(dataChannel.label)' (id: \(dataChannel.channelId))")
        dataChannel.delegate = self
    }
}

// MARK: - DataChannel Delegate
extension RTCController: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        print("DataChannel '\(dataChannel.label)' state: \(dataChannel.readyState.rawValue)")
    }
    
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard let message = String(data: buffer.data, encoding: .utf8) else { return }
        print("DataChannel ← \(message)")
        
        // Despachar en el main thread para mutar UI/Layout
        Task { @MainActor in
            self.onDataChannelMessage?(message)
        }
    }
}
