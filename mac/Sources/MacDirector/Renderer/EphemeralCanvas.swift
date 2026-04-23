import SwiftUI

/// Representa una pincelada o vector efímero en pantalla
struct EphemeralStroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]
    let color: Color
    let creationDate: Date = Date()
    
    // Si la opacidad llega a 0, la vista matriz lo destruye de la UI.
    var currentOpacity: Double = 1.0
}

/// Herramienta de Overlay Transparente que se encarga de dibujar el Neon "Mágico" que desaparece a los 3s
@MainActor
class EphemeralEngine: ObservableObject {
    @Published var activeStrokes: [EphemeralStroke] = []
    @Published var currentStroke: EphemeralStroke?
    
    // Spotlight Logic
    @Published var isSpotlightActive = false
    @Published var spotlightPosition: CGPoint = .zero
    
    // Temporizador principal de evaporación (Corre a 60hz)
    private var evaporationTimer: Timer?
    
    init() {
        startEvaporationLoop()
    }
    
    private func startEvaporationLoop() {
        evaporationTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaporateTicks()
            }
        }
    }
    
    private func evaporateTicks() {
        let now = Date()
        var aliveStrokes: [EphemeralStroke] = []
        
        for var stroke in activeStrokes {
            let age = now.timeIntervalSince(stroke.creationDate)
            
            // Vida total: 2.0 Segundos. Desvanecimiento empieza tras 0.5s.
            if age > 0.5 {
                let fadeProgress = (age - 0.5) / 1.5
                stroke.currentOpacity = max(0.0, 1.0 - fadeProgress)
            }
            
            if stroke.currentOpacity > 0.05 {
                aliveStrokes.append(stroke)
            }
        }
        
        // Asignamos solo los trazos que siguen vivos
        if activeStrokes.count != aliveStrokes.count || aliveStrokes.contains(where: { $0.currentOpacity < 1.0 }) {
            Task { @MainActor in
                self.activeStrokes = aliveStrokes
            }
        }
    }
}

/// Capa de SwiftUI puramente transparente para flotar sobre el video y quemarse allí.
struct EphemeralCanvas: View {
    @StateObject private var engine = EphemeralEngine()
    
    var body: some View {
        ZStack {
            // Capa Spotlight
            if engine.isSpotlightActive {
                Color.black.opacity(0.8)
                    .mask(
                        RadialGradient(
                            gradient: Gradient(colors: [.black, .clear]),
                            center: .init(
                                x: engine.spotlightPosition.x / (NSScreen.main?.frame.width ?? 1.0),
                                y: engine.spotlightPosition.y / (NSScreen.main?.frame.height ?? 1.0)
                            ),
                            startRadius: 0,
                            endRadius: 150
                        )
                        .compositingGroup()
                        .luminanceToAlpha()
                    )
                    .allowsHitTesting(false)
            }
            
            // Lienzo Neon Permanente
            Canvas { context, size in
                // Trazos congelados evaporándose
                for stroke in engine.activeStrokes {
                    var path = Path()
                    path.addLines(stroke.points)
                    
                    context.stroke(
                        path,
                        with: .color(stroke.color.opacity(stroke.currentOpacity)),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                    )
                    // Efecto Neon Glow Multiplicado
                    context.addFilter(.blur(radius: 4))
                    context.stroke(
                        path,
                        with: .color(stroke.color.opacity(stroke.currentOpacity * 0.5)),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round)
                    )
                }
                
                // Trazo actuando en tiempo real (evita lag)
                if let curr = engine.currentStroke {
                    var path = Path()
                    path.addLines(curr.points)
                    context.stroke(
                        path,
                        with: .color(.cyan),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                    )
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if engine.isSpotlightActive {
                            engine.spotlightPosition = value.location
                            return
                        }
                        
                        if engine.currentStroke == nil {
                            engine.currentStroke = EphemeralStroke(points: [value.location], color: .cyan)
                        } else {
                            engine.currentStroke?.points.append(value.location)
                        }
                    }
                    .onEnded { value in
                        if let curr = engine.currentStroke {
                            engine.activeStrokes.append(curr)
                            engine.currentStroke = nil
                        }
                    }
            )
        }
        .edgesIgnoringSafeArea(.all)
    }
}
