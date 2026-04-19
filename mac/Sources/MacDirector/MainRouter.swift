import SwiftUI
import MetalKit
import CoreVideo
import CoreMedia

/// Orquestador Supremo de la App Mac.
/// Levanta e inyecta las tuberías aisladas: 
/// ScreenCapture -> Compositor -> AssetWriter
@MainActor
class RuntimeOrchestrator: ObservableObject {
    let screenCapture = ScreenCaptureManager()
    let audioMixer = AudioMixer()
    let assetRecorder = AVAssetRecorder()
    let rtcController = RTCController()
    let bonjourBrowser = BonjourBrowser()
    let sensory = SensoryFeedbackManager.shared
    
    let mtkView = MTKView()
    private var metalCompositor: MetalCompositor?

    init() {
        setupPipeline()
    }

    private func setupPipeline() {
        self.metalCompositor = MetalCompositor(mtkView: mtkView)
        
        // 1. Vincular el video capturado (Entra por el Background Thread de SCStream)
        screenCapture.videoSampleBufferHandler = { [weak self] sampleBuffer in
            guard let self = self else { return }
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                self.metalCompositor?.updateMacScreen(pixelBuffer: pixelBuffer)
                
                let cmtime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                self.assetRecorder.appendVideoFrame(pixelBuffer: pixelBuffer, at: cmtime)
            }
        }
        
        // 2. Vincular el audio del sistema capturado hacia el Mixer Master
        screenCapture.audioSampleBufferHandler = { [weak self] sampleBuffer in
            self?.audioMixer.injectSystemAudio(sampleBuffer: sampleBuffer)
        }
        
        // 3. Vincular WebRTC (Android Track) hacia Metal
        // -> RtcController delegará los buffers decodificados a: metalCompositor?.updateAndroidStream()
    }
    
    func bootEngine() {
        Task {
            do {
                try await screenCapture.startCapture()
                bonjourBrowser.startDiscovery()
                
                await MainActor.run {
                    self.sensory.playDigitalConfirmSound()
                }
            } catch {
                await MainActor.run {
                    print("FATAL ERROR al arrancar el motor de captura: \(error)")
                }
            }
        }
    }
}

// Representable para poder embutir la vista 100% Metal dentro de SwiftUI
struct CompositorCanvasView: NSViewRepresentable {
    let mtkView: MTKView

    func makeNSView(context: Context) -> MTKView {
        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {}
}
