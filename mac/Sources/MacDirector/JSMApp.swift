import SwiftUI

@main
struct MacDirectorApp: App {
    @StateObject private var engine = RuntimeOrchestrator()

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
    }
}
