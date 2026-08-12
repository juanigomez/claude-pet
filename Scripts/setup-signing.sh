#!/bin/bash
# Crea un certificado auto-firmado para firmar Claw'd Pet SIEMPRE IGUAL.
#
#   ./Scripts/setup-signing.sh
#
# ## Por qué
#
# Una firma ad-hoc (`codesign -s -`) produce un requisito designado que es un hash
# desnudo del binario:
#
#     designated => cdhash H"ddc3844057e51075084af91a04a75b637e2016a8"
#
# macOS guarda ESE requisito cuando le das permiso de Accesibilidad. Cambiás una línea
# de código, recompilás, el hash cambia — y el permiso que habías dado deja de aplicar,
# aunque el switch siga encendido en Ajustes. Por eso "ya se lo di y sigue sin andar".
#
# Con un certificado propio, el requisito pasa a ser:
#
#     designated => identifier "com.clawdpet.ClawdPet" and certificate leaf = H"…"
#
# …que sobrevive a las recompilaciones. Das el permiso una vez y listo.
#
# ## Qué hace
#
# 1. Genera un certificado auto-firmado válido para code signing (10 años).
# 2. Lo importa a tu llavero de inicio de sesión.
# 3. Lo marca como confiable para firmar código.
#
# El paso 3 abre un diálogo del sistema pidiendo tu contraseña: es macOS pidiendo
# permiso para tocar los ajustes de confianza del llavero. Es esperable.
#
# Después de correrlo, `build-without-xcode.sh` y `release.sh` usan la identidad sola.
# En Xcode: target ClawdPet ▸ Signing & Capabilities ▸ Manual ▸ "ClawdPet Dev".

set -euo pipefail

IDENTITY="${CLAWDPET_SIGN_IDENTITY:-ClawdPet Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/clawdpet-cert.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "✔ La identidad «$IDENTITY» ya existe y es válida. No hay nada que hacer."
  exit 0
fi

# Puede quedar un certificado a medio instalar (importado pero sin confianza): sin esto
# acumularíamos duplicados con el mismo nombre y codesign no sabría cuál usar.
while security find-certificate -c "$IDENTITY" >/dev/null 2>&1; do
  security delete-certificate -c "$IDENTITY" >/dev/null 2>&1 || break
done

echo "▸ Generando certificado «$IDENTITY»…"
cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions    = v3
prompt             = no
[dn]
CN = $IDENTITY
[v3]
basicConstraints     = critical,CA:false
keyUsage             = critical,digitalSignature
extendedKeyUsage     = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK/cert.key" -out "$WORK/cert.crt" -config "$WORK/cert.cnf" 2>/dev/null

# `-legacy` / los algoritmos viejos son obligatorios: el Security framework de macOS
# no lee los PKCS#12 que genera OpenSSL 3 por defecto (falla el MAC verification).
openssl pkcs12 -export -inkey "$WORK/cert.key" -in "$WORK/cert.crt" \
  -out "$WORK/cert.p12" -passout pass:clawdpet -name "$IDENTITY" \
  -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES 2>/dev/null

echo "▸ Importando al llavero…"
security import "$WORK/cert.p12" -k "$KEYCHAIN" -P clawdpet -T /usr/bin/codesign -A

echo "▸ Marcándolo como confiable para firmar código."
echo "  macOS va a pedirte tu contraseña — es para tocar los ajustes de confianza."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.crt"

echo
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  echo "✔ Listo. Ahora:"
  echo "    ./Scripts/build-without-xcode.sh"
  echo "  y volvé a dar el permiso de Accesibilidad UNA vez más (la firma cambió)."
  echo "  A partir de ahí sobrevive a todas las recompilaciones."
else
  echo "✗ El certificado quedó importado pero no confiable."
  echo "  Abrí Acceso a Llaveros, buscá «$IDENTITY», doble click ▸ Confiar ▸"
  echo "  «Firma de código: Confiar siempre»."
  exit 1
fi
