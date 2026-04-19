import MetalKit
import CoreVideo

/// Orquestador absoluto de rendering en la GPU para el proyecto JSM.
/// Recibe la captura del Mac y la captura del Android, y compila la escena final 4K60.
class MetalCompositor: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    
    // Texturas volátiles
    private var macScreenTexture: CVMetalTexture?
    private var androidOverlayTexture: CVMetalTexture?
    
    // Pipeline (Asume que cargaremos Shaders para el Neon Glow en Fase 4)
    private var pipelineState: MTLRenderPipelineState!

    private var textureCache: CVMetalTextureCache!

    init?(mtkView: MTKView) {
        // Asegurar Metal en el runtime
        guard let dev = MTLCreateSystemDefaultDevice() else { return nil }
        self.device = dev
        self.commandQueue = device.makeCommandQueue()!
        
        super.init()
        
        mtkView.device = device
        mtkView.delegate = self
        mtkView.framebufferOnly = false // Permitir lectura de frames para exportarlos a MP4
        mtkView.colorPixelFormat = .bgra8Unorm
        
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        
        setupPipeline()
    }
    
    private func setupPipeline() {
        // En este paso se construye el descriptor que apuntará a nuestros Vertex y Fragment shaders (.metal)
        // Por ahora, se mantendrá en un stub limpio para habilitar el build del marco teórico.
        let defaultLibrary = device.makeDefaultLibrary()
        // fragmentFunction = defaultLibrary?.makeFunction(name: "compositorFragmentShader")
    }

    /// Llamado desde SCStream (ScreenCaptureManager) a ~60 Hz
    func updateMacScreen(pixelBuffer: CVPixelBuffer) {
        // Encerramos la manipulación en un autoreleasepool aislado para forzar 
        // a que el ARC de Swift suelte el retained CoreVideo object en este mismo nanosegundo.
        autoreleasepool {
            var cvTextureOut: CVMetalTexture?
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            
            // Zero-copy: Mapeamos la memoria unificada directo al Cache del GPU
            let status = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault,
                textureCache,
                pixelBuffer,
                nil,
                .bgra8Unorm,
                width,
                height,
                0,
                &cvTextureOut
            )
            
            if status == kCVReturnSuccess, let cvTexture = cvTextureOut {
                self.macScreenTexture = cvTexture
            }
        }
    }

    /// Llamado desde el Receiver WebRTC
    func updateAndroidStream(pixelBuffer: CVPixelBuffer) {
        // Conversión del buffer Android a textura separada
    }
    
    // MARK: - MTKViewDelegate
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        
        // Pass 1: Renderizar MacScreen.
        // Pass 2: Renderizar AndroidStream sobrepuesto aplicando TransformMatrix (Morphing).
        // Pass 3: Post Processing (Bloom, Neón) dictado por el Roadmap.
        
        // Finalizamos el frame
        commandBuffer.present(drawable)
        commandBuffer.commit()
        
        // ¡Alerta Táctica!: Una vez finalizado el render en el 'drawable.texture', 
        // pasamos esta textura final hacia AVAssetRecorder para el MP4 local.
        
        // Drenaje estricto del pool de texturas in-activas alojadas en la memoria unificada.
        CVMetalTextureCacheFlush(textureCache, 0)
    }
}
