import SwiftUI
import WebRTC
import AVFoundation

// ═══════════════════════════════════════════════════════════════
//  AndroidPreviewView — Raw NV12 GPU renderer
//  El video llena 100% del espacio asignado. Sin chrome. Sin overhead.
// ═══════════════════════════════════════════════════════════════

struct AndroidPreviewView: NSViewRepresentable {
    var pixelBuffer: CVPixelBuffer?
    
    class Coordinator {
        let displayLayer = AVSampleBufferDisplayLayer()
        
        init() {
            displayLayer.videoGravity = .resizeAspect
            displayLayer.backgroundColor = NSColor.black.cgColor
            displayLayer.preventsDisplaySleepDuringVideoPlayback = false
        }
        
        func enqueue(_ pixelBuffer: CVPixelBuffer) {
            var formatDesc: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &formatDesc
            )
            guard let fd = formatDesc else { return }
            
            var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid)
            var sb: CMSampleBuffer?
            CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescription: fd, sampleTiming: &timing, sampleBufferOut: &sb)
            guard let sampleBuffer = sb else { return }
            
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true)
            if let attachments = attachments {
                let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
                CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
            }
            
            if displayLayer.status == .failed { displayLayer.flush() }
            displayLayer.enqueue(sampleBuffer)
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer = context.coordinator.displayLayer
        if let screen = NSScreen.main {
            context.coordinator.displayLayer.contentsScale = screen.backingScaleFactor
        }
        context.coordinator.displayLayer.magnificationFilter = .trilinear
        context.coordinator.displayLayer.minificationFilter = .trilinear
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let pb = pixelBuffer {
            context.coordinator.enqueue(pb)
        }
    }
}

// ═══════════════════════════════════════════════════════════════
//  AndroidPreviewWindow — Diseño Pro: VIDEO = VENTANA
//  El video llena toda la ventana. La UI es un overlay transparente.
//  Redimensionable libremente. Cero decoraciones que roben espacio.
// ═══════════════════════════════════════════════════════════════

struct AndroidPreviewWindow: View {
    @EnvironmentObject var engine: RuntimeOrchestrator
    @State private var currentFrame: CVPixelBuffer?
    @State private var showOverlay = true
    @State private var overlayTimer: Timer?
    
    var body: some View {
        ZStack {
            // ── FONDO ──
            Color.black.edgesIgnoringSafeArea(.all)
            
            if engine.rtcController.isP2PConnected {
                // ── VIDEO: Llena 100% de la ventana ──
                if let frame = currentFrame {
                    AndroidPreviewView(pixelBuffer: frame)
                        .edgesIgnoringSafeArea(.all)
                } else {
                    // Conectado pero aún sin frames
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.cyan)
                }
                
                // ── OVERLAY TRANSPARENTE (auto-hide) ──
                if showOverlay {
                    overlayHUD
                        .transition(.opacity)
                }
            } else {
                // ── ESPERANDO CONEXIÓN ──
                waitingView
            }
        }
        // Ventana grande y completamente redimensionable
        .frame(minWidth: 320, idealWidth: 480, maxWidth: .infinity,
               minHeight: 480, idealHeight: 800, maxHeight: .infinity)
        .onReceive(engine.rtcController.$latestPixelBuffer) { pb in
            self.currentFrame = pb
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.3)) {
                showOverlay = hovering
            }
            // Auto-hide after 3 seconds
            overlayTimer?.invalidate()
            if hovering {
                overlayTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                    withAnimation(.easeOut(duration: 0.5)) {
                        showOverlay = false
                    }
                }
            }
        }
    }
    
    // MARK: - Overlay HUD (transparente, sobre el video)
    
    private var overlayHUD: some View {
        VStack {
            // ── Top bar ──
            HStack {
                // Status badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                        .shadow(color: .green, radius: 4)
                    Text("LIVE")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.6))
                .clipShape(Capsule())
                
                Spacer()
                
                // Device info
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 9))
                    Text("Honor Magic V2")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.6))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            
            Spacer()
            
            // ── Bottom bar ──
            HStack {
                // Resolution
                Text("1080p")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Capsule())
                
                Spacer()
                
                // Connection quality
                HStack(spacing: 2) {
                    ForEach(0..<4) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(i < 3 ? Color.green : Color.white.opacity(0.3))
                            .frame(width: 3, height: CGFloat(4 + i * 2))
                    }
                    Text("P2P")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.green.opacity(0.8))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.5))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }
    
    // MARK: - Waiting View
    
    private var waitingView: some View {
        VStack(spacing: 20) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 36))
                .foregroundColor(.cyan.opacity(0.6))
            
            ProgressView()
                .scaleEffect(1.0)
                .tint(.cyan)
            
            Text("ESPERANDO DISPOSITIVO")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundColor(.cyan.opacity(0.7))
                .tracking(3)
            
            Text("Inicia streaming desde tu Honor Magic V2")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))
        }
    }
}
