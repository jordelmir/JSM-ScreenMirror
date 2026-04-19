import Foundation
import CoreGraphics
import CoreVideo

/// Orquestador matemático que interviene las matrices del MetalCompositor 
/// cuando el DataChannel notifica que el usuario abrió su Honor Magic V2.
class LayoutMorphEngine {
    
    enum DeviceState {
        case foldedPortrait
        case unfoldedTablet
        case landscapeGaming
    }
    
    private var currentLayout: CGRect = .zero
    private var targetLayout: CGRect = .zero
    private var isMorphing = false
    
    // CVDisplayLink — la API nativa real de macOS para V-Sync
    private var displayLink: CVDisplayLink?
    private var morphProgress: CGFloat = 0.0
    
    init() {
        self.currentLayout = CGRect(x: 0.75, y: 0.1, width: 0.20, height: 0.8)
    }

    /// Llamado desde el Protobuf/WebRTC Receiver al detectar el `DevicePostureChanged`
    func transition(to newState: DeviceState) {
        switch newState {
        case .foldedPortrait:
            targetLayout = CGRect(x: 0.75, y: 0.1, width: 0.20, height: 0.8)
        case .unfoldedTablet:
            targetLayout = CGRect(x: 0.60, y: 0.2, width: 0.35, height: 0.6)
        case .landscapeGaming:
            targetLayout = CGRect(x: 0.2, y: 0.7, width: 0.6, height: 0.25)
        }
        
        startMorphingAnimation()
    }
    
    private func startMorphingAnimation() {
        guard !isMorphing else { return }
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
        morphProgress += 0.08
        
        if morphProgress >= 1.0 {
            currentLayout = targetLayout
            isMorphing = false
            if let link = displayLink {
                CVDisplayLinkStop(link)
            }
            displayLink = nil
        } else {
            let eased = cubicEaseInOut(morphProgress)
            currentLayout = CGRect(
                x: lerp(currentLayout.minX, targetLayout.minX, t: eased),
                y: lerp(currentLayout.minY, targetLayout.minY, t: eased),
                width: lerp(currentLayout.width, targetLayout.width, t: eased),
                height: lerp(currentLayout.height, targetLayout.height, t: eased)
            )
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
