import SwiftUI
import WebRTC
import AVFoundation

// ═══════════════════════════════════════════════════════════════
//  AndroidPreviewView — Raw NV12 GPU renderer
//  Fills 100% of assigned space. Zero letterboxing. Zero chrome.
// ═══════════════════════════════════════════════════════════════

struct AndroidPreviewView: NSViewRepresentable {
    var pixelBuffer: CVPixelBuffer?
    
    class Coordinator {
        let displayLayer = AVSampleBufferDisplayLayer()
        
        init() {
            // resizeAspectFill: llena 100% del espacio, recorta mínimamente si es necesario
            // Esto ELIMINA las barras negras por completo
            displayLayer.videoGravity = .resizeAspectFill
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
            
            var timing = CMSampleTimingInfo(
                duration: .invalid,
                presentationTimeStamp: .invalid,
                decodeTimeStamp: .invalid
            )
            var sb: CMSampleBuffer?
            CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescription: fd,
                sampleTiming: &timing,
                sampleBufferOut: &sb
            )
            guard let sampleBuffer = sb else { return }
            
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true)
            if let attachments = attachments {
                let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
                CFDictionarySetValue(
                    dict,
                    Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                    Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
                )
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
        // Retina: máxima nitidez en displays HiDPI
        if let screen = NSScreen.main {
            context.coordinator.displayLayer.contentsScale = screen.backingScaleFactor
        }
        // Filtros de interpolación de alta calidad
        context.coordinator.displayLayer.magnificationFilter = .trilinear
        context.coordinator.displayLayer.minificationFilter = .trilinear
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let pb = pixelBuffer {
            context.coordinator.enqueue(pb)
        }
        // Asegurar que el layer siempre ocupe todo el NSView
        if let layer = nsView.layer {
            layer.frame = nsView.bounds
        }
    }
}

// ═══════════════════════════════════════════════════════════════
//  AndroidPreviewWindow — Pro Screen Mirror
//  El video llena TODA la ventana. Sin barras negras. Sin chrome.
//  La ventana se ajusta al aspect ratio del stream automáticamente.
//  Completamente redimensionable — el video se estira con ella.
// ═══════════════════════════════════════════════════════════════

struct AndroidPreviewWindow: View {
    @EnvironmentObject var engine: RuntimeOrchestrator
    @State private var currentFrame: CVPixelBuffer?
    @State private var showOverlay = false
    @State private var overlayTimer: Timer?
    @State private var streamWidth: CGFloat = 1080
    @State private var streamHeight: CGFloat = 1920
    
    var body: some View {
        ZStack {
            // ── FONDO PURO ──
            Color.black.edgesIgnoringSafeArea(.all)
            
            if engine.rtcController.isP2PConnected {
                // ── VIDEO: Llena absolutamente todo ──
                if let frame = currentFrame {
                    GeometryReader { geo in
                        AndroidPreviewView(pixelBuffer: frame)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .edgesIgnoringSafeArea(.all)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onEnded { value in
                                        // Normalizar coordenadas a 0.0-1.0
                                        let normX = value.location.x / geo.size.width
                                        let normY = value.location.y / geo.size.height
                                        let clampedX = min(max(normX, 0), 1)
                                        let clampedY = min(max(normY, 0), 1)
                                        
                                        // Enviar tap al Android via DataChannel
                                        let msg = String(format: "TOUCH:%.4f:%.4f", clampedX, clampedY)
                                        engine.rtcController.sendDataChannelMessage(msg)
                                        print("👆 Touch sent: \(msg)")
                                    }
                            )
                            // Swipe/drag support
                            .gesture(
                                DragGesture(minimumDistance: 10)
                                    .onChanged { value in
                                        let normX = value.location.x / geo.size.width
                                        let normY = value.location.y / geo.size.height
                                        let msg = String(format: "TOUCH_MOVE:%.4f:%.4f", 
                                            min(max(normX, 0), 1), min(max(normY, 0), 1))
                                        engine.rtcController.sendDataChannelMessage(msg)
                                    }
                                    .onEnded { value in
                                        engine.rtcController.sendDataChannelMessage("TOUCH_UP")
                                    }
                            )
                    }
                } else {
                    connectingIndicator
                }
                
                // ── OVERLAY (solo al hover, ultra-minimal) ──
                if showOverlay {
                    overlayHUD
                        .transition(.opacity)
                }
            } else {
                waitingView
            }
        }
        // Ventana completamente libre — sin topes, crece hasta donde quieras
        .frame(minWidth: 300, maxWidth: .infinity,
               minHeight: 300, maxHeight: .infinity)
        .onReceive(engine.rtcController.$latestPixelBuffer) { pb in
            self.currentFrame = pb
            // Detectar dimensiones del stream para auto-ajuste
            if let pb = pb {
                let w = CGFloat(CVPixelBufferGetWidth(pb))
                let h = CGFloat(CVPixelBufferGetHeight(pb))
                if w > 0 && h > 0 && (abs(w - streamWidth) > 10 || abs(h - streamHeight) > 10) {
                    streamWidth = w
                    streamHeight = h
                    // Auto-ajustar la ventana al aspect ratio del stream
                    adjustWindowAspect(width: w, height: h)
                }
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.25)) {
                showOverlay = hovering
            }
            overlayTimer?.invalidate()
            if hovering {
                overlayTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { _ in
                    withAnimation(.easeOut(duration: 0.4)) {
                        showOverlay = false
                    }
                }
            }
        }
    }
    
    // MARK: - Auto-ajuste de ventana al aspect ratio del video
    
    private func adjustWindowAspect(width: CGFloat, height: CGFloat) {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.last else { return }
            let currentFrame = window.frame
            let aspect = width / height  // landscape > 1, portrait < 1
            
            // Mantener la altura actual, ajustar el ancho al aspect ratio
            let newWidth = currentFrame.height * aspect
            let newFrame = NSRect(
                x: currentFrame.origin.x,
                y: currentFrame.origin.y,
                width: max(newWidth, 300),
                height: currentFrame.height
            )
            
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(newFrame, display: true)
            }
            
            // Configurar aspect ratio de la ventana para que mantenga proporciones al redimensionar
            window.contentAspectRatio = NSSize(width: width, height: height)
        }
    }
    
    // MARK: - Overlay HUD (minimal, transparent)
    
    private var overlayHUD: some View {
        VStack {
            HStack {
                // LIVE badge
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                        .shadow(color: .red.opacity(0.8), radius: 3)
                    Text("LIVE")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.65))
                .clipShape(Capsule())
                
                Spacer()
                
                // Resolution badge
                Text("\(Int(streamWidth))×\(Int(streamHeight))")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            
            Spacer()
        }
    }
    
    // MARK: - Connecting indicator
    
    private var connectingIndicator: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.cyan)
            Text("Recibiendo stream...")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.cyan.opacity(0.6))
        }
    }
    
    // MARK: - Waiting View
    
    private var waitingView: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 32))
                .foregroundColor(.cyan.opacity(0.5))
            
            ProgressView()
                .tint(.cyan)
            
            Text("ESPERANDO DISPOSITIVO")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundColor(.cyan.opacity(0.6))
                .tracking(2)
            
            Text("Inicia streaming desde tu Honor Magic V2")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.25))
        }
    }
}
