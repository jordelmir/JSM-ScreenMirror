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
        
        WindowGroup("Elysium Android Preview", id: "androidPreview") {
            AndroidPreviewWindow()
                .environmentObject(engine)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 360, height: 780)
    }
}
