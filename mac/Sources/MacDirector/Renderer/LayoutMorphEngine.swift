import Foundation
import CoreGraphics
import CoreVideo
import os

/// Orquestador matemático que interviene las matrices del MetalCompositor 
/// cuando el DataChannel notifica que el usuario abrió su Honor Magic V2.
///
/// `currentLayout` es un CGRect normalizado (0.0-1.0) que define la posición
/// y tamaño del PIP Android dentro de la escena de composición.
/// El MetalCompositor lo lee en cada frame para transformar el overlay.
class LayoutMorphEngine {
    
    enum DeviceState {
        case foldedPortrait
        case unfoldedTablet
        case landscapeGaming
    }
    
    /// Lock para acceso thread-safe a currentLayout.
    /// CVDisplayLink escribe desde su thread C; SCStream capture lee desde otro.
    private var layoutLock = os_unfair_lock()
    private var _currentLayout: CGRect
    
    /// Rect normalizado actual del PIP Android (0.0–1.0). Thread-safe.
    /// Leído por MetalCompositor en cada frame desde el capture thread.
    var currentLayout: CGRect {
        os_unfair_lock_lock(&layoutLock)
        let value = _currentLayout
        os_unfair_lock_unlock(&layoutLock)
        return value
    }
    
    private var startLayout: CGRect = .zero
    private var targetLayout: CGRect = .zero
    private var isMorphing = false
    
    // CVDisplayLink — la API nativa real de macOS para V-Sync
    private var displayLink: CVDisplayLink?
    private var morphProgress: CGFloat = 0.0
    
    init() {
        // Default: PIP compacto en esquina inferior-derecha
        self._currentLayout = CGRect(x: 0.73, y: 0.02, width: 0.25, height: 0.35)
    }

    /// Llamado desde el Protobuf/WebRTC Receiver al detectar el `DevicePostureChanged`
    func transition(to newState: DeviceState) {
        switch newState {
        case .foldedPortrait:
            // PIP compacto vertical, esquina inferior derecha
            targetLayout = CGRect(x: 0.73, y: 0.02, width: 0.25, height: 0.35)
        case .unfoldedTablet:
            // PIP grande tipo tablet, centrado-derecha
            targetLayout = CGRect(x: 0.58, y: 0.10, width: 0.40, height: 0.55)
        case .landscapeGaming:
            // PIP ancho en la parte inferior, centrado
            targetLayout = CGRect(x: 0.20, y: 0.02, width: 0.60, height: 0.28)
        }
        
        startMorphingAnimation()
    }
    
    private func startMorphingAnimation() {
        // Guardar posición de inicio para interpolación correcta
        startLayout = currentLayout
        
        guard !isMorphing else {
            // Si ya estamos morphing, simplemente actualizamos el target
            morphProgress = 0.0
            return
        }
        isMorphing = true
        morphProgress = 0.0
        
        // CVDisplayLink — vinculado exactamente al refresh rate físico del panel (60/120 ProMotion)
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        
        guard let link = displayLink else { return }
        
        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
            guard let engine = userInfo else { return kCVReturnError }
            let morphEngine = Unmanaged<LayoutMorphEngine>.fromOpaque(engine).takeUnretainedValue()
            morphEngine.renderTick()
            return kCVReturnSuccess
        }
        
        CVDisplayLinkSetOutputCallback(link, callback, Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(link)
    }
    
    private func renderTick() {
        morphProgress += 0.06 // ~16 frames para completar (~267ms a 60hz)
        
        if morphProgress >= 1.0 {
            morphProgress = 1.0
            os_unfair_lock_lock(&layoutLock)
            _currentLayout = targetLayout
            os_unfair_lock_unlock(&layoutLock)
            isMorphing = false
            if let link = displayLink {
                CVDisplayLinkStop(link)
            }
            displayLink = nil
        } else {
            let eased = cubicEaseInOut(morphProgress)
            let newRect = CGRect(
                x: lerp(startLayout.minX, targetLayout.minX, t: eased),
                y: lerp(startLayout.minY, targetLayout.minY, t: eased),
                width: lerp(startLayout.width, targetLayout.width, t: eased),
                height: lerp(startLayout.height, targetLayout.height, t: eased)
            )
            os_unfair_lock_lock(&layoutLock)
            _currentLayout = newRect
            os_unfair_lock_unlock(&layoutLock)
        }
    }
    
    private func lerp(_ a: CGFloat, _ b: CGFloat, t: CGFloat) -> CGFloat {
        return a + (b - a) * t
    }
    
    private func cubicEaseInOut(_ p: CGFloat) -> CGFloat {
        if p < 0.5 {
            return 4.0 * p * p * p
        } else {
            let f = ((2.0 * p) - 2.0)
            return 0.5 * f * f * f + 1.0
        }
    }
}
