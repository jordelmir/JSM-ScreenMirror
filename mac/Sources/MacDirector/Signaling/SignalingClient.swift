import Foundation
import Network

/// Cliente de red TCP especializado en el apretón de manos (Handshake) con Android.
/// Intercambia SDP codificados en Base64 para evitar truncamientos.
class SignalingClient: ObservableObject {
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    
    var onSDPOfferReceived: ((String) -> Void)?
    
    func connect(to host: NWEndpoint.Host, port: NWEndpoint.Port) {
        connection = NWConnection(host: host, port: port, using: .tcp)
        
        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Signaling: Conectado a Honor Magic V2 en \(host):\(port)")
                self?.receiveBuffer = Data()
                self?.receiveData()
            case .failed(let error):
                print("Signaling: Fallo de conexión: \(error)")
            default:
                break
            }
        }
        
        connection?.start(queue: .global())
    }
    
    func sendAnswer(sdp: String) {
        guard let sdpData = sdp.data(using: .utf8) else { return }
        let b64 = sdpData.base64EncodedString() + "\n"
        guard let b64Data = b64.data(using: .utf8) else { return }
        
        connection?.send(content: b64Data, completion: .contentProcessed({ error in
            if let error = error {
                print("Signaling: Error enviando Answer: \(error)")
            } else {
                print("Signaling: Answer Base64 enviada con éxito.")
            }
        }))
    }
    
    private func receiveData() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 70000) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            
            if let data = data, !data.isEmpty {
                self.receiveBuffer.append(data)
                
                // Procesamos si hemos recibido salto de línea (fin del Base64)
                if let str = String(data: self.receiveBuffer, encoding: .utf8), let newlineRange = str.range(of: "\n") {
                    let extractedB64 = String(str[..<newlineRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if let sdpData = Data(base64Encoded: extractedB64), let sdpOffer = String(data: sdpData, encoding: .utf8) {
                        print("Signaling: SDP Offer decodificada exitosamente.")
                        self.onSDPOfferReceived?(sdpOffer)
                    } else {
                        print("Signaling: Error decodificando Offer en Base64.")
                    }
                    self.receiveBuffer.removeAll()
                }
            }
            
            if error == nil && !isComplete {
                self.receiveData()
            }
        }
    }
    
    func disconnect() {
        connection?.cancel()
    }
}
