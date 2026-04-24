import SwiftUI
import WebRTC
import AVFoundation

/// Vista que usa AVSampleBufferDisplayLayer para renderizar video NV12 en macOS.
/// AVSampleBufferDisplayLayer soporta NV12 (BiPlanar) nativamente con aceleración GPU.
struct AndroidPreviewView: NSViewRepresentable {
    var pixelBuffer: CVPixelBuffer?
    
    class Coordinator {
        let displayLayer = AVSampleBufferDisplayLayer()
        
        init() {
            displayLayer.videoGravity = .resizeAspect
            displayLayer.backgroundColor = NSColor.black.cgColor
            // Desactivar el control de timing — queremos render inmediato
            displayLayer.preventsDisplaySleepDuringVideoPlayback = false
        }
        
        func enqueue(_ pixelBuffer: CVPixelBuffer) {
            var formatDesc: CMVideoFormatDescription?
            let fmtStatus = CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &formatDesc
            )
            
            guard fmtStatus == noErr, let fd = formatDesc else {
                print("❌ Preview: CMVideoFormatDescription failed: \(fmtStatus)")
                return
            }
            
            var sampleTiming = CMSampleTimingInfo(
                duration: .invalid,
                presentationTimeStamp: .invalid,
                decodeTimeStamp: .invalid
            )
            
            var sampleBuffer: CMSampleBuffer?
            let sbStatus = CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescription: fd,
                sampleTiming: &sampleTiming,
                sampleBufferOut: &sampleBuffer
            )
            
            guard sbStatus == noErr, let sb = sampleBuffer else {
                print("❌ Preview: CMSampleBuffer creation failed: \(sbStatus)")
                return
            }
            
            // Forzar display inmediato (sin esperar PTS)
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
                print("⚠️ Preview: DisplayLayer failed, flushing. Error: \(String(describing: displayLayer.error))")
                displayLayer.flush()
            }
            
            displayLayer.enqueue(sb)
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
