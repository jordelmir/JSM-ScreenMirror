import Foundation
import WebRTC
import CoreVideo

/// Receptor de frames de video provenientes de WebRTC (Android).
/// Actúa como el puente final hacia el compositor de Metal.
class RTCVideoSink: NSObject, RTCVideoRenderer {
    
    var onFrameReceived: ((CVPixelBuffer) -> Void)?
    
    // WebRTC llama a esto cada vez que llega un nuevo frame decodificado por hardware.
    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame = frame else { return }
        
        // El Honor Magic V2 enviará frames vía VideoToolbox (Hardware).
        // Extraemos directamente el CVPixelBuffer para evitar copias costosas.
        if let buffer = frame.buffer as? RTCCVPixelBuffer {
            onFrameReceived?(buffer.pixelBuffer)
        } else {
            // Manejo de fallback para frames en otros formatos de memoria (ej: I420)
            print("WebRTC Frame Type: \(String(describing: type(of: frame.buffer)))")
        }
    }
    
    func setSize(_ size: CGSize) {
        print("WebRTC Stream Size Changed: \(size.width)x\(size.height)")
    }
}
