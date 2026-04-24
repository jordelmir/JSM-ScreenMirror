import SwiftUI
import WebRTC
import AVFoundation

/// Vista que usa AVSampleBufferDisplayLayer para renderizar video acelerado por hardware en macOS
struct AndroidPreviewView: NSViewRepresentable {
    var pixelBuffer: CVPixelBuffer?
    
    class Coordinator {
        let displayLayer = AVSampleBufferDisplayLayer()
        
        init() {
            displayLayer.videoGravity = .resizeAspect
            displayLayer.backgroundColor = NSColor.black.cgColor
        }
        
        func enqueue(_ pixelBuffer: CVPixelBuffer) {
            var formatDesc: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDesc)
            
            guard let fd = formatDesc else { return }
            
            var sampleTiming = CMSampleTimingInfo(
                duration: .invalid,
                presentationTimeStamp: CMTime(value: Int64(mach_absolute_time()), timescale: 1000000000), // Approximate
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
            
            if let sb = sampleBuffer {
                if displayLayer.status == .failed {
                    displayLayer.flush()
                }
                displayLayer.enqueue(sb)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }
    
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

/// Ventana flotante que muestra el streaming del Android
struct AndroidPreviewWindow: View {
    @EnvironmentObject var engine: RuntimeOrchestrator
    @State private var currentFrame: CVPixelBuffer?
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if engine.rtcController.isP2PConnected {
                AndroidPreviewView(pixelBuffer: currentFrame)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.cyan)
                    Text("ESPERANDO SEÑAL DE VIDEO...")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.cyan)
                }
            }
        }
        .frame(minWidth: 300, minHeight: 600)
        .background(Color.black.opacity(0.9))
        .onReceive(engine.rtcController.$latestPixelBuffer) { pb in
            self.currentFrame = pb
        }
    }
}

