#!/bin/bash
# Compila ClawdPet.app sin abrir Xcode, usando swiftc + las Command Line Tools.
#
#   ./Scripts/build-without-xcode.sh [--run]
#
# Útil para probar rápido desde la terminal. El proyecto Xcode (ClawdPet.xcodeproj)
# produce exactamente lo mismo con ⌘R; esto es un atajo, no un reemplazo.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
FINAL="$BUILD/ClawdPet.app"
SDK="$(xcrun --show-sdk-path)"
TARGET="arm64-apple-macos14.0"

# Armamos y firmamos en un staging temporal. Si el proyecto vive en el Desktop
# (sincronizado por iCloud), el file provider le pega `com.apple.FinderInfo` al
# bundle una y otra vez y `codesign` falla con "resource fork … not allowed".
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/clawdpet-build.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/ClawdPet.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# El ícono se genera del mismo sprite que dibuja la app (ver Scripts/make-icon.swift).
if [[ ! -f "$ROOT/ClawdPet/AppIcon.icns" ]]; then
  echo "▸ Generando el ícono…"
  ( cd "$ROOT" && xcrun swift Scripts/make-icon.swift >/dev/null )
fi
cp "$ROOT/ClawdPet/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Compilando el CLI…"
xcrun swiftc -sdk "$SDK" -target "$TARGET" -swift-version 5 -O \
  -o "$APP/Contents/Resources/clawdpet" \
  "$ROOT/ClawdPetCLI/main.swift"

echo "▸ Compilando la app…"
# Array en vez de $(find …) suelto: la ruta del proyecto puede tener espacios.
SOURCES=()
while IFS= read -r -d '' file; do SOURCES+=("$file"); done \
  < <(find "$ROOT/ClawdPet" -name '*.swift' -print0)

xcrun swiftc -sdk "$SDK" -target "$TARGET" -swift-version 5 -O \
  -o "$APP/Contents/MacOS/ClawdPet" \
  "${SOURCES[@]}"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleDisplayName</key><string>Claw'd Pet</string>
	<key>CFBundleExecutable</key><string>ClawdPet</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundleIdentifier</key><string>com.clawdpet.ClawdPet</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>ClawdPet</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
	<key>LSUIElement</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# ── Firma ──
#
# Por defecto una firma ad-hoc deja un requisito designado que es el hash del binario:
#
#     designated => cdhash H"ddc38440…"
#
# macOS guarda ESE requisito cuando le das permiso de Accesibilidad, así que cualquier
# recompilación lo invalida y hay que volver a darlo. Para builds locales pasamos un
# requisito explícito atado sólo al bundle identifier:
#
#     designated => identifier "com.clawdpet.ClawdPet"
#
# …que sobrevive a las recompilaciones. Es a propósito más laxo que el default: otra
# app que se hiciera pasar por este identifier heredaría el permiso. Para una app que
# compilás y usás vos es un intercambio razonable; para lo que se distribuye NO se usa
# (`release.sh` firma normal, y con Developer ID si lo tenés).
IDENTITY="${CLAWDPET_SIGN_IDENTITY:-ClawdPet Dev}"
REQUIREMENT='designated => identifier "com.clawdpet.ClawdPet"'
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  SIGN_AS="$IDENTITY"
  REQ_ARGS=()
  echo "▸ Firmando con «$IDENTITY»…"
else
  SIGN_AS="-"
  REQ_ARGS=(-r "=$REQUIREMENT")  # el «=» le dice a codesign que es texto inline, no un archivo
  echo "▸ Firmando ad-hoc con requisito estable por identifier."
fi

xattr -cr "$APP"
codesign --force --sign "$SIGN_AS" "$APP/Contents/Resources/clawdpet"
codesign --force --sign "$SIGN_AS" "${REQ_ARGS[@]}" "$APP"
codesign --verify --strict "$APP"
echo "▸ Requisito designado: $(codesign -d -r- "$APP" 2>&1 | tail -1 | sed 's/^# //')"

echo "▸ Copiando a build/…"
mkdir -p "$BUILD"
rm -rf "$FINAL"
ditto "$APP" "$FINAL"

echo "✔ Listo: $FINAL"

if [[ "${1:-}" == "--run" ]]; then
  echo "▸ Abriendo…"
  open "$FINAL"
fi
