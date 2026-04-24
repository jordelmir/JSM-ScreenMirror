import SwiftUI
import WebRTC
import AVFoundation

// MARK: - Core Video Renderer (AVSampleBufferDisplayLayer — NV12 native)

struct AndroidPreviewView: NSViewRepresentable {
    var pixelBuffer: CVPixelBuffer?
    
    class Coordinator {
        let displayLayer = AVSampleBufferDisplayLayer()
        
        init() {
            displayLayer.videoGravity = .resizeAspectFill
            displayLayer.backgroundColor = NSColor.black.cgColor
            displayLayer.preventsDisplaySleepDuringVideoPlayback = false
        }
        
        func enqueue(_ pixelBuffer: CVPixelBuffer) {
            var formatDesc: CMVideoFormatDescription?
            let fmtStatus = CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &formatDesc
            )
            guard fmtStatus == noErr, let fd = formatDesc else { return }
            
            var sampleTiming = CMSampleTimingInfo(
                duration: .invalid,
                presentationTimeStamp: .invalid,
                decodeTimeStamp: .invalid
            )
            
            var sampleBuffer: CMSampleBuffer?
            CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescription: fd,
                sampleTiming: &sampleTiming,
                sampleBufferOut: &sampleBuffer
            )
            
            guard let sb = sampleBuffer else { return }
            
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true)
            if let attachments = attachments {
                let dict = unsafeBitCast(
                    CFArrayGetValueAtIndex(attachments, 0),
                    to: CFMutableDictionary.self
                )
                CFDictionarySetValue(
                    dict,
                    Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                    Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
                )
            }
            
            if displayLayer.status == .failed {
                displayLayer.flush()
            }
            displayLayer.enqueue(sb)
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer = context.coordinator.displayLayer
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let pb = pixelBuffer {
            context.coordinator.enqueue(pb)
        }
    }
}

// MARK: - Premium Phone Frame Constants

/// Aspect ratios for Honor Magic V2 real device dimensions
private enum PhoneDimensions {
    // Honor Magic V2 folded: 6.43" → 2376x1060 → ~2.24:1
    static let foldedAspect: CGFloat = 2376.0 / 1060.0  // ≈ 2.24
    // Honor Magic V2 unfolded: 7.92" → 2156x2344 → ~0.92:1 (almost square)
    static let unfoldedAspect: CGFloat = 2156.0 / 2344.0  // ≈ 0.92
    // Corner radius scaled to match real device (as fraction of width)
    static let cornerRadiusFraction: CGFloat = 0.06
    // Bezel thickness (fraction of width)
    static let bezelFraction: CGFloat = 0.025
}

// MARK: - Device Posture Enum for Preview

enum PreviewPosture: Equatable {
    case folded
    case unfolded
    case halfOpened
    
    var aspectRatio: CGFloat {
        switch self {
        case .folded: return PhoneDimensions.foldedAspect
        case .unfolded, .halfOpened: return PhoneDimensions.unfoldedAspect
        }
    }
    
    var label: String {
        switch self {
        case .folded: return "FOLDED"
        case .unfolded: return "TABLET"
        case .halfOpened: return "FLEX"
        }
    }
    
    var icon: String {
        switch self {
        case .folded: return "iphone"
        case .unfolded: return "ipad"
        case .halfOpened: return "rectangle.split.2x1"
        }
    }
}

// MARK: - Premium Phone Bezel View

struct PhoneBezelView: View {
    let posture: PreviewPosture
    let cornerRadius: CGFloat
    
    var body: some View {
        ZStack {
            // Outer bezel — glossy titanium finish
            RoundedRectangle(cornerRadius: cornerRadius + 4)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.15, green: 0.15, blue: 0.18),
                            Color(red: 0.08, green: 0.08, blue: 0.10),
                            Color(red: 0.12, green: 0.12, blue: 0.15),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.8), radius: 20, x: 0, y: 10)
                .shadow(color: Color.cyan.opacity(0.08), radius: 30, x: 0, y: 0)
            
            // Inner bezel highlight — subtle edge light
            RoundedRectangle(cornerRadius: cornerRadius + 3)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.03),
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.05),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.0
                )
            
            // Side button indicators (power + volume)
            if posture == .folded {
                // Power button — right side
                HStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(red: 0.2, green: 0.2, blue: 0.23))
                        .frame(width: 2, height: 30)
                        .offset(x: 1, y: -20)
                }
                
                // Volume buttons — right side
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color(red: 0.2, green: 0.2, blue: 0.23))
                            .frame(width: 2, height: 22)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color(red: 0.2, green: 0.2, blue: 0.23))
                            .frame(width: 2, height: 22)
                    }
                    .offset(x: 1, y: 30)
                }
            }
        }
    }
}

// MARK: - Status Bar Overlay

struct PhoneStatusBar: View {
    let posture: PreviewPosture
    let isStreaming: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // Posture indicator
            HStack(spacing: 4) {
                Image(systemName: posture.icon)
                    .font(.system(size: 9, weight: .bold))
                Text(posture.label)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
            }
            .foregroundColor(.cyan)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.cyan.opacity(0.15))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.cyan.opacity(0.3), lineWidth: 0.5)
                    )
            )
            
            Spacer()
            
            // Streaming indicator
            if isStreaming {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                        .shadow(color: .green, radius: 3)
                    Text("LIVE")
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.green.opacity(0.12))
                )
            }
            
            // Resolution badge
            Text("1080p")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }
}

// MARK: - Fold Hinge Indicator (for unfolded/half-opened)

struct FoldHingeView: View {
    let isHalfOpened: Bool
    
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.white.opacity(isHalfOpened ? 0.08 : 0.03),
                        Color.black.opacity(isHalfOpened ? 0.3 : 0.1),
                        Color.white.opacity(isHalfOpened ? 0.08 : 0.03),
                        Color.clear,
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 3)
    }
}

// MARK: - Premium Android Preview Window

struct AndroidPreviewWindow: View {
    @EnvironmentObject var engine: RuntimeOrchestrator
    @State private var currentFrame: CVPixelBuffer?
    @State private var posture: PreviewPosture = .folded
    @State private var showGlow = false
    @State private var breathePhase: CGFloat = 0
    
    // Adaptive sizing
    private let maxPhoneHeight: CGFloat = 680
    private let maxPhoneWidth: CGFloat = 500
    private let bezelPadding: CGFloat = 8
    
    var body: some View {
        ZStack {
            // Background — deep space with subtle radial gradient
            RadialGradient(
                colors: [
                    Color(red: 0.04, green: 0.04, blue: 0.08),
                    Color(red: 0.02, green: 0.02, blue: 0.04),
                    Color.black
                ],
                center: .center,
                startRadius: 50,
                endRadius: 400
            )
            .edgesIgnoringSafeArea(.all)
            
            if engine.rtcController.isP2PConnected {
                // Connected — show phone with live feed
                phoneDeviceView
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                // Waiting for connection
                waitingView
            }
        }
        .frame(minWidth: 350, idealWidth: 420, maxWidth: 600,
               minHeight: 500, idealHeight: 750, maxHeight: 900)
        .onReceive(engine.rtcController.$latestPixelBuffer) { pb in
            self.currentFrame = pb
        }
        .onReceive(engine.$androidPosture) { postureString in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                switch postureString {
                case "FOLDED": posture = .folded
                case "UNFOLDED": posture = .unfolded
                case "HALF_OPENED": posture = .halfOpened
                default: break
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                breathePhase = 1.0
            }
        }
    }
    
    // MARK: - Phone Device Composite View
    
    private var phoneDeviceView: some View {
        GeometryReader { geo in
            let availW = geo.size.width - 40  // margin
            let availH = geo.size.height - 80 // margin + status bar
            let aspect = posture.aspectRatio
            
            // Calculate phone size to fit within available space
            let phoneW: CGFloat = {
                let wFromH = availH / aspect
                return min(wFromH, availW)
            }()
            let phoneH = phoneW * aspect
            let cornerRadius = phoneW * PhoneDimensions.cornerRadiusFraction
            
            VStack(spacing: 0) {
                // Phone status bar (outside bezel)
                PhoneStatusBar(posture: posture, isStreaming: currentFrame != nil)
                    .frame(width: phoneW + bezelPadding * 2)
                    .padding(.bottom, 8)
                
                // Phone body
                ZStack {
                    // Ambient glow behind phone
                    RoundedRectangle(cornerRadius: cornerRadius + 8)
                        .fill(Color.cyan.opacity(0.04 + breathePhase * 0.03))
                        .blur(radius: 25)
                        .scaleEffect(1.05)
                    
                    // Phone bezel (outer shell)
                    PhoneBezelView(posture: posture, cornerRadius: cornerRadius)
                    
                    // Screen area (inset from bezel)
                    ZStack {
                        // Screen background
                        Color.black
                        
                        // Live video feed
                        if let frame = currentFrame {
                            AndroidPreviewView(pixelBuffer: frame)
                                .clipped()
                        }
                        
                        // Front camera punch-hole (subtle)
                        VStack {
                            HStack {
                                Spacer()
                                Circle()
                                    .fill(Color(red: 0.05, green: 0.05, blue: 0.07))
                                    .frame(width: 8, height: 8)
                                    .overlay(
                                        Circle()
                                            .fill(Color.white.opacity(0.05))
                                            .frame(width: 4, height: 4)
                                    )
                                    .padding(.trailing, 20)
                                    .padding(.top, 8)
                            }
                            Spacer()
                        }
                        
                        // Fold hinge line (for unfolded modes)
                        if posture == .unfolded || posture == .halfOpened {
                            FoldHingeView(isHalfOpened: posture == .halfOpened)
                        }
                        
                        // Screen edge reflection (premium glass effect)
                        RoundedRectangle(cornerRadius: cornerRadius - 2)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.08),
                                        Color.clear,
                                        Color.clear,
                                        Color.white.opacity(0.04),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius - 2))
                    .padding(bezelPadding)
                }
                .frame(width: phoneW + bezelPadding * 2, height: phoneH + bezelPadding * 2)
                .animation(.spring(response: 0.6, dampingFraction: 0.82), value: posture)
                
                // Bottom info bar
                bottomInfoBar
                    .frame(width: phoneW + bezelPadding * 2)
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // MARK: - Bottom Info Bar
    
    private var bottomInfoBar: some View {
        HStack(spacing: 16) {
            // Device name
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 10))
                    .foregroundColor(.cyan)
                Text("Honor Magic V2")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            // Connection quality
            HStack(spacing: 3) {
                ForEach(0..<4) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i < 3 ? Color.green : Color.white.opacity(0.2))
                        .frame(width: 3, height: CGFloat(4 + i * 3))
                }
            }
            
            Text("P2P")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.green.opacity(0.7))
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Waiting View
    
    private var waitingView: some View {
        VStack(spacing: 24) {
            // Ghost phone outline
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.cyan.opacity(0.2 + breathePhase * 0.15),
                                Color.purple.opacity(0.1 + breathePhase * 0.1),
                                Color.cyan.opacity(0.15 + breathePhase * 0.1),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: 140, height: 280)
                    .shadow(color: .cyan.opacity(0.15), radius: 15)
                
                VStack(spacing: 16) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 28))
                        .foregroundColor(.cyan.opacity(0.5 + breathePhase * 0.3))
                    
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.cyan)
                }
            }
            
            VStack(spacing: 8) {
                Text("ESPERANDO DISPOSITIVO")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(.cyan.opacity(0.8))
                    .tracking(3)
                
                Text("Inicia streaming desde tu Honor Magic V2")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
    }
}
