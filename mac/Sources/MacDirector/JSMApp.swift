import SwiftUI

@main
struct MacDirectorApp: App {
    @StateObject private var engine = RuntimeOrchestrator()

    var body: some Scene {
        // Ventana principal purasangre Metal sin los cromados de sistema
        WindowGroup {
            ZStack {
                CompositorCanvasView(mtkView: engine.mtkView)
                    .ignoresSafeArea()
                
                // La UI Cyberpunk Flotante
                VStack {
                    Spacer()
                    HUDOverlayView()
                        .padding(.bottom, 20)
                }
            }
            .onAppear {
                engine.bootEngine()
            }
        }
        .windowStyle(.hiddenTitleBar)
    }
}
