import AppKit
import AVFoundation

/// Manejador de la experiencia sensorial y cibernética de alta tecnología. 
/// Detona efectos físicos y digitales sincronizados al microsegundo.
class SensoryFeedbackManager {
    static let shared = SensoryFeedbackManager()
    private var audioPlayer: AVAudioPlayer?
    
    private init() {}
    
    /// Gatillo físico para interacciones pesadas en la app Mac (e.g. Emparejamiento WebRTC exitoso)
    func triggerHapticAlignment() {
        // Usa el Taptic Engine del Mac para una vibración seca y contundente de "Alineamiento"
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
    
    /// Gatillo sutil usado cuando el Magic V2 completa su morphing geométrico
    func triggerHapticLevelChange() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
    
    /// Gatillo usado al hacer click y dejar el rastro del "Radar Pointer" o seleccionar herramientas
    func triggerHapticGeneric() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
    
    // MARK: - Efectos Sonoros (High-Tech / Mecánicos)
    
    func playDigitalConfirmSound() {
        if let url = Bundle.module.url(forResource: "cyber_confirm", withExtension: "wav") {
            audioPlayer = try? AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        } else {
            NSSound(named: "Tink")?.play() 
        }
    }
    
    func playMechanicalClick() {
        if let url = Bundle.module.url(forResource: "mech_click", withExtension: "wav") {
            audioPlayer = try? AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        } else {
            NSSound(named: "Pop")?.play()
        }
    }
}
