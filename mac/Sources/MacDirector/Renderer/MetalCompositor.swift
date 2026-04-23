import MetalKit
import CoreVideo
import CoreImage
import CoreMedia

/// Orquestador Headless de rendering en GPU.
/// Fusiona el frame de Mac y el de Android off-screen (invisblemente) para enrutarlos al MP4.
class MetalCompositor: NSObject {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext
    
    private var macScreenPixelBuffer: CVPixelBuffer?
    private var androidOverlayPixelBuffer: CVPixelBuffer?
    private var pixelBufferPool: CVPixelBufferPool?
    var onFrameComposited: ((CVPixelBuffer, CMTime) -> Void)?
    
    /// Define si el PIP de Android se fusiona en el video o no.
    var isAndroidOverlayEnabled: Bool = true
    
    override init() {
        guard let dev = MTLCreateSystemDefaultDevice() else { fatalError("Metal no soportado") }
        self.device = dev
        self.commandQueue = device.makeCommandQueue()!
        
        self.ciContext = CIContext(mtlDevice: dev, options: [
            .cacheIntermediates: false,
            .allowLowPower: false
        ])
        
        super.init()
    }

    private func setupPixelBufferPool(width: Int, height: Int) {
        if pixelBufferPool == nil {
            let poolAttributes: [String: Any] = [kCVPixelBufferPoolMinimumBufferCountKey as String: 3]
            let bufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes as CFDictionary, bufferAttributes as CFDictionary, &pixelBufferPool)
        }
    }

    func updateMacScreen(pixelBuffer: CVPixelBuffer, pts: CMTime) {
        autoreleasepool {
            self.macScreenPixelBuffer = pixelBuffer
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            setupPixelBufferPool(width: width, height: height)
            self.composeAndEmitFrame(targetSize: CGSize(width: width, height: height), pts: pts)
        }
    }

    func updateAndroidStream(pixelBuffer: CVPixelBuffer) {
        self.androidOverlayPixelBuffer = pixelBuffer
    }
    
    private func composeAndEmitFrame(targetSize: CGSize, pts: CMTime) {
        guard let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let pool = pixelBufferPool else { return }
        
        var outputPixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outputPixelBuffer)
        guard let destinationBuffer = outputPixelBuffer else { return }
        
        var blendedImage: CIImage? = nil
        
        if let macBuffer = macScreenPixelBuffer {
            // CIImage(cvPixelBuffer:) preserva el espacio de color (ej. Display P3) y maneja las coordenadas sin flips manuales
            blendedImage = CIImage(cvPixelBuffer: macBuffer)
        } else {
            blendedImage = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: targetSize))
        }
        
        if isAndroidOverlayEnabled, let androidBuffer = androidOverlayPixelBuffer {
            let img = CIImage(cvPixelBuffer: androidBuffer)
            let pipHeight = targetSize.height * 0.25
            let pipRatio = pipHeight / img.extent.height
            
            let transform = CGAffineTransform(scaleX: pipRatio, y: pipRatio)
                .translatedBy(
                    x: (targetSize.width - (img.extent.width * pipRatio) - 40) / pipRatio, 
                    y: 40 / pipRatio
                )
            
            let pipImage = img.transformed(by: transform)
            blendedImage = pipImage.composited(over: blendedImage!)
        }
        
        if let finalImage = blendedImage {
            let srgbSpace = CGColorSpace(name: CGColorSpace.sRGB)!
            ciContext.render(finalImage, to: destinationBuffer, bounds: finalImage.extent, colorSpace: srgbSpace)
            
            // Inyectar etiquetas estrictas Rec.709 para coincidir con el AVAssetWriterInput (Evita drop de frames a 0 bytes)
            CVBufferSetAttachment(destinationBuffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
            CVBufferSetAttachment(destinationBuffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
            CVBufferSetAttachment(destinationBuffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
            CVBufferSetAttachment(destinationBuffer, "CVImageBufferGammaLevel" as CFString, 2.2 as NSNumber, .shouldPropagate)
            
            onFrameComposited?(destinationBuffer, pts)
        }
        
        commandBuffer.commit()
    }
}
