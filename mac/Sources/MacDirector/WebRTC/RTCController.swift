import Foundation
import WebRTC

/// Gestor del PeerConnection y la pista de video recibida
class RTCController: NSObject, ObservableObject {
    private var peerConnectionFactory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection?
    let videoSink = RTCVideoSink()
    
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
    
    /// Recibe el SDP Offer crudo desde Bonjour Socket
    func handleRemoteOffer(sdp: String, completion: @escaping (String) -> Void) {
        let sessionDescription = RTCSessionDescription(type: .offer, sdp: sdp)
        
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
                    // Exportamos la espuesta al Socket Bonjour
                    completion(sdp.sdp)
                }
            }
        }
    }
}

extension RTCController: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        // [Crítico]: WebRTC ejecuta esto en su hilo C++ worker interno (Signaling Thread)
        DispatchQueue.main.async {
            print("Track de video inyectado desde Android.")
            if let videoTrack = stream.videoTracks.first {
                videoTrack.add(self.videoSink)
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
        dataChannel.delegate = self
    }
}

extension RTCController: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {}
    
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard let message = String(data: buffer.data, encoding: .utf8) else { return }
        print("DataChannel Command: \(message)")
        
        // V1: Parser directo para mutar Layout PIP de Honor Magic V2 en Mac Director
        Task { @MainActor in
            if message == "FOLD_CLOSED" {
                // Notificar al LayoutEngine (via EventBus o Delegate)
            } else if message == "FOLD_OPENED" {
                // Expandir PIP Android a Tablet
            }
        }
    }
}
