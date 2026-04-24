import SwiftUI

struct DashboardView: View {
    @Environment(\.openWindow) var openWindow
    @EnvironmentObject var engine: RuntimeOrchestrator
    @State private var isAnimatingRadar = false
    @State private var isAnimatingRec = false
    @State private var hoverRecord = false
    @State private var hoverDual = false
    @State private var hoverFolder = false
    @State private var hoverHud = false
    
    var body: some View {
        ZStack {
            // Fondo Base Deep Space con gradiente sutil
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.02, blue: 0.06),
                    Color(red: 0.04, green: 0.03, blue: 0.10),
                    Color(red: 0.02, green: 0.02, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()
            
            // Grid sutil decorativa (Industrial)
            Canvas { context, size in
                for x in stride(from: 0, to: size.width, by: 40) {
                    context.stroke(Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) }, with: .color(.white.opacity(0.02)), lineWidth: 0.5)
                }
                for y in stride(from: 0, to: size.height, by: 40) {
                    context.stroke(Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) }, with: .color(.white.opacity(0.02)), lineWidth: 0.5)
                }
            }
            .ignoresSafeArea()
            
            // Glow ambiental superior
            Circle()
                .fill(
                    RadialGradient(colors: [Color.cyan.opacity(0.08), .clear], center: .center, startRadius: 0, endRadius: 200)
                )
                .frame(width: 400, height: 400)
                .offset(y: -250)
                .blur(radius: 40)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 22) {
                    
                    // ─── Header con Logo ───
                    VStack(spacing: 4) {
                        Text("ELYSIUM VANGUARD")
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                            .foregroundStyle(
                                LinearGradient(colors: [.cyan, .blue, .purple], startPoint: .leading, endPoint: .trailing)
                            )
                        Text("SCREEN MIRROR STUDIO")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                            .tracking(4)
                    }
                    .padding(.top, 18)
                    
                    // ─── Barra de Status Superior ───
                    HStack(spacing: 8) {
                        StatusPill(label: "TCC", value: engine.screenCapture.isAuthorized ? "OK" : "⚠", color: engine.screenCapture.isAuthorized ? .green : .red)
                        StatusPill(label: "MOTOR", value: engine.isBooted ? "ON" : "OFF", color: engine.isBooted ? .green : .gray)
                        StatusPill(
                            label: "P2P",
                            value: engine.rtcController.isP2PConnected ? "LIVE" : (engine.bonjourBrowser.isSearching ? "SCAN" : "IDLE"),
                            color: engine.rtcController.isP2PConnected ? .green : (engine.bonjourBrowser.isSearching ? .cyan : .gray)
                        )
                        
                        Spacer()
                        
                        // FPS Badge (siempre visible)
                        HStack(spacing: 4) {
                            Circle()
                                .fill(engine.fps > 0 ? Color.green : Color.red.opacity(0.5))
                                .frame(width: 6, height: 6)
                            Text("\(engine.fps) FPS")
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundColor(engine.fps > 0 ? .green : .red.opacity(0.7))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.white.opacity(0.04))
                                .overlay(RoundedRectangle(cornerRadius: 20).stroke(engine.fps > 0 ? Color.green.opacity(0.3) : Color.red.opacity(0.2), lineWidth: 1))
                        )
                    }
                    .padding(.horizontal, 20)

                    // ─── Alerta de Error Técnico ───
                    if let error = engine.recordingError {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 16))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ERROR TÉCNICO")
                                    .font(.system(size: 9, weight: .black, design: .monospaced))
                                    .foregroundColor(.red)
                                Text(error)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.red.opacity(0.8))
                                    .lineLimit(3)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.25), lineWidth: 1))
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // ─── Indicador de Grabación en Curso ───
                    if engine.isRecording {
                        HStack(spacing: 14) {
                            // Punto rojo pulsante
                            ZStack {
                                Circle()
                                    .fill(Color.red.opacity(0.3))
                                    .frame(width: 28, height: 28)
                                    .scaleEffect(isAnimatingRec ? 1.3 : 0.9)
                                    .opacity(isAnimatingRec ? 0.2 : 0.6)
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 12, height: 12)
                            }
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimatingRec)
                            .onAppear { isAnimatingRec = true }
                            .onDisappear { isAnimatingRec = false }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("GRABANDO")
                                    .font(.system(size: 11, weight: .black, design: .monospaced))
                                    .foregroundColor(.red)
                                Text(formatTime(engine.recordingSeconds))
                                    .font(.system(size: 22, weight: .black, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(engine.selectedQuality.rawValue)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.cyan.opacity(0.6))
                                Text("HEVC")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.red.opacity(0.06))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.red.opacity(0.2), lineWidth: 1))
                        )
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // ─── Selección de Calidad ───
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CALIDAD DE GRABACIÓN MASTER")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan.opacity(0.5))
                        
                        HStack(spacing: 8) {
                            ForEach(VideoQuality.allCases) { quality in
                                QualityButton(
                                    label: quality.shortLabel,
                                    isSelected: engine.selectedQuality == quality,
                                    isDisabled: engine.isRecording
                                ) {
                                    withAnimation(.spring(response: 0.3)) {
                                        engine.selectedQuality = quality
                                    }
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.03))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.06), lineWidth: 1))
                    )
                    .padding(.horizontal, 20)
                    
                    // ─── Android Link Status ───
                    if engine.rtcController.isP2PConnected || engine.androidConnectionState != "IDLE" {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(engine.rtcController.isP2PConnected ? Color.green : Color.cyan.opacity(0.5))
                                    .frame(width: 6, height: 6)
                                Text("ANDROID LINK")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.cyan.opacity(0.5))
                                Spacer()
                                Text(engine.androidConnectionState)
                                    .font(.system(size: 8, weight: .black, design: .monospaced))
                                    .foregroundColor(engine.rtcController.isP2PConnected ? .green : .cyan.opacity(0.6))
                            }
                            
                            if engine.rtcController.isP2PConnected {
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("POSTURE")
                                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                                            .foregroundColor(.purple.opacity(0.5))
                                        Text(engine.androidPosture)
                                            .font(.system(size: 10, weight: .black, design: .monospaced))
                                            .foregroundColor(.purple)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("ORIENT")
                                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                                            .foregroundColor(.orange.opacity(0.5))
                                        Text(engine.androidOrientation)
                                            .font(.system(size: 10, weight: .black, design: .monospaced))
                                            .foregroundColor(.orange)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("SIZE")
                                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.3))
                                        Text(engine.androidDimensions)
                                            .font(.system(size: 10, weight: .black, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                    Spacer()
                                }
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.cyan.opacity(0.03))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cyan.opacity(0.1), lineWidth: 1))
                        )
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // ─── Acciones Principales ───
                    VStack(spacing: 12) {
                        
                        // Botón de Grabar / Detener
                        Button(action: {
                            withAnimation(.spring(response: 0.4)) {
                                if engine.isRecording {
                                    engine.stopRecording()
                                } else {
                                    if !engine.isBooted {
                                        engine.bootEngine()
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                        engine.startRecording()
                                    }
                                }
                            }
                        }) {
                            HStack(spacing: 16) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(engine.isRecording ? Color.orange.opacity(0.15) : Color.red.opacity(0.15))
                                        .frame(width: 48, height: 48)
                                    Image(systemName: engine.isRecording ? "stop.circle.fill" : "record.circle")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundColor(engine.isRecording ? .orange : .red)
                                }
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(engine.isRecording ? "DETENER GRABACIÓN" : "INICIAR GRABACIÓN")
                                        .font(.system(size: 13, weight: .black))
                                        .foregroundColor(.white)
                                    Text(engine.isRecording ? "Guardando en Descargas/screen recorder" : "Captura pantalla completa + audio del sistema")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.2))
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(hoverRecord ? 0.08 : 0.04))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(
                                                engine.isRecording
                                                    ? Color.orange.opacity(0.3)
                                                    : Color.white.opacity(hoverRecord ? 0.15 : 0.08),
                                                lineWidth: 1
                                            )
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .onHover { hoverRecord = $0 }
                        .animation(.easeOut(duration: 0.2), value: hoverRecord)
                        
                        // Botón Modo Dual
                        Button(action: {
                            engine.bootEngine()
                        }) {
                            HStack(spacing: 16) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.cyan.opacity(0.12))
                                        .frame(width: 48, height: 48)
                                    Image(systemName: "iphone.badge.plus")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(.cyan)
                                }
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("MODO DUAL ELYSIUM")
                                        .font(.system(size: 13, weight: .black))
                                        .foregroundColor(.white)
                                    Text("Enlazar dispositivo Android vía WebRTC")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.2))
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(hoverDual ? 0.08 : 0.04))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.white.opacity(hoverDual ? 0.15 : 0.08), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .onHover { hoverDual = $0 }
                        .animation(.easeOut(duration: 0.2), value: hoverDual)
                        
                        // Botones secundarios
                        HStack(spacing: 10) {
                            MiniButton(title: "VER GRABACIONES", icon: "folder.fill", hover: $hoverFolder) {
                                engine.openRecordingFolder()
                            }
                            MiniButton(title: "VER ANDROID", icon: "iphone", hover: $hoverHud) {
                                openWindow(id: "androidPreview")
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer(minLength: 10)

                    // ─── Footer de Escaneo ───
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .stroke(Color.cyan.opacity(0.2), lineWidth: 1)
                                .scaleEffect(isAnimatingRadar ? 1.3 : 0.8)
                                .opacity(isAnimatingRadar ? 0 : 0.5)
                                .animation(Animation.easeOut(duration: 2.5).repeatForever(autoreverses: false), value: isAnimatingRadar)
                                .frame(width: 24, height: 24)
                            Circle()
                                .fill(Color.cyan.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                        
                        Text(engine.bonjourBrowser.isSearching ? "ESCANEANDO RED LOCAL..." : "SISTEMA OPERATIVO")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan.opacity(0.4))
                        
                        Spacer()
                        
                        Text("v1.0.0")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.15))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    .onAppear { isAnimatingRadar = true }
                }
            }
        }
        .frame(width: 520, height: 640)
        .alert("PERMISOS REQUERIDOS", isPresented: $engine.showPermissionAlert) {
            Button("ABRIR AJUSTES") {
                engine.screenCapture.openPermissionSettings()
            }
            Button("CANCELAR", role: .cancel) {}
        } message: {
            Text("Elysium Vanguard necesita permisos de 'Grabación de Pantalla' para funcionar. Actívalos en Ajustes del Sistema → Privacidad → Grabación de Pantalla.")
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Componentes Reutilizables

struct QualityButton: View {
    let label: String
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .black : .bold, design: .monospaced))
                .foregroundColor(isSelected ? .white : .white.opacity(0.4))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.cyan.opacity(0.2) : Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSelected ? Color.cyan.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled && !isSelected ? 0.4 : 1)
    }
}

struct MiniButton: View {
    let title: String
    let icon: String
    @Binding var hover: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(hover ? 0.07 : 0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(hover ? 0.12 : 0.06), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.2), value: hover)
    }
}

struct StatusPill: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(color.opacity(0.6))
            Text(value)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(color.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.2), lineWidth: 0.5))
        )
    }
}
