import MetalKit
import CoreVideo
import CoreImage
import CoreMedia
import CoreGraphics

/// Dato ligero de un trazo para renderizado en el compositor.
/// Coordenadas normalizadas (0.0-1.0). El compositor escala a la resolución de salida.
struct CompositorStroke {
    let points: [CGPoint]
    let color: CGColor
    let opacity: Double
    let lineWidth: CGFloat
}

/// Compositor Headless GPU de 3 pasadas.
///
/// - Pass 1: Mac Screen (fondo completo)
/// - Pass 2: Android PIP (posición/tamaño dinámico vía LayoutMorphEngine)
/// - Pass 3: Anotaciones efímeras (neon glow, coordenadas normalizadas desde EphemeralEngine)
///
/// Thread Model:
/// - `updateMacScreen` se llama desde el callback de SCStream (capture thread)
/// - `updateAndroidStream` se llama desde el callback de WebRTC (decoder thread)
/// - `pipLayoutRect` se escribe desde capture thread (lectura atómica de LayoutMorphEngine)
/// - `activeAnnotations` se escribe desde capture thread (lectura atómica de EphemeralEngine)
/// - La composición ocurre inline en `updateMacScreen`, todo en el capture thread
class MetalCompositor: NSObject {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext
    
    private var macScreenPixelBuffer: CVPixelBuffer?
    private var androidOverlayPixelBuffer: CVPixelBuffer?
    private var pixelBufferPool: CVPixelBufferPool?
    private var poolWidth: Int = 0
    private var poolHeight: Int = 0
    var onFrameComposited: ((CVPixelBuffer, CMTime) -> Void)?
    
    /// Define si el PIP de Android se fusiona en el video.
    var isAndroidOverlayEnabled: Bool = true
    
    /// Rect normalizado (0.0–1.0) del PIP Android.
    /// Alimentado por LayoutMorphEngine cada frame.
    var pipLayoutRect: CGRect = CGRect(x: 0.73, y: 0.02, width: 0.25, height: 0.35)
    
    /// Strokes de anotación activos (coords normalizadas 0-1).
    /// Inyectados desde EphemeralEngine.cachedCompositorStrokes.
    var activeAnnotations: [CompositorStroke] = []
    
    // ─── Annotation render cache ───
    // Evita re-renderizar CGContext cuando los strokes no han cambiado.
    private var lastAnnotationFingerprint: Double = -1
    private var cachedAnnotationImage: CIImage?
    private var cachedAnnotationTargetSize: CGSize = .zero
    
    // Color space de salida (Rec.709 estricto para AVAssetWriter)
    private let outputColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    
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
        guard poolWidth != width || poolHeight != height else { return }
        
        poolWidth = width
        poolHeight = height
        pixelBufferPool = nil // Liberar el pool anterior
        
        let poolAttributes: [String: Any] = [kCVPixelBufferPoolMinimumBufferCountKey as String: 3]
        let bufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
        CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            bufferAttributes as CFDictionary,
            &pixelBufferPool
        )
    }

    func updateMacScreen(pixelBuffer: CVPixelBuffer, pts: CMTime) {
        autoreleasepool {
            self.macScreenPixelBuffer = pixelBuffer
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            setupPixelBufferPool(width: width, height: height)
            composeAndEmitFrame(targetSize: CGSize(width: width, height: height), pts: pts)
        }
    }

    func updateAndroidStream(pixelBuffer: CVPixelBuffer) {
        self.androidOverlayPixelBuffer = pixelBuffer
    }
    
    // ═══════════════════════════════════════════════════════════
    //  COMPOSICIÓN PRINCIPAL — 3 PASADAS
    // ═══════════════════════════════════════════════════════════
    
    private func composeAndEmitFrame(targetSize: CGSize, pts: CMTime) {
        guard let pool = pixelBufferPool else { return }
        
        var outputPixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outputPixelBuffer)
        guard status == kCVReturnSuccess, let destinationBuffer = outputPixelBuffer else { return }
        
        // ═══════════════════════════════════════════
        //  PASS 1: Mac Screen (Background)
        // ═══════════════════════════════════════════
        var composited: CIImage
        
        if let macBuffer = macScreenPixelBuffer {
            composited = CIImage(cvPixelBuffer: macBuffer)
        } else {
            composited = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: targetSize))
        }
        
        // ═══════════════════════════════════════════
        //  PASS 2: Android PIP (Dynamic Rect)
        // ═══════════════════════════════════════════
        if isAndroidOverlayEnabled, let androidBuffer = androidOverlayPixelBuffer {
            composited = compositeAndroidPIP(
                androidImage: CIImage(cvPixelBuffer: androidBuffer),
                over: composited,
                targetSize: targetSize
            )
        }
        
        // ═══════════════════════════════════════════
        //  PASS 3: Ephemeral Annotations
        // ═══════════════════════════════════════════
        let strokes = activeAnnotations
        if !strokes.isEmpty {
            if let annotationLayer = getAnnotationImage(strokes: strokes, targetSize: targetSize) {
                composited = annotationLayer.composited(over: composited)
            }
        } else {
            // Invalidar cache cuando no hay strokes
            cachedAnnotationImage = nil
            lastAnnotationFingerprint = -1
        }
        
        // ═══════════════════════════════════════════
        //  OUTPUT: Render + Color Tags
        // ═══════════════════════════════════════════
        ciContext.render(composited, to: destinationBuffer, bounds: composited.extent, colorSpace: outputColorSpace)
        
        // Tags Rec.709 estrictos — sin esto AVAssetWriter produce 0 bytes
        CVBufferSetAttachment(destinationBuffer, kCVImageBufferColorPrimariesKey,
                              kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(destinationBuffer, kCVImageBufferTransferFunctionKey,
                              kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(destinationBuffer, kCVImageBufferYCbCrMatrixKey,
                              kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        
        onFrameComposited?(destinationBuffer, pts)
    }
    
    // ═══════════════════════════════════════════════════════════
    //  PASS 2: Android PIP Compositing
    // ═══════════════════════════════════════════════════════════
    
    private func compositeAndroidPIP(androidImage: CIImage, over base: CIImage, targetSize: CGSize) -> CIImage {
        let layout = pipLayoutRect
        
        // Normalizado → Píxeles absolutos
        let pipX = layout.minX * targetSize.width
        let pipY = layout.minY * targetSize.height
        let pipW = layout.width * targetSize.width
        let pipH = layout.height * targetSize.height
        
        guard pipW > 1 && pipH > 1 else { return base }
        
        // Escalar preservando aspect ratio
        let srcW = androidImage.extent.width
        let srcH = androidImage.extent.height
        guard srcW > 0 && srcH > 0 else { return base }
        
        let scale = min(pipW / srcW, pipH / srcH)
        let scaledW = srcW * scale
        let scaledH = srcH * scale
        
        // Centrar dentro del rect PIP
        let offsetX = pipX + (pipW - scaledW) / 2.0
        let offsetY = pipY + (pipH - scaledH) / 2.0
        
        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))
        
        let pip = androidImage.transformed(by: transform)
        
        // Bezel sutil (borde 2px oscuro alrededor del PIP)
        let bezelInset: CGFloat = 2.0
        let bezelRect = CGRect(
            x: offsetX - bezelInset,
            y: offsetY - bezelInset,
            width: scaledW + bezelInset * 2,
            height: scaledH + bezelInset * 2
        )
        let bezel = CIImage(color: CIColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 0.85))
            .cropped(to: bezelRect)
        
        return pip.composited(over: bezel.composited(over: base))
    }
    
    // ═══════════════════════════════════════════════════════════
    //  PASS 3: Annotation Rendering (Cached)
    // ═══════════════════════════════════════════════════════════
    
    /// Devuelve la CIImage de anotaciones, usando cache solo cuando los strokes no han cambiado visualmente.
    /// El fingerprint incluye count + opacities para detectar fade-out.
    private func getAnnotationImage(strokes: [CompositorStroke], targetSize: CGSize) -> CIImage? {
        // Fingerprint: count + quantized opacity sum (detecta fade-out sin ser excesivamente caro)
        let opacitySum = strokes.reduce(0.0) { $0 + $1.opacity }
        let fingerprint = Double(strokes.count) * 1000.0 + (opacitySum * 100.0).rounded()
        
        let needsRebuild = fingerprint != lastAnnotationFingerprint
                        || cachedAnnotationTargetSize != targetSize
                        || cachedAnnotationImage == nil
        
        if needsRebuild {
            cachedAnnotationImage = renderAnnotationLayer(strokes: strokes, size: targetSize)
            lastAnnotationFingerprint = fingerprint
            cachedAnnotationTargetSize = targetSize
        }
        
        return cachedAnnotationImage
    }
    
    /// Renderiza strokes a CIImage transparente usando CoreGraphics.
    /// Dual-pass: halo exterior difuso + núcleo brillante = efecto neón.
    /// Coordenadas de entrada normalizadas (0-1), escaladas a `size`.
    private func renderAnnotationLayer(strokes: [CompositorStroke], size: CGSize) -> CIImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0 && height > 0 else { return nil }
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: outputColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        // Flip vertical: CG origin = bottom-left, SwiftUI/screen coords = top-left
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        
        let w = CGFloat(width)
        let h = CGFloat(height)
        
        for stroke in strokes {
            guard stroke.points.count >= 2 else { continue }
            let alpha = CGFloat(stroke.opacity)
            guard alpha > 0.01 else { continue }
            
            // Desnormalizar puntos al tamaño de salida
            let absPoints = stroke.points.map { p in
                CGPoint(x: p.x * w, y: p.y * h)
            }
            let absLineWidth = stroke.lineWidth * min(w, h)
            
            // Pass 1: Halo exterior (simula blur con línea gruesa + baja opacidad)
            if let glowColor = stroke.color.copy(alpha: alpha * 0.30) {
                context.setStrokeColor(glowColor)
                context.setLineWidth(absLineWidth * 3.5)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.beginPath()
                context.move(to: absPoints[0])
                for i in 1..<absPoints.count { context.addLine(to: absPoints[i]) }
                context.strokePath()
            }
            
            // Pass 2: Núcleo brillante
            if let coreColor = stroke.color.copy(alpha: alpha) {
                context.setStrokeColor(coreColor)
                context.setLineWidth(absLineWidth)
                context.beginPath()
                context.move(to: absPoints[0])
                for i in 1..<absPoints.count { context.addLine(to: absPoints[i]) }
                context.strokePath()
            }
        }
        
        guard let cgImage = context.makeImage() else { return nil }
        return CIImage(cgImage: cgImage)
    }
}
