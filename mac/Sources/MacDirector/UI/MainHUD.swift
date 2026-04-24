import SwiftUI

/// Panel UI flotante para la Mac que rige el Drag Handle y el Glassmorphism oscuro.
/// Conectado directamente a EphemeralEngine.shared para que los botones de herramientas
/// activen/desactiven el modo de dibujo y spotlight en tiempo real.
struct HUDOverlayView: View {
    @EnvironmentObject var engine: RuntimeOrchestrator
    @ObservedObject private var annotationEngine = EphemeralEngine.shared
    @State private var dragOffset = CGSize.zero
    
    var body: some View {
        HStack(spacing: 12) {
            
            // Drag Handle industrial (3 Barras)
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.gray.opacity(0.7))
                        .frame(width: 4, height: 18)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
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
                
                // Lápiz Neón — activa modo dibujo en EphemeralEngine
                ToolButton(
                    icon: "pencil.and.outline",
                    color: !annotationEngine.isSpotlightActive ? .cyan : .gray,
                    isActive: !annotationEngine.isSpotlightActive
                ) {
                    if annotationEngine.isSpotlightActive {
                        annotationEngine.isSpotlightActive = false
                    }
                    SensoryFeedbackManager.shared.triggerHapticGeneric()
                }
                
                // Spotlight Radar — activa modo spotlight en EphemeralEngine
                ToolButton(
                    icon: "dot.radiowaves.up.forward",
                    color: annotationEngine.isSpotlightActive ? .green : .gray,
                    isActive: annotationEngine.isSpotlightActive
                ) {
                    annotationEngine.isSpotlightActive.toggle()
                    SensoryFeedbackManager.shared.triggerHapticGeneric()
                }

                Divider()
                    .background(Color.white.opacity(0.1))
                    .frame(height: 18)
                
                // Color picker para el trazo neón
                HStack(spacing: 6) {
                    ForEach([Color.cyan, Color.red, Color.green, Color.yellow, Color.purple], id: \.self) { color in
                        Circle()
                            .fill(color)
                            .frame(width: annotationEngine.strokeColor == color ? 14 : 10, height: annotationEngine.strokeColor == color ? 14 : 10)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(annotationEngine.strokeColor == color ? 0.8 : 0), lineWidth: 1.5)
                            )
                            .onTapGesture {
                                annotationEngine.strokeColor = color
                                SensoryFeedbackManager.shared.triggerHapticGeneric()
                            }
                            .animation(.spring(response: 0.2), value: annotationEngine.strokeColor == color)
                    }
                }

                Divider()
                    .background(Color.white.opacity(0.1))
                    .frame(height: 18)

                // Switch Mac-only vs Mac+Android
                ToolButton(
                    icon: (engine.metalCompositor?.isAndroidOverlayEnabled ?? true) ? "iphone.badge.plus" : "desktopcomputer", 
                    color: (engine.metalCompositor?.isAndroidOverlayEnabled ?? true) ? .cyan : .gray
                ) {
                    let currentState = engine.metalCompositor?.isAndroidOverlayEnabled ?? true
                    engine.metalCompositor?.isAndroidOverlayEnabled = !currentState
                    SensoryFeedbackManager.shared.playMechanicalClick()
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
        .shadow(color: .cyan.opacity(0.2), radius: 10)
    }
}

struct ToolButton: View {
    let icon: String
    let color: Color
    var isActive: Bool = false
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)
                .scaleEffect(isHovered ? 1.15 : 1.0)
                .animation(.spring(response: 0.2), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
