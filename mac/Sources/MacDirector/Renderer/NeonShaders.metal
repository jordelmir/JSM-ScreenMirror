#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float timeTTL; // Time To Live restante
};

// ==========================================
// SHADER: Lápiz Láser Neón
// ==========================================
// Calcula la distancia matemática a un segmento para iluminar el "núcleo" de blanco
// y los píxeles adyacentes con un glow fosforescente neón.
fragment float4 laserNeonFragment(VertexOut in [[stage_in]],
                                  constant float &distanceToStroke [[buffer(0)]],
                                  constant float3 &neonColor [[buffer(1)]]) {
                                      
    float coreRadius = 2.0;    // Núcleo blanco caliente
    float glowRadius = 15.0;   // Halo fosforescente brillante
    
    // Disolución Glitch cuando se acaba el tiempo de vida (TTL)
    float alphaDecline = smoothstep(0.0, 1.5, in.timeTTL);
    if (in.timeTTL < 0.5) {
        // Fractal/Noise simple para corromper los bordes en el último medio segundo
        float noise = fract(sin(dot(in.uv, float2(12.9898, 78.233))) * 43758.5453);
        if (noise > (in.timeTTL * 2.0)) {
            discard_fragment();
        }
    }
    
    // El núcleo duro interno
    if (distanceToStroke < coreRadius) {
        return float4(1.0, 1.0, 1.0, alphaDecline); 
    } 
    // Decaimiento exponencial para el haz de neón suave
    else if (distanceToStroke < glowRadius) {
        float intensity = pow((glowRadius - distanceToStroke) / glowRadius, 1.5);
        return float4(neonColor * intensity, intensity * alphaDecline);
    }
    
    return float4(0, 0, 0, 0);
}

// ==========================================
// SHADER: Spotlight de Pulso (Latido)
// ==========================================
fragment float4 spotlightPulseFragment(VertexOut in [[stage_in]],
                                       constant float2 &centerPos [[buffer(0)]],
                                       constant float &time [[buffer(1)]]) {
                                           
    float distance = length(in.uv - centerPos);
    // Calculo de onda sinusoidal basada en tiempo para el latido
    float pulse = sin(time * 5.0) * 0.05; 
    
    float spotlightRadius = 0.2 + pulse;
    
    // Oscurece profundamente todo, excepto el radar del spotlight
    if (distance > spotlightRadius) {
        float falloff = smoothstep(spotlightRadius, spotlightRadius + 0.1, distance);
        return float4(0.0, 0.0, 0.0, 0.85 * falloff); // Fondo oscurecido (.ultraThin 느낌)
    }
    
    // El foco iluminado no modifica el color original, solo pasa
    return float4(0, 0, 0, 0);
}

// ==========================================
// SHADER: Puntero Radar (Ondas Holográficas)
// ==========================================
fragment float4 radarHoloFragment(VertexOut in [[stage_in]],
                                  constant float2 &clickPos [[buffer(0)]],
                                  constant float &elapsedTime [[buffer(1)]]) {
                                      
    float dist = length(in.uv - clickPos);
    float waveSpeed = 2.0;
    float waveFrequency = 20.0;
    
    float wavePhase = (dist - elapsedTime * waveSpeed) * waveFrequency;
    float waveAmplitude = sin(max(0.0, wavePhase));
    
    // Decay radiante en el tiempo y distancia
    float edgeDecay = smoothstep(0.5, 0.0, dist) * smoothstep(1.5, 0.5, elapsedTime);
    
    float intensity = exp(-1.5 * wavePhase) * waveAmplitude * edgeDecay;
    intensity = saturate(intensity);
    
    // Cian eléctrico holográfico para las ondas
    float3 cyanNeon = float3(0.0, 0.8, 1.0);
    
    return float4(cyanNeon * intensity, intensity);
}

// ==========================================
// SHADER: Data Rain (Efecto tras recuadro Android)
// ==========================================
fragment float4 dataRainFragment(VertexOut in [[stage_in]],
                                 constant float &time [[buffer(0)]]) {
    // Escala del "cristal"
    float2 uv = in.uv * float2(20.0, 5.0);
    float drop = fract(sin(dot(float2(floor(uv.x)), float2(12.9898, 78.233))) * 43758.5453);
    
    // Caída vertical controlada por tiempo y drop aleatorio por columna
    float yOffset = fract(uv.y - time * (1.0 + drop * 2.0));
    
    // Glow verde cibernético para las gotas que están al fondo (detrás del recuadro del Magic V2)
    float intensity = smoothstep(0.8, 1.0, yOffset) * 0.4;
    return float4(0.0, intensity, 0.2 * intensity, intensity); // RGBA
}
