import Foundation
import AVFoundation
import VideoToolbox

/// Motor de persistencia del Stream. Inyecta frames del compositor Metal a un contenedor MP4.
class AVAssetRecorder {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var audioInput: AVAssetWriterInput?
    
    private var isRecording = false
    private var sessionStartTime: CMTime = .zero
    @Published var frameCount: Int = 0
    @Published var lastError: String? = nil
    @Published var lastErrorCode: String? = nil
    
    func startRecording(outputURL: URL, size: CGSize, bitrate: Int = 16_000_000) throws {
        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        
        // Settings de Video: HEVC (H.265) con bitrate adaptativo por resolución
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: 60,
                AVVideoMaxKeyFrameIntervalKey: 120,
                AVVideoMaxKeyFrameIntervalDurationKey: 2.0
            ]
        ]
        
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true
        
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput!,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )
        
        if assetWriter?.canAdd(videoInput!) == true {
            assetWriter?.add(videoInput!)
        }
        
        // Settings de Audio: AAC-LC 256kbps 48kHz Estéreo
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 256000
        ]
        
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput?.expectsMediaDataInRealTime = true
        
        if assetWriter?.canAdd(audioInput!) == true {
            assetWriter?.add(audioInput!)
        }
        
        assetWriter?.startWriting()
        
        if assetWriter?.status == .failed {
            let err = assetWriter?.error as NSError?
            lastErrorCode = "\(err?.code ?? -1)"
            throw assetWriter?.error ?? NSError(domain: "AVAssetRecorder", code: -1)
        }
        
        isRecording = true
        sessionStartTime = .zero
        frameCount = 0
        lastError = nil
        lastErrorCode = nil
        print("AVAssetRecorder: HEVC encoder ready at \(Int(size.width))x\(Int(size.height)) @ \(bitrate/1_000_000)Mbps")
    }
    
    /// Consume la textura resultante que sale del pipeline `MetalCompositor` y la empaqueta.
    func appendVideoFrame(pixelBuffer: CVPixelBuffer, at time: CMTime) {
        guard isRecording, videoInput?.isReadyForMoreMediaData == true else { return }
        
        if sessionStartTime == .zero {
            sessionStartTime = time
            assetWriter?.startSession(atSourceTime: time)
        }
        
        if pixelBufferAdaptor?.append(pixelBuffer, withPresentationTime: time) == true {
            frameCount += 1
        } else {
            let errorMsg = assetWriter?.error?.localizedDescription ?? "Status: \(assetWriter?.status.rawValue ?? -1)"
            let debugInfo = "Append Error: \(errorMsg)\n"
            try? debugInfo.write(to: URL(fileURLWithPath: "/tmp/ev_error.log"), atomically: true, encoding: .utf8)
            lastError = errorMsg
        }
    }
    
    /// Consume Audio Mixto emparejado desde AudioMixer y encola si el sessionStart existe.
    func appendAudioFrame(sampleBuffer: CMSampleBuffer) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        guard isRecording, assetWriter?.status == .writing else { return }
        // Barrera crítica anti-desincronización (Crash shield):
        // No pasamos audio cuyo reloj físico ocurrió ANTES del arranque nominal del video de la sesión
        guard sessionStartTime != .zero, pts >= sessionStartTime else { return }
        
        if audioInput?.isReadyForMoreMediaData == true {
           audioInput?.append(sampleBuffer)
        }
    }
    
    func stopRecording(completion: @escaping (URL?) -> Void) {
        guard isRecording, let writer = assetWriter else { return }
        isRecording = false
        
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        writer.finishWriting {
            completion(writer.outputURL)
        }
    }
}
