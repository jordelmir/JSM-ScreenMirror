import Foundation
import ScreenCaptureKit
import CoreMedia

/// Gestor moderno y definitivo de captura de pantalla en macOS usando ScreenCaptureKit.
/// Evita la sobrecarga de CGDisplayStream, y otorga aceleración de GPU automática en SoCs Apple Silicon.
@available(macOS 12.3, *)
class ScreenCaptureManager: NSObject, ObservableObject {
    private var stream: SCStream?
    
    // Aquí inyectaremos el buffer directamente al Metal Compositor
    var videoSampleBufferHandler: ((CMSampleBuffer) -> Void)?
    var audioSampleBufferHandler: ((CMSampleBuffer) -> Void)?

    func startCapture() async throws {
        // En v1, pedimos los displays disponibles y agarramos la main screen
        let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        guard let display = availableContent.displays.first else {
            print("No main display found.")
            return
        }

        // SCStreamConfiguration de alto nivel: 1440p @ 60fps
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = 2560
        configuration.height = 1440
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 5 // Buffer corto para descartar frames si hay retraso en GPU
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        
        // Incluir audio del host nativamente
        configuration.capturesAudio = true
        
        stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        
        // Agregamos la salida de SampleBuffers a esta clase
        try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.jsm.videocapture"))
        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.jsm.audiocapture"))

        try await stream?.startCapture()
        print("SCStream iniciado: 2560x1440 @ 60fps con System Audio.")
    }

    func stopCapture() async throws {
        try await stream?.stopCapture()
    }
}

@available(macOS 12.3, *)
extension ScreenCaptureManager: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Chequeos drásticos de status (Frame Dropped / Error)
        guard sampleBuffer.isValid else { return }
        
        switch type {
        case .screen:
            videoSampleBufferHandler?(sampleBuffer)
        case .audio:
            audioSampleBufferHandler?(sampleBuffer)
        @unknown default:
            break
        }
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("SCStream fatal error: \(error.localizedDescription)")
    }
}
