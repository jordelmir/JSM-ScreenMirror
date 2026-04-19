package com.jsm.core

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.jsm.core.sensory.SensoryFeedbackManager
import com.jsm.core.signaling.NsdBroadcaster

class MainActivity : ComponentActivity() {

    private lateinit var nsdBroadcaster: NsdBroadcaster
    private lateinit var sensoryFeedback: SensoryFeedbackManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        nsdBroadcaster = NsdBroadcaster(this)
        sensoryFeedback = SensoryFeedbackManager(this)

        setContent {
            MaterialTheme(colorScheme = darkColorScheme(background = Color(0xFF0F0F13))) {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    CyberPunkControlPanel()
                }
            }
        }
    }

    @Composable
    fun CyberPunkControlPanel() {
        var isBroadcasting by remember { mutableStateOf(false) }

        Column(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = "JSM Magic Link",
                color = Color(0xFF00E5FF), // Cyan Neón
                style = MaterialTheme.typography.headlineLarge.copy(fontWeight = FontWeight.Bold)
            )
            
            Spacer(modifier = Modifier.height(60.dp))
            
            Button(
                onClick = {
                    isBroadcasting = !isBroadcasting
                    if (isBroadcasting) {
                        nsdBroadcaster.startBroadcasting(9999)
                        sensoryFeedback.triggerPairingSuccess()
                    } else {
                        nsdBroadcaster.stopBroadcasting()
                    }
                },
                shape = RoundedCornerShape(12.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (isBroadcasting) Color(0xFF00E5FF).copy(alpha = 0.2f) else Color.DarkGray
                ),
                elevation = ButtonDefaults.buttonElevation(
                    defaultElevation = if (isBroadcasting) 20.dp else 0.dp
                ),
                modifier = Modifier
                    .width(200.dp)
                    .height(60.dp)
            ) {
                Text(
                    text = if (isBroadcasting) "Sincronizando..." else "Iniciar Enlace WebRTC",
                    color = if (isBroadcasting) Color(0xFF00E5FF) else Color.White
                )
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        nsdBroadcaster.stopBroadcasting()
    }
}
