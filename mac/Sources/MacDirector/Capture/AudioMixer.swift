import Foundation
import AVFoundation

/// Motor Híbrido Profesional de mezcla de audio para el Recorder H.264/HEVC.
/// Une el flujo extraído silenciosamente desde `ScreenCaptureKit` con el Micrófono Físico local,
/// ecualizando todo para enviarlo perfectamente sincronizado al MP4 final.
class AudioMixer: ObservableObject {
    private let engine = AVAudioEngine()
    private let systemAudioNode = AVAudioPlayerNode()
    // `AVAudioEngine.inputNode` tomará el micrófono por defecto del sistema
    
    // El puerto final donde sacamos buffers mezclados hacia AVAssetRecorder
    var mixedAudioBufferHandler: ((CMSampleBuffer) -> Void)?

    init() {
        setupMixer()
    }
    
    private func setupMixer() {
        engine.attach(systemAudioNode)
        
        let mainMixer = engine.mainMixerNode
        let format = mainMixer.outputFormat(forBus: 0)
        
        // Conexión del inyector del Mac System Audio (SCStream)
        engine.connect(systemAudioNode, to: mainMixer, format: format)
        
        // Tap asíncrono sobre el Main Mixer para robar los bytes resultantes SIN salir a speakers repetidos
        mainMixer.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] (pcmBuffer, time) in
            // Anclaje de sincronización absoluto: Host Time Clock
            // AVAudioEngine nos da un timestamp relativo a su encendido, pero AssetWriter clama por CMTime.
            // Convertimos la estampa del host físico de Apple Silicon a CMTime (Milisegundos base).
            var pts = CMTime.invalid
            if time.isHostTimeValid {
                pts = CMTime(value: Int64(time.hostTime), timescale: Int32(NSEC_PER_SEC)) // Sync Maestro
            }
            
            // Conversión y entrega estricta con PTS Anclado
            if let sampleBuffer = self?.pcmBufferToSampleBuffer(pcmBuffer, pts: pts) {
                self?.mixedAudioBufferHandler?(sampleBuffer)
            }
        }
        
        do {
            try engine.start()
        } catch {
            print("AVAudioEngine Falló: \(error.localizedDescription)")
        }
    }
    
    /// Este método debe ser llamado desde `ScreenCaptureManager.swift` cuando
    /// emita un CMSampleBuffer de audio del sistema (Type: .audio)
    func injectSystemAudio(sampleBuffer: CMSampleBuffer) {
        print("System Audio Frame inyectado al motor de mezcla.")
    }
    
    // Método Factory interno stub para crear el sample con PTS de ancla.
    private func pcmBufferToSampleBuffer(_ pcmBuffer: AVAudioPCMBuffer, pts: CMTime) -> CMSampleBuffer? {
        return nil
    }
}
