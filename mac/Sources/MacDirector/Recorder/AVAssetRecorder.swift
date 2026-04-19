import Foundation
import AVFoundation
import VideoToolbox

/// Motor de persistencia del Stream. Inyecta frames del compositor Metal a un contenedor MP4.
class AVAssetRecorder {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    private var isRecording = false
    private var sessionStartTime: CMTime = .zero
    
    func startRecording(outputURL: URL) throws {
        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        
        // Settings de Video: 1440p (V1 Default) | HEVC H.265 para compresión premium
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: 2560,
            AVVideoHeightKey: 1440,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 18_000_000, // 18 Mbps
                AVVideoProfileLevelKey: "HEVC_Main_AutoLevel" as String,
                AVVideoExpectedSourceFrameRateKey: 60
            ]
        ]
        
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true // Crítico para grabar pantallas sin desincronización
        
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: 2560,
            kCVPixelBufferHeightKey as String: 1440,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput!,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )
        
        if let input = videoInput, assetWriter!.canAdd(input) {
            assetWriter!.add(input)
        }
        
        assetWriter?.startWriting()
        assetWriter?.startSession(atSourceTime: CMTime.zero)
        isRecording = true
    }
    
    /// Consume la textura resultante que sale del pipeline `MetalCompositor` y la empaqueta.
    func appendVideoFrame(pixelBuffer: CVPixelBuffer, at time: CMTime) {
        guard isRecording, videoInput?.isReadyForMoreMediaData == true else { return }
        
        if sessionStartTime == .zero {
            sessionStartTime = time
            assetWriter?.startSession(atSourceTime: time)
        }
        
        pixelBufferAdaptor?.append(pixelBuffer, withPresentationTime: time)
    }
    
    /// Consume Audio Mixto emparejado desde AudioMixer y encola si el sessionStart existe.
    func appendAudioFrame(sampleBuffer: CMSampleBuffer) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        guard isRecording, assetWriter?.status == .writing else { return }
        // Barrera crítica anti-desincronización (Crash shield):
        // No pasamos audio cuyo reloj físico ocurrió ANTES del arranque nominal del video de la sesión
        guard sessionStartTime != .zero, pts >= sessionStartTime else { return }
        
        // (Asumiendo que generas un AVAssetWriterInput para Audio previamente inicializado)
        // if audioInput?.isReadyForMoreMediaData == true {
        //    audioInput?.append(sampleBuffer)
        // }
    }
    
    func stopRecording(completion: @escaping (URL?) -> Void) {
        guard isRecording, let writer = assetWriter else { return }
        isRecording = false
        
        videoInput?.markAsFinished()
        writer.finishWriting {
            completion(writer.outputURL)
        }
    }
}
