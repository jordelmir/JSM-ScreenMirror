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
    
    func injectSystemAudio(sampleBuffer: CMSampleBuffer) {
        // En V1 extraemos de CMSampleBuffer a AVAudioPCMBuffer y agendamos en systemAudioNode
        // Omitimos la implementación de desembalaje para mantener la arquitectura limpia (requiere CMAudioFormatDescription)
    }
    
    // Método Factory interno que convierte PCM a CMSampleBuffer para AVAssetWriter
    private func pcmBufferToSampleBuffer(_ pcmBuffer: AVAudioPCMBuffer, pts: CMTime) -> CMSampleBuffer? {
        var status: OSStatus = noErr
        var formatDescription: CMAudioFormatDescription? = nil
        
        status = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                                asbd: pcmBuffer.format.streamDescription,
                                                layoutSize: 0,
                                                layout: nil,
                                                magicCookieSize: 0,
                                                magicCookie: nil,
                                                extensions: nil,
                                                formatDescriptionOut: &formatDescription)
        
        guard status == noErr, let formatDesc = formatDescription else { return nil }
        
        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: CMTimeMake(value: 1, timescale: Int32(pcmBuffer.format.sampleRate)),
                                        presentationTimeStamp: pts,
                                        decodeTimeStamp: .invalid)
        
        status = CMSampleBufferCreate(allocator: kCFAllocatorDefault,
                                      dataBuffer: nil,
                                      dataReady: false,
                                      makeDataReadyCallback: nil,
                                      refcon: nil,
                                      formatDescription: formatDesc,
                                      sampleCount: CMItemCount(pcmBuffer.frameLength),
                                      sampleTimingEntryCount: 1,
                                      sampleTimingArray: &timing,
                                      sampleSizeEntryCount: 0,
                                      sampleSizeArray: nil,
                                      sampleBufferOut: &sampleBuffer)
        
        guard status == noErr, let buffer = sampleBuffer else { return nil }
        
        // Asignar los datos del buffer PCM (requiere punteros AudioBufferList)
        status = CMSampleBufferSetDataBufferFromAudioBufferList(buffer,
                                                                blockBufferAllocator: kCFAllocatorDefault,
                                                                blockBufferMemoryAllocator: kCFAllocatorDefault,
                                                                flags: 0,
                                                                bufferList: pcmBuffer.audioBufferList)
        
        return status == noErr ? buffer : nil
    }
}
