import Foundation
import AppKit

@MainActor
class HotKeyObserver: ObservableObject {
    
    enum LayoutMode: Int {
        case hidden = 1
        case cornerPIP = 2
        case splitScreen = 3
    }
    
    @Published var currentLayout: LayoutMode = .cornerPIP
    
    private var globalEventMonitor: Any?
    
    init() {
        startObserving()
    }
    
    private func startObserving() {
        // macOS Global Keyword Hook: Permite interceptar eventos mientras la app graba en el fondo
        let options: NSEvent.EventTypeMask = [.keyDown]
        
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: options) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        
        // También observamos si la app *SÍ* tiene el foco
        NSEvent.addLocalMonitorForEvents(matching: options) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        // Validación de modifiers: Option + Command (Para evitar interferencias ruidosas globales)
        guard event.modifierFlags.contains(.command) && event.modifierFlags.contains(.option) else { return }
        
        switch event.keyCode {
        case 18: // '1' - Esconder Android
            currentLayout = .hidden
            playHaptic(.hidden)
        case 19: // '2' - PIP / Monolito Flotante
            currentLayout = .cornerPIP
            playHaptic(.cornerPIP)
        case 20: // '3' - Panel Dividido
            currentLayout = .splitScreen
            playHaptic(.splitScreen)
        default:
            break
        }
    }
    
    private func playHaptic(_ layout: LayoutMode) {
        switch layout {
        case .hidden:
            SensoryFeedbackManager.shared.playDigitalConfirmSound()
        case .cornerPIP:
            SensoryFeedbackManager.shared.playMechanicalClick()
        case .splitScreen:
            SensoryFeedbackManager.shared.playDigitalConfirmSound()
        }
    }
    
    deinit {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
