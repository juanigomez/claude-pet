# Publicar en GitHub

Sí: un repo de GitHub con **Releases** alcanza perfectamente para que tus amigos la
instalen. Lo único que GitHub no puede resolver es la firma — eso lo decide Apple, no
el lugar de donde se descarga. Ver «Sobre el aviso de Gatekeeper» abajo.

## Crear el repo

Desde la carpeta del proyecto:

```bash
git init
git add .
git commit -m "Claw'd Pet"

gh repo create claude-pet --public --source=. --push
```

El `.gitignore` ya excluye `build/`, `dist/` y los `xcuserdata`.

## Publicar una versión

```bash
./Scripts/release.sh 1.0
gh release create v1.0 dist/ClawdPet-1.0.zip \
  --title "Claw'd Pet 1.0" \
  --notes "Primera versión. Ver docs/INSTALAR.md para los pasos de instalación."
```

El script compila en Release con Xcode, firma y empaqueta con `ditto -c -k` (un `zip`
común rompe la firma del bundle).

Poné el link a [`docs/INSTALAR.md`](INSTALAR.md) en las notas de la release: es lo que
tus amigos van a necesitar leer para el paso del aviso de seguridad.

## Sobre el aviso de Gatekeeper

Hay tres niveles, y el costo sube con cada uno:

| Firma | Qué ven tus amigos | Costo |
|---|---|---|
| **Ad-hoc** (lo que hace el script hoy) | «Apple no puede comprobar…». Se resuelve con click derecho ▸ Abrir, una vez. | gratis |
| **Developer ID** | Aviso más suave, pero igual aparece si no está notarizada. | 99 USD/año |
| **Developer ID + notarización** | Nada. Doble click y abre. | 99 USD/año |

El script ya soporta los tres. Para el tercero, una vez que tengas la cuenta:

```bash
# Una sola vez: guardar credenciales en el llavero
xcrun notarytool store-credentials clawdpet \
  --apple-id tu@email.com --team-id TUTEAMID --password <app-specific-password>

export CLAWDPET_SIGN_IDENTITY="Developer ID Application: Tu Nombre (TUTEAMID)"
export CLAWDPET_NOTARY_PROFILE="clawdpet"
./Scripts/release.sh 1.0
```

La `--password` es una **app-specific password** de appleid.apple.com, no la de tu
cuenta.

## Si querés que compile solo en cada tag

Un workflow mínimo en `.github/workflows/release.yml`:

```yaml
name: release
on:
  push:
    tags: ["v*"]
jobs:
  build:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - run: ./Scripts/release.sh "${GITHUB_REF_NAME#v}"
      - uses: softprops/action-gh-release@v2
        with:
          files: dist/*.zip
```

Los runners de macOS son gratis en repos públicos. Para notarizar desde CI habría que
meter el certificado y las credenciales como secrets — vale la pena sólo si ya tenés
la cuenta de developer.
