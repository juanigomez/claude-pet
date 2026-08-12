# Instalar Claw'd Pet

Esto es lo que le pasás a alguien junto con el link de la release.

## 1. Descargar

Bajá `ClawdPet-<version>.zip` desde la pestaña **Releases** del repo y hacé doble click
para descomprimirlo.

## 2. Mover a Aplicaciones

Arrastrá **ClawdPet.app** a tu carpeta `Aplicaciones`. Importa: si la dejás en
Descargas, la opción de «abrir al iniciar sesión» no va a funcionar.

## 3. Abrirla la primera vez

> Esta app está firmada **ad-hoc**, no con una cuenta de Apple Developer. macOS avisa
> la primera vez. Es el mismo aviso que da cualquier app open source que no pagó los
> 99 USD al año.

macOS va a decir algo como *«No se puede abrir "ClawdPet" porque Apple no puede
comprobar que no contenga software malicioso»*.

**Solución (una sola vez):**

1. Click derecho sobre ClawdPet.app → **Abrir**.
2. En el diálogo, **Abrir** de nuevo.

Si esa opción no aparece (macOS 15+ a veces la esconde):

1. Abrí **Ajustes del Sistema ▸ Privacidad y seguridad**.
2. Bajá hasta el mensaje sobre ClawdPet y tocá **Abrir igualmente**.

O desde la terminal, en una línea:

```bash
xattr -dr com.apple.quarantine /Applications/ClawdPet.app
```

Después de la primera vez, se abre normal.

## 4. Dar permiso de Accesibilidad

Al abrirla por primera vez sale un diálogo del sistema: *«ClawdPet» quiere controlar
esta computadora usando funciones de accesibilidad*. Tocá **Abrir Ajustes del Sistema**
y activá el switch de **ClawdPet** en la lista.

Ojo: en la lista figura como **ClawdPet**, sin el `.app` — macOS muestra el nombre, no
el archivo.

Se da **una sola vez**: la app se firma con un requisito atado a su bundle identifier,
así que el permiso sobrevive a las actualizaciones.

Si descartaste el diálogo y no volvió a aparecer, en la terminal:

```bash
tccutil reset Accessibility com.clawdpet.ClawdPet
open /Applications/ClawdPet.app
```

Lo usa para tres cosas: saber dónde está la ventana de la app que te reclama algo,
medir el ancho del Dock para no pasarse de largo, y escribir en Claude Desktop cuando
le preguntás algo. No lee contenido de tus ventanas.

Sin el permiso la mascota igual funciona, sólo que rebota donde esté en vez de caminar
hacia la app.

## 5. Conectarla con Claude Code (opcional)

**Preferencias ▸ Integración ▸ Conectar ahora.** Eso instala `clawdpet` y
`clawdpet-hook` en `~/.local/bin` y escribe los hooks en `~/.claude/settings.json`
(con backup del que tengas). Abrí una sesión nueva de Claude Code y listo: la mascota
muestra "…" mientras trabaja, salta cuando necesita tu OK, y vuelve a caminar al
terminar.

## Desinstalar

```bash
rm -rf /Applications/ClawdPet.app
rm -rf ~/Library/Application\ Support/ClawdPet
rm -f ~/.local/bin/clawdpet ~/.local/bin/clawdpet-hook
```

Y sacá los hooks de `~/.claude/settings.json` (o restaurá alguno de los
`settings.json.clawdpet-backup-*` que quedaron al lado).
