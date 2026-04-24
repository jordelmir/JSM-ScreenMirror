import Foundation
import AVFoundation
import CoreMedia

/// Motor de mezcla de audio profesional para el pipeline de grabación.
///
/// Arquitectura:
/// - `systemAudioNode`: Recibe audio del sistema vía ScreenCaptureKit (CMSampleBuffer → AVAudioPCMBuffer)
/// - `inputNode`: Micrófono físico del Mac (automático vía AVAudioEngine)
/// - `mainMixerNode`: Fusiona ambas señales
/// - Tap en el mixer: Extrae el audio mezclado como CMSampleBuffer para AVAssetRecorder
///
/// Sincronización:
/// - Usa el Host Time Clock de Apple Silicon (mach_absolute_time) como referencia temporal
/// - CMTime se deriva del hostTime del AVAudioTime para anclar A/V sync con el compositor
class AudioMixer: ObservableObject {
    private let engine = AVAudioEngine()
    private let systemAudioNode = AVAudioPlayerNode()
    
    /// Callback que entrega audio mezclado al AVAssetRecorder
    var mixedAudioBufferHandler: ((CMSampleBuffer) -> Void)?
    
    // Formato actual del audio de sistema (puede cambiar si la config de SCStream muta)
    private var systemAudioFormat: AVAudioFormat?
    private var isEngineRunning = false
    
    // Protección contra scheduling en nodo detenido
    private let scheduleLock = NSLock()

    init() {
        setupMixer()
    }
    
    private func setupMixer() {
        engine.attach(systemAudioNode)
        
        let mainMixer = engine.mainMixerNode
        let outputFormat = mainMixer.outputFormat(forBus: 0)
        
        // MUTE the physical output to prevent infinite feedback loops.
        // The tap is installed on the bus, so it will still receive the audio before output.
        mainMixer.outputVolume = 0.0
        
        // Conexión inicial del nodo de sistema al mixer (se reconecta si el formato cambia)
        engine.connect(systemAudioNode, to: mainMixer, format: outputFormat)
        
        // Tap asíncrono sobre el mixer para extraer audio mezclado
        mainMixer.installTap(onBus: 0, bufferSize: 1024, format: outputFormat) { [weak self] pcmBuffer, time in
            guard let self = self else { return }
            
            // Derivar CMTime del Host Clock nativo para sync A/V preciso
            var pts = CMTime.invalid
            if time.isHostTimeValid {
                let hostTimeNanos = time.hostTime
                pts = CMTime(value: Int64(hostTimeNanos), timescale: Int32(NSEC_PER_SEC))
            }
            
            if let sampleBuffer = self.convertPCMToSampleBuffer(pcmBuffer, pts: pts) {
                self.mixedAudioBufferHandler?(sampleBuffer)
            }
        }
        
        do {
            try engine.start()
            isEngineRunning = true
            systemAudioNode.play()
        } catch {
            print("AudioMixer: AVAudioEngine falló al arrancar: \(error.localizedDescription)")
        }
    }
    
    // ═══════════════════════════════════════════════════════════
    //  INYECCIÓN DE AUDIO DEL SISTEMA (ScreenCaptureKit)
    // ═══════════════════════════════════════════════════════════
    
    /// Convierte CMSampleBuffer de ScreenCaptureKit a AVAudioPCMBuffer y lo agenda en el mixer.
    func injectSystemAudio(sampleBuffer: CMSampleBuffer) {
        guard isEngineRunning else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        
        // 1. Extraer formato de audio del buffer
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }
        
        // 2. Crear AVAudioFormat — acceso directo sin puntero mutable
        guard let audioFormat = AVAudioFormat(streamDescription: asbd) else { return }
        
        // 3. Si el formato cambió, reconectar el nodo
        if let currentFormat = systemAudioFormat {
            if currentFormat.sampleRate != audioFormat.sampleRate ||
               currentFormat.channelCount != audioFormat.channelCount {
                reconnectSystemNode(with: audioFormat)
            }
        } else {
            reconnectSystemNode(with: audioFormat)
        }
        
        // 4. Cantidad de frames
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return }
        
        // 5. Crear AVAudioPCMBuffer destino
        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: audioFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else { return }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)
        
        // 6. Extraer datos crudos del CMBlockBuffer
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let blockStatus = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        guard blockStatus == kCMBlockBufferNoErr, let srcPointer = dataPointer, totalLength > 0 else { return }
        
        // 7. Copiar datos al PCM buffer según el formato
        let streamDesc = asbd.pointee
        let channelCount = Int(streamDesc.mChannelsPerFrame)
        let isFloat = (streamDesc.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isNonInterleaved = (streamDesc.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        
        if isFloat, let channelData = pcmBuffer.floatChannelData {
            let bytesPerSample = MemoryLayout<Float>.size
            
            if isNonInterleaved {
                // Non-interleaved: cada canal es un bloque contiguo separado
                let framesPerChannel = totalLength / (channelCount * bytesPerSample)
                let actualFrames = min(framesPerChannel, frameCount)
                for ch in 0..<min(channelCount, Int(audioFormat.channelCount)) {
                    let channelOffset = ch * actualFrames * bytesPerSample
                    let copyBytes = actualFrames * bytesPerSample
                    guard channelOffset + copyBytes <= totalLength else { continue }
                    memcpy(channelData[ch], srcPointer.advanced(by: channelOffset), copyBytes)
                }
            } else if channelCount == 1 {
                // Mono interleaved: copia directa
                let copyBytes = min(totalLength, frameCount * bytesPerSample)
                memcpy(channelData[0], srcPointer, copyBytes)
            } else {
                // Multi-canal interleaved: deinterleave manualmente
                let srcFloat = UnsafeRawPointer(srcPointer)
                    .bindMemory(to: Float.self, capacity: frameCount * channelCount)
                let chCount = min(channelCount, Int(audioFormat.channelCount))
                for frame in 0..<frameCount {
                    let srcIdx = frame * channelCount
                    guard srcIdx + chCount <= totalLength / bytesPerSample else { break }
                    for ch in 0..<chCount {
                        channelData[ch][frame] = srcFloat[srcIdx + ch]
                    }
                }
            }
        } else if let channelData = pcmBuffer.int16ChannelData {
            // PCM Int16 (menos común desde SCStream, pero por robustez)
            let copyBytes = min(totalLength, frameCount * Int(streamDesc.mBytesPerFrame))
            memcpy(channelData[0], srcPointer, copyBytes)
        } else {
            return // Formato no soportado
        }
        
        // 8. Schedule en el player node (thread-safe)
        scheduleLock.lock()
        if isEngineRunning {
            systemAudioNode.scheduleBuffer(pcmBuffer, completionHandler: nil)
        }
        scheduleLock.unlock()
    }
    
    /// Reconecta el nodo de audio del sistema con un nuevo formato.
    private func reconnectSystemNode(with format: AVAudioFormat) {
        scheduleLock.lock()
        engine.disconnectNodeOutput(systemAudioNode)
        engine.connect(systemAudioNode, to: engine.mainMixerNode, format: format)
        systemAudioFormat = format
        if isEngineRunning {
            systemAudioNode.play()
        }
        scheduleLock.unlock()
    }
    
    // ═══════════════════════════════════════════════════════════
    //  CONVERSIÓN PCM → CMSampleBuffer (para AVAssetWriter)
    // ═══════════════════════════════════════════════════════════
    
    /// Convierte AVAudioPCMBuffer a CMSampleBuffer con PTS anclado al Host Clock.
    private func convertPCMToSampleBuffer(_ pcmBuffer: AVAudioPCMBuffer, pts: CMTime) -> CMSampleBuffer? {
        var formatDescription: CMAudioFormatDescription?
        var status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: pcmBuffer.format.streamDescription,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard status == noErr, let formatDesc = formatDescription else { return nil }
        
        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTimeMake(value: 1, timescale: Int32(pcmBuffer.format.sampleRate)),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        
        status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
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
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let buffer = sampleBuffer else { return nil }
        
        status = CMSampleBufferSetDataBufferFromAudioBufferList(
            buffer,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: pcmBuffer.audioBufferList
        )
        
        return status == noErr ? buffer : nil
    }
}
