#!/bin/bash
# Arma el .zip de release listo para subir a GitHub Releases.
#
#   ./Scripts/release.sh [version]
#
# Compila en Release con Xcode, firma ad-hoc y empaqueta con `ditto -c -k`, que es el
# formato que espera macOS (conserva los symlinks y los metadatos del bundle; un `zip`
# común te rompe la firma).
#
# Si tenés cuenta de Apple Developer, exportá estas variables y el script firma con
# Developer ID y notariza — tus amigos no ven ninguna advertencia:
#
#   export CLAWDPET_SIGN_IDENTITY="Developer ID Application: Tu Nombre (TEAMID)"
#   export CLAWDPET_NOTARY_PROFILE="clawdpet"   # perfil guardado con:
#   #   xcrun notarytool store-credentials clawdpet --apple-id … --team-id … --password …

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-$(date +%Y.%m.%d)}"
DIST="$ROOT/dist"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/clawdpet-release.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
XCODEBUILD="$DEVELOPER_DIR/usr/bin/xcodebuild"

echo "▸ Compilando ClawdPet $VERSION en Release…"
"$XCODEBUILD" \
  -project "$ROOT/ClawdPet.xcodeproj" \
  -scheme ClawdPet \
  -configuration Release \
  -derivedDataPath "$STAGE/dd" \
  MARKETING_VERSION="$VERSION" \
  build > "$STAGE/build.log" 2>&1 || { tail -40 "$STAGE/build.log"; exit 1; }

APP="$STAGE/dd/Build/Products/Release/ClawdPet.app"
[[ -d "$APP" ]] || { echo "No se generó la app"; exit 1; }

# Xcode copia AppIcon.icns como recurso pero ignora `INFOPLIST_KEY_CFBundleIconFile`,
# así que la clave se inyecta a mano. Va ANTES de firmar: tocar el Info.plist después
# invalida la firma.
if [[ -f "$APP/Contents/Resources/AppIcon.icns" ]]; then
  /usr/bin/plutil -replace CFBundleIconFile -string AppIcon "$APP/Contents/Info.plist"
fi

if [[ -n "${CLAWDPET_SIGN_IDENTITY:-}" ]]; then
  echo "▸ Firmando con Developer ID…"
  codesign --force --options runtime --timestamp \
    --sign "$CLAWDPET_SIGN_IDENTITY" "$APP/Contents/Resources/clawdpet"
  codesign --force --options runtime --timestamp \
    --sign "$CLAWDPET_SIGN_IDENTITY" "$APP"
else
  # Re-firmamos igual: tocar el Info.plist arriba invalidó la firma que puso Xcode.
  #
  # Con el requisito designado por defecto (el hash del binario), cada versión nueva
  # invalida el permiso de Accesibilidad que la gente ya dio, y hay que explicarles que
  # lo vuelvan a dar en cada update. Lo atamos al bundle identifier para que sobreviva.
  #
  # Es más laxo a propósito: otra app que se hiciera pasar por este identifier heredaría
  # el permiso. Como la app se distribuye sin firmar de todas formas, el riesgo adicional
  # es acotado frente al costo de re-pedirlo siempre. Con Developer ID esto no hace falta
  # (el requisito queda atado al certificado), y por eso arriba no se aplica.
  echo "▸ Firmando ad-hoc con requisito estable por identifier."
  codesign --force --sign - "$APP/Contents/Resources/clawdpet"
  codesign --force --sign - \
    -r='designated => identifier "com.clawdpet.ClawdPet"' "$APP"
fi

codesign --verify --strict "$APP"

mkdir -p "$DIST"
# Nombre FIJO, sin versión: así el link `releases/latest/download/ClawdPet.zip` de la
# landing sigue funcionando en cada release nueva. La versión va en el tag.
ZIP="$DIST/ClawdPet.zip"
rm -f "$ZIP"
echo "▸ Empaquetando…"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

if [[ -n "${CLAWDPET_NOTARY_PROFILE:-}" ]]; then
  echo "▸ Notarizando (esto tarda unos minutos)…"
  xcrun notarytool submit "$ZIP" --keychain-profile "$CLAWDPET_NOTARY_PROFILE" --wait
  # El staple va sobre la .app, así que reempaquetamos después de pegarle el ticket.
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
  echo "▸ Notarizado y stapleado."
fi

echo
echo "✔ $ZIP"
echo
echo "Para publicarlo:"
echo "  gh release create v$VERSION \"$ZIP\" --title \"Claw'd Pet $VERSION\" \\"
echo "    --notes 'Ver docs/INSTALAR.md para los pasos de instalación.'"
