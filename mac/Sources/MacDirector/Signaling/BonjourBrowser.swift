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
                if case let .service(name, type, domain, interface) = result.endpoint {
                    print("Found service: \(name), interface: \(String(describing: interface))")
                    // Aquí resolveremos el Endpoint a una IP directa para inyectarlo al RTC
                    self?.resolveEndpoint(result.endpoint)
                }
            }
        }
        
        browser?.start(queue: .main)
    }
    
    private func resolveEndpoint(_ endpoint: NWEndpoint) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let endpoint = connection.currentPath?.remoteEndpoint,
                   case let .hostPort(host, port) = endpoint {
                    DispatchQueue.main.async {
                        self?.discoveredHost = host
                        self?.discoveredPort = port
                        self?.isSearching = false
                    }
                    // Cancelamos conexión una vez tenemos la IP, WebRTC se hace cargo.
                    connection.cancel()
                }
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
