#!/bin/bash

# Elysium Vanguard Pro - Release Packager
# Este script automatiza la generación del DMG premium y la inclusión del APK.

set -e

APP_NAME="Elysium Vanguard"
VERSION="1.0.0"
BUILD_DIR="mac/.build/release"
STAGING_DIR="release_staging"
DMG_NAME="Elysium_Vanguard_Pro_V1.dmg"
APK_PATH="android/app/build/outputs/apk/debug/app-debug.apk"
BG_IMAGE="elysium_dmg_bg_1776686213177.png"

echo "🚀 Iniciando proceso de empaquetado para $APP_NAME..."

# 1. Compilar binario final
echo "📦 Compilando binario de Mac en modo Release..."
swift build --package-path mac -c release

# 1.1 Compilar Shaders Metal (Vanguard Pro Visuals)
echo "🎨 Compilando Shaders Metal..."
METAL_PATH="mac/Sources/MacDirector/Renderer/NeonShaders.metal"
xcrun -sdk macosx metal -c "$METAL_PATH" -o NeonShaders.air
xcrun -sdk macosx metallib NeonShaders.air -o default.metallib
rm NeonShaders.air

# 2. Preparar la estructura del App Bundle si no existe
echo "🏗️ Preparando estructura de la App..."
APP_BUNDLE="$HOME/Applications/$APP_NAME.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

# Copiar Shaders Metal e Icono
cp default.metallib "$APP_BUNDLE/Contents/Resources/"
rm default.metallib

ICON_SRC="mac/Sources/MacDirector/Resources/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$APP_BUNDLE/Contents/Resources/"
fi

# 2.1 Copiar Dependencias Dinámicas (WebRTC)
echo "📦 Copiando dependencias críticas (WebRTC)..."
WEBRTC_FRAMEWORK="mac/.build/arm64-apple-macosx/release/WebRTC.framework"
if [ -d "$WEBRTC_FRAMEWORK" ]; then
    cp -R "$WEBRTC_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/"
    # Firmar el framework (obligatorio para Hardened Runtime)
    codesign --force -s - "$APP_BUNDLE/Contents/Frameworks/WebRTC.framework"
else
    echo "⚠️ ADVERTENCIA: No se encontró WebRTC.framework. La sincronización P2P podría fallar."
fi

# Generar Info.plist vital para macOS
cat <<EOF > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.jsm.elysiumvanguard</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.3</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

BIN_PATH="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$BUILD_DIR/MacDirector" "$BIN_PATH"

# 2.2 Inyectar RPATH para encontrar los Frameworks
echo "🛠️ Ajustando RPATH del binario..."
install_name_tool -add_rpath "@executable_path/../Frameworks" "$BIN_PATH" 2>/dev/null || true

# 3. Firma Ad-hoc con Hardened Runtime y Entitlements
echo "🔐 Aplicando firma digital (Hardened Runtime + Entitlements)..."
ENTITLEMENTS="mac/Elysium.entitlements"
codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" -s - "$APP_BUNDLE"

# 4. Instalación Local en /Applications (Limpia)
echo "📂 Instalando en /Applications..."
FINAL_DEST="/Applications/$APP_NAME.app"
rm -rf "$FINAL_DEST"
cp -R "$APP_BUNDLE" "$FINAL_DEST"
xattr -cr "$FINAL_DEST"

# 5. Crear Carpeta de Staging para el DMG
echo "📂 Creando imagen de staging..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# Incluir el cliente de Android
echo "🤖 Incluyendo instalador de Android (APK)..."
mkdir -p "$STAGING_DIR/Android_Client"
cp "$APK_PATH" "$STAGING_DIR/Android_Client/Elysium_Android_Remote.apk"

# 6. Generar el DMG
echo "💿 Generando archivo DMG final..."
rm -f "$DMG_NAME"
hdiutil create -volname "$APP_NAME Installation" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_NAME"

echo "✅ PROCESO COMPLETADO EXIOTOSAMENTE"
echo "📦 Instalación realizada en: $FINAL_DEST"
echo "📦 Archivo listo para GitHub: $DMG_NAME"
