import Foundation
import WebRTC
import CoreVideo

/// Receptor de frames de video provenientes de WebRTC (Android).
/// Convierte I420 (3 planes YUV) a NV12 (BiPlanar) para compatibilidad con AVSampleBufferDisplayLayer.
class RTCVideoSink: NSObject, RTCVideoRenderer {
    
    var onFrameReceived: ((CVPixelBuffer) -> Void)?
    private var frameCount = 0
    
    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame = frame else { return }
        
        if let buffer = frame.buffer as? RTCCVPixelBuffer {
            // Hardware decode path (H264/VideoToolbox) — ya es CVPixelBuffer nativo
            onFrameReceived?(buffer.pixelBuffer)
        } else if let i420 = frame.buffer as? RTCI420Buffer {
            // Software decode path (VP8/I420) — convertir a NV12 BiPlanar
            if let nv12 = convertI420ToNV12(i420) {
                onFrameReceived?(nv12)
            } else {
                frameCount += 1
                if frameCount % 300 == 1 {
                    print("⚠️ RTCVideoSink: I420→NV12 conversion failed (frame #\(frameCount))")
                }
            }
        } else {
            frameCount += 1
            if frameCount % 300 == 1 {
                print("⚠️ RTCVideoSink: Unknown buffer type: \(type(of: frame.buffer))")
            }
        }
    }
    
    /// Convierte RTCI420Buffer (3 planes: Y, U, V) a CVPixelBuffer NV12 (2 planes: Y, UV interleaved).
    /// AVSampleBufferDisplayLayer soporta NV12 nativamente con aceleración GPU.
    private func convertI420ToNV12(_ i420: RTCI420Buffer) -> CVPixelBuffer? {
        let width = Int(i420.width)
        let height = Int(i420.height)
        
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
            kCVPixelBufferMetalCompatibilityKey: true
        ]
        
        // NV12 = BiPlanar YCbCr 4:2:0 (lo que Apple GPU ama)
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            attrs as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let pb = pixelBuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        
        // ── Plane 0: Y (luma) ──
        guard let yDest = CVPixelBufferGetBaseAddressOfPlane(pb, 0) else { return nil }
        let yDestStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        let ySrcStride = Int(i420.strideY)
        let ySource = i420.dataY
        
        for row in 0..<height {
            memcpy(
                yDest.advanced(by: row * yDestStride),
                ySource.advanced(by: row * ySrcStride),
                min(width, min(yDestStride, ySrcStride))
            )
        }
        
        // ── Plane 1: UV interleaved (chroma) ──
        // I420 tiene U y V en planos separados. NV12 los quiere entrelazados: UVUVUVUV...
        guard let uvDest = CVPixelBufferGetBaseAddressOfPlane(pb, 1) else { return nil }
        let uvDestStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)
        let uSrcStride = Int(i420.strideU)
        let vSrcStride = Int(i420.strideV)
        let uSource = i420.dataU
        let vSource = i420.dataV
        
        let halfWidth = (width + 1) / 2
        let halfHeight = (height + 1) / 2
        
        for row in 0..<halfHeight {
            let uvRow = uvDest.advanced(by: row * uvDestStride).assumingMemoryBound(to: UInt8.self)
            let uRow = uSource.advanced(by: row * uSrcStride)
            let vRow = vSource.advanced(by: row * vSrcStride)
            
            for col in 0..<halfWidth {
                uvRow[col * 2]     = uRow[col]  // U
                uvRow[col * 2 + 1] = vRow[col]  // V
            }
        }
        
        return pb
    }
    
    func setSize(_ size: CGSize) {
        print("WebRTC Stream Size: \(Int(size.width))x\(Int(size.height))")
    }
}
