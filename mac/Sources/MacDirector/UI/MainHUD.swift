import SwiftUI

/// Panel UI flotante para la Mac que rige el Drag Handle y el Glassmorphism oscuro.
struct HUDOverlayView: View {
    @EnvironmentObject var engine: RuntimeOrchestrator
    @State private var dragOffset = CGSize.zero
    @State private var isLaserActive = false
    @State private var isSpotlightActive = false
    
    var body: some View {
        HStack(spacing: 12) {
            
            // Requisito V1: Drag Handle industrial (3 Barras), sin menús de hamburguesa
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.gray.opacity(0.7))
                    .frame(width: 4, height: 18)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.gray.opacity(0.7))
                    .frame(width: 4, height: 18)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.gray.opacity(0.7))
                    .frame(width: 4, height: 18)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Lógica para interceptar NSWindow drag en AppKit irá aquí
                        self.dragOffset = value.translation
                    }
                    .onEnded { _ in self.dragOffset = .zero }
            )
            .padding(.leading, 8)
            
            Divider()
                .background(Color.white.opacity(0.2))
                .frame(height: 24)
            
            // Botones de herramientas premium tácticas
            HStack(spacing: 20) {
                
                if engine.isRecording {
                    Text(engine.recordingSeconds < 3600 ? String(format: "%02d:%02d", engine.recordingSeconds / 60, engine.recordingSeconds % 60) : "REC")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.red)
                        .padding(.horizontal, 4)
                        .transition(.opacity)
                }

                ToolButton(icon: engine.isRecording ? "stop.circle.fill" : "record.circle", color: .red) {
                    engine.toggleRecording()
                }
                
                ToolButton(icon: "pencil.and.outline", color: isLaserActive ? .cyan : .gray) {
                    isLaserActive.toggle()
                    if isLaserActive { isSpotlightActive = false }
                    SensoryFeedbackManager.shared.triggerHapticGeneric()
                    print("Lápiz Neón Toggled: \(isLaserActive)")
                }
                
                ToolButton(icon: "dot.radiowaves.up.forward", color: isSpotlightActive ? .green : .gray) {
                    isSpotlightActive.toggle()
                    if isSpotlightActive { isLaserActive = false }
                    SensoryFeedbackManager.shared.triggerHapticGeneric()
                    print("Spotlight Radar Toggled: \(isSpotlightActive)")
                }

                Divider()
                    .background(Color.white.opacity(0.1))
                    .frame(height: 18)

                // El Switch de "Capacidad": Solo Mac vs Mac + Android
                ToolButton(
                    icon: (engine.metalCompositor?.isAndroidOverlayEnabled ?? true) ? "iphone.badge.plus" : "desktopcomputer", 
                    color: (engine.metalCompositor?.isAndroidOverlayEnabled ?? true) ? .cyan : .gray
                ) {
                    let currentState = engine.metalCompositor?.isAndroidOverlayEnabled ?? true
                    engine.metalCompositor?.isAndroidOverlayEnabled = !currentState
                    SensoryFeedbackManager.shared.playMechanicalClick()
                    print("Capacidad Cambiada: Is Android PIP Enabled = \(!currentState)")
                }
            }
            .padding(.horizontal, 8)
            
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        // Estética Glassmorphism Cyberpunk profunda
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [.cyan.opacity(0.8), .purple.opacity(0.3)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        // Shadow envolvente estilo resplandor neón constante
        .shadow(color: .cyan.opacity(0.2), radius: 10)
    }
}

struct ToolButton: View {
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            // Micro-animaciones tácticas al pasar el cursor
            NSCursor.pointingHand.set()
        }
    }
}
