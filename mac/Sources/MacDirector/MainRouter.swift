import SwiftUI
import MetalKit
import CoreVideo
import CoreMedia
import Combine

enum VideoQuality: String, CaseIterable, Identifiable {
    case hd_1080p = "1080p (FHD)"
    case qhd_2k = "2K (QHD)"
    case uhd_4k = "4K (UHD)"
    
    var id: String { self.rawValue }
    
    var shortLabel: String {
        switch self {
        case .hd_1080p: return "1080p"
        case .qhd_2k: return "2K"
        case .uhd_4k: return "4K"
        }
    }
    
    var size: CGSize {
        switch self {
        case .hd_1080p: return CGSize(width: 1920, height: 1080)
        case .qhd_2k: return CGSize(width: 2560, height: 1440)
        case .uhd_4k: return CGSize(width: 3840, height: 2160)
        }
    }
    
    /// Bitrate óptimo por resolución (bps)
    var targetBitrate: Int {
        switch self {
        case .hd_1080p: return 8_000_000   // 8 Mbps
        case .qhd_2k:   return 16_000_000  // 16 Mbps
        case .uhd_4k:   return 30_000_000  // 30 Mbps
        }
    }
}

/// Orquestador Supremo de la App Mac.
/// Levanta e inyecta las tuberías aisladas: 
/// ScreenCapture -> Compositor -> AssetWriter
/// Bonjour -> Signaling -> WebRTC (ICE + SDP) -> Metal PIP
@MainActor
class RuntimeOrchestrator: ObservableObject {
    @Published var isRecording = false
    @Published var recordingSeconds = 0
    @Published var isBooted = false
    @Published var selectedQuality: VideoQuality = .qhd_2k
    @Published var fps: Int = 0
    @Published var showPermissionAlert = false
    @Published var recordingError: String? = nil
    
    // ─── Estado de conexión Android ───
    @Published var androidConnectionState: String = "IDLE"
    @Published var androidPosture: String = "—"
    @Published var androidOrientation: String = "—"
    @Published var androidDimensions: String = "—"
    
    private var recordingTimer: Timer?
    private var telemetryTimer: Timer?
    private var lastFrameCount = 0
    
    let screenCapture = ScreenCaptureManager()
    let audioMixer = AudioMixer()
    let assetRecorder = AVAssetRecorder()
    let rtcController = RTCController()
    let bonjourBrowser = BonjourBrowser()
    let signalingClient = SignalingClient()
    let sensory = SensoryFeedbackManager.shared
    let layoutEngine = LayoutMorphEngine()
    let hotKeyObserver = HotKeyObserver()
    
    public var metalCompositor: MetalCompositor?
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupPipeline()
        setupHotKeys()
    }

    private func setupPipeline() {
        self.metalCompositor = MetalCompositor()
        
        // ── PATH COMPOSITOR UNIFICADO (FIX 0-BYTES + PIP ANDROID) ──
        metalCompositor?.onFrameComposited = { [weak self] finalPixelBuffer, pts in
            guard let self = self else { return }
            self.assetRecorder.appendVideoFrame(pixelBuffer: finalPixelBuffer, at: pts)
        }
        
        // ScreenCapture envía el frame crudo + el PTS nativo (evita desincronización de audio/video)
        screenCapture.directPixelBufferHandler = { [weak self] pixelBuffer, pts in
            guard let self = self else { return }
            
            // Inyectar posición PIP dinámica desde el LayoutMorphEngine (thread-safe via os_unfair_lock)
            self.metalCompositor?.pipLayoutRect = self.layoutEngine.currentLayout
            
            // Inyectar anotaciones pre-cacheadas (snapshot síncrono, sin async Task)
            self.metalCompositor?.activeAnnotations = EphemeralEngine.cachedCompositorStrokes
            
            self.metalCompositor?.updateMacScreen(pixelBuffer: pixelBuffer, pts: pts)
        }
        
        // 2. Vincular el audio del sistema capturado hacia el Mixer Master
        screenCapture.audioSampleBufferHandler = { [weak self] sampleBuffer in
            self?.audioMixer.injectSystemAudio(sampleBuffer: sampleBuffer)
        }
        
        // 2.1 RECIBIR el audio mezclado (Mixer -> Recorder)
        audioMixer.mixedAudioBufferHandler = { [weak self] mixedBuffer in
            self?.assetRecorder.appendAudioFrame(sampleBuffer: mixedBuffer)
        }
        
        // 3. Vincular WebRTC (Android Track) hacia Metal
        rtcController.videoSink.onFrameReceived = { [weak self] pixelBuffer in
            self?.metalCompositor?.updateAndroidStream(pixelBuffer: pixelBuffer)
            DispatchQueue.main.async {
                self?.rtcController.latestPixelBuffer = pixelBuffer
            }
        }
        
        // 4. ── ICE candidates: RTC ↔ Signaling bridge ──
        rtcController.onLocalIceCandidate = { [weak self] candidate in
            self?.signalingClient.sendIceCandidate(
                candidate: candidate.sdp,
                sdpMid: candidate.sdpMid,
                sdpMLineIndex: candidate.sdpMLineIndex
            )
        }
        
        signalingClient.onRemoteIceCandidateReceived = { [weak self] candidate, sdpMid, sdpMLineIndex in
            self?.rtcController.addRemoteIceCandidate(
                candidate: candidate,
                sdpMid: sdpMid,
                sdpMLineIndex: sdpMLineIndex
            )
        }
        
        // 5. ── DataChannel: metadatos del Android (fold, orientación) ──
        rtcController.onDataChannelMessage = { [weak self] message in
            self?.handleAndroidDataChannelMessage(message)
        }
        
        // 6. ── Observar estado de conexión P2P ──
        rtcController.$isP2PConnected.sink { [weak self] connected in
            Task { @MainActor in
                self?.androidConnectionState = connected ? "CONNECTED" : "WAITING"
                if connected {
                    self?.sensory.triggerHapticAlignment()
                }
            }
        }.store(in: &cancellables)
        
        // 7. ── AUTO-RECONNECT: cuando ICE muere, reconectar automáticamente ──
        rtcController.onConnectionLost = { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                self.androidConnectionState = "RECONNECTING"
                print("🔄 ICE connection lost — auto-reconnecting in 3s...")
                
                // Esperar 3 segundos antes de reconectar
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                
                // Recrear PeerConnection para nueva negociación
                self.rtcController.reconnectP2P()
                
                // Re-vincular video sink
                self.rtcController.videoSink.onFrameReceived = { [weak self] pixelBuffer in
                    self?.metalCompositor?.updateAndroidStream(pixelBuffer: pixelBuffer)
                    DispatchQueue.main.async {
                        self?.rtcController.latestPixelBuffer = pixelBuffer
                    }
                }
                
                // Reconectar signaling (que dispara nueva Offer del Android)
                if let host = self.bonjourBrowser.discoveredHost,
                   let port = self.bonjourBrowser.discoveredPort {
                    self.signalingClient.connect(to: host, port: port)
                    print("🔄 Signaling reconnected — waiting for new Offer...")
                }
            }
        }
    }
    
    /// Procesa mensajes del DataChannel del Android
    private func handleAndroidDataChannelMessage(_ message: String) {
        let parts = message.components(separatedBy: ":")
        guard let command = parts.first else { return }
        
        switch command {
        case "POSTURE":
            if parts.count >= 2 {
                let posture = parts[1]
                androidPosture = posture
                
                switch posture {
                case "FOLDED":
                    layoutEngine.transition(to: .foldedPortrait)
                    sensory.triggerHapticLevelChange()
                case "UNFOLDED":
                    layoutEngine.transition(to: .unfoldedTablet)
                    sensory.triggerHapticLevelChange()
                case "HALF_OPENED":
                    layoutEngine.transition(to: .unfoldedTablet)
                    sensory.triggerHapticLevelChange()
                default:
                    break
                }
            }
            
        case "ORIENTATION":
            if parts.count >= 4 {
                androidOrientation = parts[1] // PORTRAIT or LANDSCAPE
                androidDimensions = "\(parts[2])×\(parts[3])"
                
                if parts[1] == "LANDSCAPE" {
                    layoutEngine.transition(to: .landscapeGaming)
                }
            }
            
        default:
            print("DataChannel: Comando no reconocido: \(command)")
        }
    }
    
    /// Conecta el HotKeyObserver al LayoutMorphEngine y MetalCompositor
    private func setupHotKeys() {
        hotKeyObserver.$currentLayout.sink { [weak self] layout in
            Task { @MainActor in
                guard let self = self else { return }
                switch layout {
                case .hidden:
                    self.metalCompositor?.isAndroidOverlayEnabled = false
                case .cornerPIP:
                    self.metalCompositor?.isAndroidOverlayEnabled = true
                    self.layoutEngine.transition(to: .foldedPortrait)
                case .splitScreen:
                    self.metalCompositor?.isAndroidOverlayEnabled = true
                    self.layoutEngine.transition(to: .unfoldedTablet)
                }
            }
        }.store(in: &cancellables)
    }
    
    func bootEngine() {
        if !screenCapture.hasFullRecordingPermission() {
            self.showPermissionAlert = true
            screenCapture.openPermissionSettings()
            return
        }

        Task {
            do {
                try await screenCapture.startCapture(quality: selectedQuality.size)
                bonjourBrowser.startDiscovery()
                androidConnectionState = "SCANNING"
                
                // Telemetría de FPS Master (basada en frames REALES de SCKit)
                telemetryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self = self else { return }
                        let currentFrames = self.screenCapture.receivedFrameCount
                        self.fps = currentFrames - self.lastFrameCount
                        self.lastFrameCount = currentFrames
                        
                        // Watchdog: si llevamos 3+ segundos sin frames, alertar
                        if self.isBooted && self.fps == 0 && self.recordingSeconds > 3 {
                            self.recordingError = "⚠ Sin señal de video. Verifica permisos de Grabación de Pantalla y reinicia la app."
                        }
                    }
                }
                
                // Inicializamos WebRTC antes del Handshake
                self.rtcController.createPeerConnection()
                
                // [Handshake Automático]: Bonjour descubre Android → conecta signaling
                bonjourBrowser.$discoveredHost.sink { [weak self] host in
                    guard let self = self, let host = host, let port = self.bonjourBrowser.discoveredPort else { return }
                    self.androidConnectionState = "DISCOVERED"
                    self.signalingClient.connect(to: host, port: port)
                }.store(in: &cancellables)
                
                // [SDP Swap]: Android envía Offer → Mac responde con Answer
                signalingClient.onSDPOfferReceived = { [weak self] offerSdp in
                    Task { @MainActor in
                        self?.androidConnectionState = "NEGOTIATING"
                    }
                    self?.rtcController.handleRemoteOffer(sdp: offerSdp) { answerSdp in
                        self?.signalingClient.sendAnswer(sdp: answerSdp)
                    }
                }
                
                await MainActor.run {
                    self.isBooted = true
                    self.sensory.playDigitalConfirmSound()
                }
            } catch {
                await MainActor.run {
                    print("FATAL ERROR al arrancar el motor de captura: \(error)")
                }
            }
        }
    }
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    func startRecording() {
        if !screenCapture.hasFullRecordingPermission() {
            self.showPermissionAlert = true
            return
        }

        let fileManager = FileManager.default
        let downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let targetDirectory = downloadsURL.appendingPathComponent("screen recorder")
        
        if !fileManager.fileExists(atPath: targetDirectory.path) {
            try? fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        
        // Nombre legible: Elysium_2026-04-20_14-30-00_2K.mp4
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let fileName = "Elysium_\(timestamp)_\(selectedQuality.shortLabel).mp4"
        let outputURL = targetDirectory.appendingPathComponent(fileName)
        
        do {
            try assetRecorder.startRecording(outputURL: outputURL, size: selectedQuality.size, bitrate: selectedQuality.targetBitrate)
            isRecording = true
            recordingSeconds = 0
            recordingError = nil
            
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.recordingSeconds += 1
                }
            }
            sensory.playDigitalConfirmSound()
            print("Recording started: \(outputURL.lastPathComponent) at \(selectedQuality.shortLabel)")
        } catch {
            let techError = assetRecorder.lastErrorCode ?? "UNKNOWN"
            recordingError = "\(error.localizedDescription) (Código: \(techError))"
            print("Recording failed: \(error)")
        }
    }
    
    func stopRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        assetRecorder.stopRecording { [weak self] url in
            Task { @MainActor in
                self?.isRecording = false
                if let url = url {
                    let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                    let sizeMB = Double(fileSize) / 1_048_576.0
                    print("✅ Grabación guardada: \(url.lastPathComponent) (\(String(format: "%.1f", sizeMB)) MB)")
                }
            }
        }
        sensory.playMechanicalClick()
    }
    
    func openRecordingFolder() {
        let fileManager = FileManager.default
        let downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let targetDirectory = downloadsURL.appendingPathComponent("screen recorder")
        
        if fileManager.fileExists(atPath: targetDirectory.path) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: targetDirectory.path)
        } else {
            NSWorkspace.shared.open(downloadsURL)
        }
    }
    
    /// Apagado completo de todos los subsistemas.
    /// Llamado al cerrar la app o resetear el motor.
    func shutdownEngine() {
        if isRecording { stopRecording() }
        
        telemetryTimer?.invalidate()
        telemetryTimer = nil
        
        // P2P teardown (orden: RTC → Signaling → Discovery)
        rtcController.dispose()
        signalingClient.disconnect()
        bonjourBrowser.stopDiscovery()
        
        // Capture teardown
        Task { try? await screenCapture.stopCapture() }
        
        cancellables.removeAll()
        
        isBooted = false
        androidConnectionState = "IDLE"
        print("Engine shutdown completo.")
    }
}

// Representable para poder embutir la vista 100% Metal dentro de SwiftUI
struct CompositorCanvasView: NSViewRepresentable {
    let mtkView: MTKView

    func makeNSView(context: Context) -> MTKView {
        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {}
}
