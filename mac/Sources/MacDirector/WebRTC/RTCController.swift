import Foundation
import WebRTC

/// Gestor del PeerConnection y la pista de video recibida
class RTCController: NSObject, ObservableObject {
    private var peerConnectionFactory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection?
    
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
}

extension RTCController: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        // [Crítico]: WebRTC ejecuta esto en su hilo C++ worker interno (Signaling Thread)
        // Despachamos a una cola de renderizado dedicada para procesar hardware bytes
        DispatchQueue.global(qos: .userInteractive).async {
            print("Track H.265/H.264 recibido remotamente de Android.")
            guard let videoTrack = stream.videoTracks.first else { return }
            
            // Aquí transferiremos el RTCVideoTrack a nuestro lienzo de Metal.
            // Para actualizar estados de UI (ej: isConnected), obligatoriamente saltamos a MainActor
            Task { @MainActor in
                // Ejemplo: HUDOverlayView state update
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        // Enviar ICE a Android vía Signaling Socket
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("DataChannel P2P abierto para metadatos (Orientation, Fold State)")
    }
}
