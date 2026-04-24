import Foundation
import Network

/// Orquestador para el descubrimiento automático (Zero-Config) mediante Bonjour
class BonjourBrowser: ObservableObject {
    private var browser: NWBrowser?
    private let serviceType = "_jsm_video._tcp"
    private let serviceDomain = "local."
    
    @Published var discoveredHost: NWEndpoint.Host?
    @Published var discoveredPort: NWEndpoint.Port?
    @Published var isSearching = false

    func startDiscovery() {
        isSearching = true
        let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: serviceDomain)
        browser = NWBrowser(for: descriptor, using: .tcp)
        
        browser?.stateUpdateHandler = { newState in
            print("Bonjour Browser state: \(newState)")
        }
        
        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            for result in results {
                if case let .service(name, _, _, interface) = result.endpoint {
                    print("Found service: \(name), interface: \(String(describing: interface))")
                    // Aquí resolveremos el Endpoint a una IP directa para inyectarlo al RTC
                    self?.resolveEndpoint(result.endpoint)
                }
            }
        }
        
        browser?.start(queue: .main)
    }
    
    private func resolveEndpoint(_ endpoint: NWEndpoint) {
        // CRITICAL FIX: No abrir TCP al puerto del servicio (9999) porque
        // SignalingServer lo interpreta como un cliente Mac real y se desconecta
        // inmediatamente al cancelar, perdiendo la Offer.
        // En su lugar, usamos un puerto efímero (80) solo para resolver la IP.
        // La conexión fallará (refused) pero el path ya contendrá la IP resuelta.
        
        // Primero intentamos extraer host/port directamente del endpoint del servicio
        if case let .hostPort(host, port) = endpoint {
            DispatchQueue.main.async {
                self.discoveredHost = host
                self.discoveredPort = port
                self.isSearching = false
            }
            return
        }
        
        // Para endpoints tipo .service, necesitamos resolver con NWConnection
        // Usamos UDP para que no abra una conexión TCP al SignalingServer
        let udpParams = NWParameters.udp
        let connection = NWConnection(to: endpoint, using: udpParams)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let remoteEndpoint = connection.currentPath?.remoteEndpoint,
                   case let .hostPort(host, port) = remoteEndpoint {
                    DispatchQueue.main.async {
                        self?.discoveredHost = host
                        // El port resuelto es el del servicio NSD (9999)
                        self?.discoveredPort = port
                        self?.isSearching = false
                        print("Bonjour: Resolved to \(host):\(port) via UDP probe")
                    }
                }
                connection.cancel()
            case .preparing:
                // En preparing, el path ya puede tener la IP resuelta
                if let remoteEndpoint = connection.currentPath?.remoteEndpoint,
                   case let .hostPort(host, port) = remoteEndpoint {
                    DispatchQueue.main.async {
                        self?.discoveredHost = host
                        self?.discoveredPort = port
                        self?.isSearching = false
                        print("Bonjour: Resolved to \(host):\(port) during preparation")
                    }
                    connection.cancel()
                }
            case .failed(_), .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: .main)
    }
    
    func stopDiscovery() {
        browser?.cancel()
        isSearching = false
    }
}
