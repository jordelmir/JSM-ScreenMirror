import Foundation
import Network

/// Cliente de red TCP persistente para intercambio WebRTC completo con Android.
///
/// Protocolo: JSON delimitado por newlines sobre TCP.
/// Tipos de mensaje:
///   {"type":"offer","sdp":"<base64>"}
///   {"type":"answer","sdp":"<base64>"}
///   {"type":"ice","candidate":"...","sdpMid":"...","sdpMLineIndex":0}
///
/// Reconexión:
///   Si la conexión se pierde, reintenta cada 3 segundos automáticamente
///   hasta que se llame `disconnect()` o se establezca la conexión.
class SignalingClient: ObservableObject {
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var lastHost: NWEndpoint.Host?
    private var lastPort: NWEndpoint.Port?
    private var reconnectTimer: DispatchSourceTimer?
    private var intentionalDisconnect = false
    
    @Published var isConnected = false
    
    var onSDPOfferReceived: ((String) -> Void)?
    var onRemoteIceCandidateReceived: ((String, String?, Int) -> Void)?
    
    init() {}
    
    func connect(to host: NWEndpoint.Host, port: NWEndpoint.Port) {
        intentionalDisconnect = false
        lastHost = host
        lastPort = port
        stopReconnectTimer()
        
        // Cancelar conexión anterior si existe
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        
        let tcpParams = NWProtocolTCP.Options()
        tcpParams.noDelay = true  // Nagle off — latencia mínima para signaling
        tcpParams.connectionTimeout = 5
        let params = NWParameters(tls: nil, tcp: tcpParams)
        
        connection = NWConnection(host: host, port: port, using: params)
        
        connection?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                print("Signaling: Conectado a Android en \(host):\(port)")
                DispatchQueue.main.async {
                    self.isConnected = true
                }
                self.receiveBuffer = Data()
                self.stopReconnectTimer()
                self.receiveLoop()
                
            case .failed(let error):
                print("Signaling: Fallo de conexión: \(error)")
                DispatchQueue.main.async {
                    self.isConnected = false
                }
                self.scheduleReconnect()
                
            case .cancelled:
                DispatchQueue.main.async {
                    self.isConnected = false
                }
                if !self.intentionalDisconnect {
                    self.scheduleReconnect()
                }
                
            default:
                break
            }
        }
        
        connection?.start(queue: .global(qos: .userInitiated))
    }
    
    // ═══════════════════════════════════════════════════════════
    //  ENVÍO DE MENSAJES
    // ═══════════════════════════════════════════════════════════
    
    /// Envía el SDP Answer al Android como mensaje JSON
    func sendAnswer(sdp: String) {
        guard let sdpData = sdp.data(using: .utf8) else { return }
        let b64 = sdpData.base64EncodedString()
        
        sendJSON(["type": "answer", "sdp": b64])
    }
    
    /// Envía un ICE candidate local al Android
    func sendIceCandidate(candidate: String, sdpMid: String?, sdpMLineIndex: Int32) {
        sendJSON([
            "type": "ice",
            "candidate": candidate,
            "sdpMid": sdpMid ?? "",
            "sdpMLineIndex": sdpMLineIndex
        ])
    }
    
    private func sendJSON(_ dict: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dict),
              var jsonString = String(data: jsonData, encoding: .utf8) else {
            print("Signaling: Error serializando JSON")
            return
        }
        
        jsonString += "\n"
        guard let data = jsonString.data(using: .utf8) else { return }
        
        connection?.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                print("Signaling: Error enviando: \(error)")
            }
        }))
    }
    
    // ═══════════════════════════════════════════════════════════
    //  RECEPCIÓN DE MENSAJES
    // ═══════════════════════════════════════════════════════════
    
    /// Loop de lectura persistente que procesa mensajes JSON delimitados por newlines
    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 70000) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let data = data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.processBuffer()
            }
            
            if error == nil && !isComplete {
                self.receiveLoop()
            } else {
                print("Signaling: Conexión cerrada. Complete=\(isComplete), Error=\(String(describing: error))")
                DispatchQueue.main.async {
                    self.isConnected = false
                }
                if !self.intentionalDisconnect {
                    self.scheduleReconnect()
                }
            }
        }
    }
    
    /// Procesa el buffer buscando mensajes JSON completos (delimitados por \n)
    private func processBuffer() {
        guard let str = String(data: receiveBuffer, encoding: .utf8) else { return }
        
        let lines = str.components(separatedBy: "\n")
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if index == lines.count - 1 {
                // Último fragmento: podría ser mensaje parcial — conservar en buffer
                receiveBuffer = trimmed.data(using: .utf8) ?? Data()
                break
            }
            
            guard !trimmed.isEmpty else { continue }
            
            do {
                guard let jsonData = trimmed.data(using: .utf8),
                      let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                      let type = json["type"] as? String else {
                    print("Signaling: Mensaje inválido: \(trimmed.prefix(80))")
                    continue
                }
                
                switch type {
                case "offer":
                    if let sdpB64 = json["sdp"] as? String,
                       let sdpData = Data(base64Encoded: sdpB64),
                       let sdpOffer = String(data: sdpData, encoding: .utf8) {
                        print("Signaling: SDP Offer decodificada (\(sdpOffer.count) chars)")
                        self.onSDPOfferReceived?(sdpOffer)
                    } else {
                        print("Signaling: Error decodificando SDP Offer Base64")
                    }
                    
                case "ice":
                    if let candidate = json["candidate"] as? String {
                        let sdpMid = json["sdpMid"] as? String
                        let sdpMLineIndex = json["sdpMLineIndex"] as? Int ?? 0
                        print("Signaling: ICE candidate recibido del Android")
                        self.onRemoteIceCandidateReceived?(candidate, sdpMid, sdpMLineIndex)
                    }
                    
                default:
                    print("Signaling: Tipo desconocido: \(type)")
                }
            } catch {
                print("Signaling: Error parseando: \(error), raw: \(trimmed.prefix(80))")
            }
        }
    }
    
    // ═══════════════════════════════════════════════════════════
    //  RECONEXIÓN AUTOMÁTICA
    // ═══════════════════════════════════════════════════════════
    
    private func scheduleReconnect() {
        guard !intentionalDisconnect, let host = lastHost, let port = lastPort else { return }
        
        stopReconnectTimer()
        
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 3.0)
        timer.setEventHandler { [weak self] in
            print("Signaling: Intentando reconexión a \(host):\(port)...")
            self?.connect(to: host, port: port)
        }
        timer.resume()
        reconnectTimer = timer
    }
    
    private func stopReconnectTimer() {
        reconnectTimer?.cancel()
        reconnectTimer = nil
    }
    
    func disconnect() {
        intentionalDisconnect = true
        stopReconnectTimer()
        connection?.cancel()
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
}
