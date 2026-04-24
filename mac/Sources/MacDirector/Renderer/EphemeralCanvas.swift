import SwiftUI
import os

/// Representa una pincelada o vector efímero en pantalla
struct EphemeralStroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]
    let color: Color
    let creationDate: Date = Date()
    
    // Si la opacidad llega a 0, la vista matriz lo destruye de la UI.
    var currentOpacity: Double = 1.0
}

/// Motor de anotaciones efímeras con cache thread-safe para el pipeline de recording.
///
/// Arquitectura:
/// - `activeStrokes` vive en el hilo principal (SwiftUI)
/// - Cada tick de evaporación (60hz, main thread) reconstruye `_cachedStrokes`
/// - El capture thread de SCStream lee `cachedCompositorStrokes` bajo lock
/// - Las coordenadas del cache están NORMALIZADAS (0.0-1.0) para que
///   MetalCompositor las escale a su resolución de salida
@MainActor
class EphemeralEngine: ObservableObject {
    /// Instancia global. El MainRouter y EphemeralCanvas leen/escriben desde aquí.
    static let shared = EphemeralEngine()
    
    @Published var activeStrokes: [EphemeralStroke] = []
    @Published var currentStroke: EphemeralStroke?
    
    // Spotlight Logic
    @Published var isSpotlightActive = false
    @Published var spotlightPosition: CGPoint = .zero
    
    // Color configurable para el trazo
    @Published var strokeColor: Color = .cyan
    
    // ─── Cache Thread-Safe para MetalCompositor ───
    // Escrito exclusivamente desde el main thread (evaporation tick).
    // Leído desde el capture thread de SCStream via `cachedCompositorStrokes`.
    private static var _cacheLock = os_unfair_lock()
    private static var _cachedStrokes: [CompositorStroke] = []
    
    /// Lectura atómica del snapshot de strokes para el compositor.
    /// Llamado desde el capture thread de SCStream — NUNCA bloquea.
    static var cachedCompositorStrokes: [CompositorStroke] {
        os_unfair_lock_lock(&_cacheLock)
        let snapshot = _cachedStrokes
        os_unfair_lock_unlock(&_cacheLock)
        return snapshot
    }
    
    // Dimensiones del canvas SwiftUI (se actualizan cuando cambia el tamaño de ventana)
    var canvasSize: CGSize = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
    
    // Temporizador principal de evaporación (Corre a 60hz)
    private var evaporationTimer: Timer?
    
    init() {
        startEvaporationLoop()
    }
    
    private func startEvaporationLoop() {
        evaporationTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaporateTick()
            }
        }
    }
    
    private func evaporateTick() {
        let now = Date()
        var aliveStrokes: [EphemeralStroke] = []
        
        for var stroke in activeStrokes {
            let age = now.timeIntervalSince(stroke.creationDate)
            
            // Vida total: 3.0 Segundos. Desvanecimiento empieza tras 1.0s.
            if age > 1.0 {
                let fadeProgress = (age - 1.0) / 2.0
                stroke.currentOpacity = max(0.0, 1.0 - fadeProgress)
            }
            
            if stroke.currentOpacity > 0.05 {
                aliveStrokes.append(stroke)
            }
        }
        
        activeStrokes = aliveStrokes
        
        // ── Reconstruir cache normalizado para el compositor ──
        rebuildCompositorCache()
    }
    
    /// Reconstruye el snapshot thread-safe de strokes con coordenadas normalizadas (0-1).
    /// Solo se ejecuta en el main thread como parte del tick de evaporación.
    private func rebuildCompositorCache() {
        var result: [CompositorStroke] = []
        let cw = max(canvasSize.width, 1.0)
        let ch = max(canvasSize.height, 1.0)
        
        for stroke in activeStrokes {
            guard stroke.points.count >= 2 else { continue }
            // Normalizar puntos a espacio 0.0-1.0
            let normalized = stroke.points.map { p in
                CGPoint(x: p.x / cw, y: p.y / ch)
            }
            result.append(CompositorStroke(
                points: normalized,
                color: NSColor(stroke.color).cgColor,
                opacity: stroke.currentOpacity,
                lineWidth: 6.0 / min(cw, ch) // Normalizar grosor
            ))
        }
        
        // Incluir trazo en curso
        if let curr = currentStroke, curr.points.count >= 2 {
            let normalized = curr.points.map { p in
                CGPoint(x: p.x / cw, y: p.y / ch)
            }
            result.append(CompositorStroke(
                points: normalized,
                color: NSColor(curr.color).cgColor,
                opacity: 1.0,
                lineWidth: 6.0 / min(cw, ch)
            ))
        }
        
        // Escribir atómicamente al cache estático
        EphemeralEngine._cacheLock.withLockUnchecked {
            EphemeralEngine._cachedStrokes = result
        }
    }
}

// ─── Extensión para os_unfair_lock ───
extension os_unfair_lock {
    mutating func withLockUnchecked<R>(_ body: () -> R) -> R {
        os_unfair_lock_lock(&self)
        defer { os_unfair_lock_unlock(&self) }
        return body()
    }
}

/// Capa de SwiftUI puramente transparente para flotar sobre el video.
/// Los strokes se renderizan aquí para feedback visual instantáneo,
/// y simultáneamente se inyectan al MetalCompositor para que aparezcan en el MP4.
struct EphemeralCanvas: View {
    @ObservedObject private var engine = EphemeralEngine.shared
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Capa Spotlight
                if engine.isSpotlightActive {
                    Color.black.opacity(0.8)
                        .mask(
                            RadialGradient(
                                gradient: Gradient(colors: [.black, .clear]),
                                center: .init(
                                    x: engine.spotlightPosition.x / geometry.size.width,
                                    y: engine.spotlightPosition.y / geometry.size.height
                                ),
                                startRadius: 0,
                                endRadius: 150
                            )
                            .compositingGroup()
                            .luminanceToAlpha()
                        )
                        .allowsHitTesting(false)
                }
                
                // Lienzo Neon
                Canvas { context, size in
                    // Trazos congelados evaporándose
                    for stroke in engine.activeStrokes {
                        guard stroke.points.count >= 2 else { continue }
                        var path = Path()
                        path.addLines(stroke.points)
                        
                        // Pass 1: Glow exterior
                        context.stroke(
                            path,
                            with: .color(stroke.color.opacity(stroke.currentOpacity * 0.4)),
                            style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round)
                        )
                        // Pass 2: Núcleo brillante
                        context.stroke(
                            path,
                            with: .color(stroke.color.opacity(stroke.currentOpacity)),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                        )
                    }
                    
                    // Trazo en tiempo real
                    if let curr = engine.currentStroke, curr.points.count >= 2 {
                        var path = Path()
                        path.addLines(curr.points)
                        context.stroke(
                            path,
                            with: .color(engine.strokeColor.opacity(0.4)),
                            style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round)
                        )
                        context.stroke(
                            path,
                            with: .color(engine.strokeColor),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
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
                                engine.currentStroke = EphemeralStroke(
                                    points: [value.location],
                                    color: engine.strokeColor
                                )
                            } else {
                                engine.currentStroke?.points.append(value.location)
                            }
                        }
                        .onEnded { _ in
                            if let curr = engine.currentStroke {
                                engine.activeStrokes.append(curr)
                                engine.currentStroke = nil
                            }
                        }
                )
            }
            .onAppear {
                engine.canvasSize = geometry.size
            }
            .onChange(of: geometry.size) { _, newSize in
                engine.canvasSize = newSize
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
}
