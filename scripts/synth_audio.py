import math
import struct
import wave
import random

def generate_wave(filename, duration, synth_type):
    sample_rate = 44100
    num_samples = int(duration * sample_rate)
    
    with wave.open(filename, 'w') as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        
        for i in range(num_samples):
            t = float(i) / sample_rate
            val = 0.0
            
            if synth_type == 'confirm':
                # Fast sweep digital confirm 
                env = math.exp(-t * 6.0)
                freq = 880.0 + (1200.0 * t) # freq sweep
                # Square wave / Sawtooth mix for "digital" feel
                sine = math.sin(2.0 * math.pi * freq * t)
                val = 1.0 if sine > 0 else -1.0
                val *= env * 0.4
                
            elif synth_type == 'click':
                # Tactile mechanical click, white noise + low punch
                env = math.exp(-t * 80.0)
                punch = math.sin(2.0 * math.pi * 150.0 * t) * env
                noise = (random.random() * 2.0 - 1.0) * env * 0.5
                val = punch + noise
            
            # clamp and pack
            val = max(-1.0, min(1.0, val))
            amplitude = 32767.0
            packed_value = struct.pack('h', int(val * amplitude))
            wav_file.writeframes(packed_value)

# Generation
generate_wave('mac/Sources/MacDirector/Resources/cyber_confirm.wav', 0.4, 'confirm')
generate_wave('mac/Sources/MacDirector/Resources/mech_click.wav', 0.15, 'click')
print("¡Sonidos cibernéticos sintetizados generados con éxito!")
