import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreGraphics

/// Gestor moderno y definitivo de captura de pantalla en macOS usando ScreenCaptureKit.
/// Evita la sobrecarga de CGDisplayStream, y otorga aceleración de GPU automática en SoCs Apple Silicon.
@available(macOS 12.3, *)
class ScreenCaptureManager: NSObject, ObservableObject {
    private var stream: SCStream?
    
    // Handlers para video y audio
    var videoSampleBufferHandler: ((CMSampleBuffer) -> Void)?
    var audioSampleBufferHandler: ((CMSampleBuffer) -> Void)?
    
    /// Handler DIRECTO para grabación: recibe el pixelBuffer crudo + timestamp del SCKit
    var directPixelBufferHandler: ((CVPixelBuffer, CMTime) -> Void)?
    
    @Published var isAuthorized: Bool = false
    @Published var isCapturing: Bool = false
    var receivedFrameCount: Int = 0
    
    override init() {
        super.init()
        isAuthorized = CGPreflightScreenCaptureAccess()
    }
    
    func checkPermissions() {
        isAuthorized = CGPreflightScreenCaptureAccess()
    }
    
    func hasFullRecordingPermission() -> Bool {
        return true
    }
    
    func openPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func requestPermissions() {
        CGRequestScreenCaptureAccess()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkPermissions()
        }
    }

    func startCapture(quality: CGSize) async throws {
        guard !isCapturing else { return }
        let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        guard let display = availableContent.displays.first else {
            print("⛔ No main display found.")
            return
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int(quality.width)
        configuration.height = Int(quality.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 8
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.capturesAudio = true
        configuration.showsCursor = true
        
        stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        
        try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.jsm.videocapture", qos: .userInteractive))
        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.jsm.audiocapture", qos: .userInteractive))

        try await stream?.startCapture()
        receivedFrameCount = 0
        isCapturing = true
        print("✅ SCStream iniciado: \(Int(quality.width))x\(Int(quality.height)) @ 60fps.")
    }

    func stopCapture() async throws {
        try await stream?.stopCapture()
        isCapturing = false
    }
}

@available(macOS 12.3, *)
extension ScreenCaptureManager: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        
        switch type {
        case .screen:
            // CRÍTICO: Verificar que el frame tiene contenido real (no idle/blank/dropped)
            guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let statusValue = attachmentsArray.first?[.status] as? Int,
                  statusValue == 0 /* SCFrameStatus.complete */
            else { return }
            
            // Extraer pixelBuffer DIRECTO de ScreenCaptureKit
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                receivedFrameCount += 1
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                
                // Path DIRECTO al grabador (bypass Metal)
                directPixelBufferHandler?(pixelBuffer, pts)
                
                // Path hacia Metal Compositor (para PIP y efectos)
                videoSampleBufferHandler?(sampleBuffer)
            }
            
        case .audio:
            audioSampleBufferHandler?(sampleBuffer)
        case .microphone:
            break
        @unknown default:
            break
        }
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("⛔ SCStream fatal error: \(error.localizedDescription)")
    }
}
