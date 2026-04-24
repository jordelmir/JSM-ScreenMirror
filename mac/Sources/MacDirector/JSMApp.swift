import SwiftUI

@main
struct MacDirectorApp: App {
    @StateObject private var engine = RuntimeOrchestrator()
    
    // ═══ ANTI APP-NAP ═══
    // macOS App Nap puede suspender la app si no está visible,
    // matando la conexión WebRTC. Esto lo previene.
    private let activity = ProcessInfo.processInfo.beginActivity(
        options: [.userInitiated, .idleSystemSleepDisabled, .suddenTerminationDisabled],
        reason: "Elysium Vanguard: WebRTC P2P streaming activo"
    )

    var body: some Scene {
        WindowGroup {
            ZStack {
                DashboardView()
                    .environmentObject(engine)
                
                // Si el motor arrancó, mostrar HUD flotante en la parte inferior
                if engine.isBooted {
                    VStack {
                        Spacer()
                        HUDOverlayView()
                            .environmentObject(engine)
                            .padding(.bottom, 20)
                    }
                }
            }
            .onDisappear {
                engine.shutdownEngine()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        
        WindowGroup("Elysium Android Preview", id: "androidPreview") {
            AndroidPreviewWindow()
                .environmentObject(engine)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic) // Permitir resize libre
        .defaultSize(width: 480, height: 860) // Tamaño inicial más grande
    }
}
