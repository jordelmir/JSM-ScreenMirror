import SwiftUI

/// Panel UI flotante para la Mac que rige el Drag Handle y el Glassmorphism oscuro.
struct HUDOverlayView: View {
    // Gestor de posición arrastrable táctica
    @State private var dragOffset = CGSize.zero
    
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
                ToolButton(icon: "record.circle", color: .red) {
                    print("Start Record")
                }
                
                ToolButton(icon: "pencil.and.outline", color: .cyan) {
                    print("Lápiz Neón")
                }
                
                ToolButton(icon: "dot.radiowaves.up.forward", color: .green) {
                    print("Spotlight Radar")
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
