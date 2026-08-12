# Claw'd Pet

Mascota de escritorio pixel-art para macOS que camina sobre el Dock y te muestra qué
está haciendo tu agente de IA. App de barra de menú (`LSUIElement`, sin ícono en el
Dock) con una ventana flotante transparente, un servidor HTTP local para recibir
avisos, y un comando de terminal para dispararlos a mano.

| Estado | Qué se ve |
|---|---|
| **idle** | camina de un lado a otro sobre el Dock |
| **thinking** | se para y aparece la burbuja con "…" en ola |
| **needs_action** | cambia de color, camina hasta la ventana de la app que te reclama, rebota, y **muestra en la burbuja qué app es** |

Click en la mascota → se abre un campo de texto; lo que escribís se responde en la
propia burbuja. Si estaba reclamando atención, el click te lleva a esa app.

- **Instalarla** (para vos o para un amigo): [`docs/INSTALAR.md`](docs/INSTALAR.md)
- **Publicarla en GitHub**: [`docs/PUBLICAR.md`](docs/PUBLICAR.md)

## Qué hay adentro

```
ClawdPet.xcodeproj          Proyecto (2 targets: la app y el CLI)
ClawdPet/
  main.swift                Entry point (NSApplication + AppDelegate)
  AppDelegate.swift         Barra de menú, menú, ventana de Preferencias
  AppCoordinator.swift      Une mascota + ventana + servidor y los sincroniza con la config
  Models/                   PetState, NotifyPayload, PetConfig, TargetApp + AppResolver
  PetView/                  Sprite (SwiftUI Canvas), burbuja, campo de texto, máquina de estados
  WindowManager/            NSPanel flotante y su posicionamiento sobre el Dock
  Detection/                Servidor HTTP, árbol de procesos, AX de ventanas y del Dock,
                            puente a Claude Desktop, instalador de hooks
  Preferences/              UI de configuración, login item, instalador del CLI
ClawdPetCLI/main.swift      El comando `clawdpet`
Scripts/
  build-without-xcode.sh    Compila la .app con swiftc, sin abrir Xcode
  setup-signing.sh          Certificado propio para que el permiso no muera en cada build
  release.sh                Arma el .zip firmado para GitHub Releases
  clawdpet-hook.sh          Copia de referencia del hook
docs/                       Guías de instalación y publicación
```

Sin dependencias externas: AppKit, SwiftUI, Combine, Network y ServiceManagement.

## Requisitos

- macOS 14 Sonoma o superior. Probado en macOS 26 / M4.
- Xcode 16+ — el `.xcodeproj` usa grupos sincronizados con el sistema de archivos
  (`objectVersion = 77`), así que los archivos que agregues a las carpetas aparecen
  solos en el target.

## Compilar y correr

```bash
open ClawdPet.xcodeproj      # scheme ClawdPet, ⌘R
```

El target `ClawdPetCLI` se compila primero (es una dependencia) y el binario `clawdpet`
queda embebido en `ClawdPet.app/Contents/Resources/clawdpet`. Está configurado con
firma «Sign to Run Locally», así que compila sin cuenta de desarrollador.

Sin Xcode:

```bash
./Scripts/build-without-xcode.sh --run
```

> El script compila y firma en un directorio temporal antes de copiar a `build/`.
> Si el proyecto vive en el Desktop con iCloud Drive sincronizando Desktop &
> Documents, el file provider le pega `com.apple.FinderInfo` al bundle y `codesign`
> falla con *"resource fork … not allowed"*.

## Con qué funciona

| Dónde usás Claude | Cómo se entera la mascota | Estado |
|---|---|---|
| **Claude Code en VS Code / Cursor** | hooks | ✅ verificado |
| **Claude Code en Terminal / iTerm / Ghostty / Warp** | hooks | ✅ verificado |
| **claude.ai en el navegador** | userscript (`Scripts/clawdpet-claude-ai.user.js`) | ⚠️ ver abajo |
| **Claude Desktop** | — | ❌ no hay señal |

La diferencia no es capricho: **Claude Code tiene hooks**, que son una API de verdad
para avisar qué está pasando. Las otras dos no tienen nada equivalente.

### El navegador

`Scripts/clawdpet-claude-ai.user.js`, para Tampermonkey o Violentmonkey. Mira el DOM de
claude.ai y avisa cuando aparece o desaparece el botón de detener.

Va por `GET` con todo en el query string, a propósito: en modo `no-cors` sólo se pueden
mandar Content-Types simples, así que un `POST` con `application/json` dispararía
preflight y quedaría bloqueado. Mixed content no molesta porque `127.0.0.1` cuenta como
origen seguro. Y no manda `app`: sin PID ni identificador, Claw'd Pet usa la app que
está al frente — o sea el navegador — así que anda igual en Chrome, Safari o Arc.

Lo verificado es el mecanismo (el aviso llega y la mascota camina hasta el ícono del
navegador). Lo que **no** está verificado son los selectores del DOM de claude.ai: si
cambian, dejá de detectar. Para eso el script trae `__clawdpet.debug()` en la consola,
que lista lo que encuentra.

### Claude Desktop

No hay forma confiable, y conviene decirlo derecho en vez de improvisar algo frágil:

- **No tiene hooks.**
- **No expone su interfaz por Accessibility.** Su ventana entera es
  `AXWindow → AXGroup → tres AXButton sin título`. Nada de texto, nada de estado.
- **Sus logs no sirven.** `~/Library/Logs/Claude/claude.ai-web.log` sólo tiene warnings
  de la interfaz; no registra cuándo empieza ni termina un mensaje.

Lo que sí funciona con Claude Desktop es lo inverso: la mascota puede **señalarla** (es
una app como cualquier otra) y el campo de texto puede **escribirle**
(Preferencias ▸ General ▸ Qué hace con tu pregunta).

## Conectarla con Claude Code

**Preferencias ▸ Integración ▸ Conectar ahora.** Eso hace tres cosas:

1. Symlinkea `clawdpet` y `clawdpet-hook` en `~/.local/bin` (sin sudo).
2. Guarda un backup de `~/.claude/settings.json`.
3. Escribe los hooks, **conservando los tuyos**: sólo reemplaza entradas cuyo comando
   contenga `clawdpet-hook`; cualquier otro hook que tengas queda intacto.

Los hooks que enchufa:

| Evento de Claude Code | Comando | Efecto |
|---|---|---|
| `UserPromptSubmit` | `clawdpet-hook thinking` | burbuja de "…" |
| `PermissionRequest` | `clawdpet-hook needs_action 'Necesito tu OK'` | salta pidiendo atención |
| `Notification` | `clawdpet-hook needs_action 'Necesito tu OK'` | otros avisos |
| `PostToolUse` | `clawdpet-hook thinking` | respondiste, sigue trabajando |
| `Stop` | `clawdpet-hook needs_action` | terminó de responder, va hasta la app y espera tu click |

Abrí una sesión nueva de Claude Code para que los tome.

### Qué evento usar para qué (esto es fácil de equivocar)

La secuencia real de Claude Code para una herramienta que pide permiso es:

```
UserPromptSubmit → PreToolUse → [aparece el prompt] → PermissionRequest
                 → [respondés] → PostToolUse → … → Stop
```

- **`PreToolUse` corre ANTES de que aparezca el prompt**, no después de que respondas.
  Usarlo para salir del estado de alerta no sirve: mientras esperás no vuelve a
  dispararse, y la mascota se quedaría saltando hasta el `Stop` del final del turno.
  Por eso no lo usamos.
- **`PermissionRequest` es el prompt mismo**: es lo que hace que el aviso salga en el
  instante exacto en que Claude te pide algo, sin demora. `Notification` es genérico y
  llega más tarde; lo dejamos igual porque cubre otros casos.
- **`PostToolUse` corre justo después de que respondés** y la herramienta termina: ese
  es el que saca a la mascota del salto.
- **`Stop` también manda `needs_action`**: cuando Claude termina de responder la
  mascota va hasta la app igual que cuando pide permiso, en vez de volver directamente
  a pasearse sin avisar. Se saca del salto igual que cualquier otro `needs_action`:
  clickeándola o volviendo vos mismo a esa app.

### `@Published` publica en `willSet`

Vale la pena tenerlo presente porque produce bugs silenciosos: cuando un sink de
`store.$config` recibe el valor nuevo, `store.config` **todavía tiene el viejo**. Con
eso, un `guard store.config.enabled else { return }` adentro de `show()` hacía que la
mascota se escondiera y no volviera nunca: al prenderla, el sink recibía `true` pero la
config aún leía `false`.

Los sinks de config van todos con `.receive(on: RunLoop.main)`, que difiere un turno de
runloop y garantiza leer el valor ya guardado.

### El destino tiene que ser alcanzable

Los límites del paseo se recalculan seguido, porque el Dock se mide en vivo y su ancho
cambia al abrir o cerrar apps. Si el destino queda fuera de los límites nuevos, el clamp
frena a la mascota antes de llegar y **nunca "llega"**: se queda caminando en el lugar,
que es lo que se veía como saltitos contra el borde. Cada tick recorta el destino a los
límites vigentes para que siempre sea alcanzable.

### Tres redes para que no se quede trabada

1. `PostToolUse` la saca del salto en cuanto respondés.
2. Si **vos** traés al frente la app que estaba reclamando, se calma sola
   (`NSWorkspace.didActivateApplicationNotification`). Cubre aprobar desde la terminal
   sin tocar la mascota, y también si algún hook no llegó a dispararse.
3. Cada hook arranca su propio proceso, así que dos eventos consecutivos pueden llegar
   **desordenados** por milisegundos. Un `thinking` atrasado que pisara un aviso recién
   llegado te haría perder el pedido entero, así que durante 1,2 s el aviso gana
   (`PetController.attentionGraceWindow`). Perder un aviso es peor que atrasarlo.

### No hay apps que configurar

### La burbuja dice QUÉ te está pidiendo

Claude Code le pasa a cada hook un JSON por stdin con el detalle del evento: el texto de
la notificación, o qué herramienta quiere correr y con qué argumentos. El hook lo
reenvía **tal cual** como cuerpo del POST y manda `state` y `pid` por query string, así
no hay que escapar ni parsear nada en bash (nada de `jq`, nada de `python`). Del lado de
Swift se arma el mensaje:

| Evento | Qué muestra |
|---|---|
| `Notification` | el texto que ya redactó Claude Code |
| `PermissionRequest` de `Bash` | la `description` del comando, o el comando |
| `PermissionRequest` de `Edit`/`Write`/`Read` | `Edit · README.md` |
| cualquier otro | el nombre de la herramienta |

Sin esto la burbuja sólo podía decir "Necesito tu OK", que no te dice para qué.

El hook manda su propio PID (`$$`) y Claw'd Pet **sube por el árbol de procesos** hasta
encontrar la app dueña:

```
clawdpet-hook (pid 4711)
  └─ claude          (pid 4390)
       └─ zsh        (pid 4102)
            └─ Code Helper
                 └─ Visual Studio Code   ← esta
```

Así funciona igual desde Terminal, iTerm, Ghostty, Warp o la terminal integrada de VS
Code, sin listas de bundle identifiers ni configuración. Ver `ProcessTree` y
`AppResolver`. Si querés forzar otra app, `--app` sigue existiendo y acepta un alias
(`vscode`), un bundle id o un nombre visible (`"Visual Studio Code"`).

## El endpoint y el CLI

`POST http://127.0.0.1:8787/notify`

```json
{ "state": "needs_action", "message": "Necesito tu OK", "pid": 4711, "duration": 10 }
```

| Campo | Valores |
|---|---|
| `state` | `idle` · `thinking` · `needs_action` (obligatorio) |
| `pid` | PID de quien avisa; con esto se detecta la app sola |
| `app` | fallback: alias, bundle id o nombre visible |
| `message` | texto corto para la burbuja |
| `duration` | segundos del mensaje; default: el de Preferencias |

También responde `GET /health` (incluye si Accesibilidad está concedida) y acepta
`GET /notify?state=thinking` para un curl de una línea.

El listener se bindea explícitamente a `127.0.0.1` (`NWParameters.requiredLocalEndpoint`)
y además rechaza conexiones cuyo endpoint remoto no sea loopback.

```bash
clawdpet notify --state needs_action --message "Build falló"
clawdpet thinking
clawdpet done "Terminó la tarea"
clawdpet ping                      # ¿está viva? ¿tiene permisos?
```

Ejemplo en `.vscode/tasks.json`:

```json
{
  "label": "build + avisar",
  "type": "shell",
  "command": "npm run build || clawdpet notify --state needs_action --message 'Build falló'"
}
```

## La barra de menú

El ícono de Claw'd vive ahí siempre (la app es `LSUIElement`, no aparece en el Dock).

- **Click izquierdo**: prende y apaga la mascota. Cuando está apagada el ícono se ve
  atenuado.
- **Click derecho** (o ⌃-click): Preferencias y Salir. Nada más.

No hay forma de forzar el estado a mano, y es a propósito: la mascota refleja lo que
hace el agente. Un control para ponerla en "pensando" cuando nadie está pensando sólo
genera desconfianza en lo que muestra.

Para que esté siempre, activá **Preferencias ▸ General ▸ Abrir al iniciar sesión**
(necesita que la app esté en `/Applications`).

> Nota de implementación: no se le asigna `menu` al `NSStatusItem`. Si se le asigna,
> AppKit se queda con todos los clicks y no hay forma de distinguir izquierdo de
> derecho; manejamos el click nosotros y desplegamos el menú a mano.

## Preferencias

Desde el menú del ícono de la barra.

- **General** — mostrar/ocultar, sonido, abrir al iniciar sesión, **tema (naranja /
  oscuro / claro)** con preview de los tres estados, tamaño, velocidad, altura,
  duración del mensaje, «no pasarse del Dock», «click abre el campo de texto», y
  botones para probar cada estado.
- **Integración** — estado y puerto del servidor, botón «Conectar ahora», snippets.
- **Permisos** — estado de Accesibilidad, con la explicación de por qué a veces
  aparece en rojo aunque ya lo hayas dado, y un botón para reiniciar la app.

Se guarda en `~/Library/Application Support/ClawdPet/config.json`.

**Abrir al iniciar sesión** usa `SMAppService.mainApp`: falla si la app corre desde
DerivedData, así que copiá `ClawdPet.app` a `/Applications` primero.

## Decisiones técnicas

### Nivel de ventana (por encima del Dock)

El Dock vive en `kCGDockWindowLevel` (= 20). Elegimos **`.statusBar` (25)**:

| Nivel | raw | ¿arriba del Dock? | Costo |
|---|---|---|---|
| `.floating` | 3 | no | — |
| `.mainMenu` | 24 | sí | tapa la barra de menú |
| **`.statusBar`** | **25** | **sí** | **ninguno relevante** |
| `.popUpMenu` | 101 | sí | tapa menús contextuales |
| `.screenSaver` | 1000 | sí | tapa TODO, incluidos modales y Spotlight |

`.statusBar` es el nivel público más bajo que queda arriba del Dock, y sigue estando
por debajo de `.popUpMenu`, así que los menús contextuales, Spotlight y las hojas del
sistema se dibujan **sobre** la mascota en vez de quedar tapados. Se cambia en un solo
lugar: `PetPanel.preferredLevel`.

### Ventana-franja, no ventanita que se mueve

La ventana ocupa todo el ancho de la pantalla en una franja de abajo, y la mascota se
mueve *adentro* con SwiftUI: así la animación no requiere mover un `NSWindow` 60 veces
por segundo. El costo es que la franja taparía los clicks al Dock, así que
`ignoresMouseEvents` arranca en `true` y se apaga sólo cuando el cursor está sobre la
mascota, la burbuja o el campo de texto — el rectángulo lo reporta la propia vista con
un `PreferenceKey`, porque cambia de tamaño según el contenido.

### El ancho real del Dock

`NSScreen.visibleFrame` da la **altura** del Dock pero no su ancho, y la ventana del
Dock en `CGWindowList` mide toda la pantalla. La única forma de saber dónde empieza y
termina la tira es la Accessibility API sobre `com.apple.dock`: el primer hijo es un
`AXList` con los íconos (`DockLocator`, con caché de 2 s porque recorrerlo en cada
frame sería carísimo).

Ojo con qué rectángulo se usa: el frame del `AXList` incluye el padding del contenedor
redondeado, así que quedarse con él deja a la mascota caminando sobre la curva del
borde. Usamos la **unión de los frames de los íconos**, que es literalmente dónde están,
y le restamos medio sprite para que el cuerpo entero quede adentro.

`clawdpet ping` imprime la tira detectada, para verificarlo de un vistazo.

Sin permiso de Accesibilidad devuelve `nil` y la mascota camina por todo el ancho de la
pantalla — se puede apagar con «no pasarse del Dock».

### El campo de texto y el foco

El panel es `.nonactivatingPanel` y normalmente `canBecomeKey` es `false`, así que
nunca te roba el foco. Mientras el campo está abierto lo activamos temporalmente: al
ser *nonactivating*, recibe el teclado **sin** activar la app ni sacarle el foco a tu
editor (el mismo truco que usa Spotlight).

### Responder en la burbuja

Por defecto el campo de texto corre **`claude -p` con el modelo haiku** y muestra la
respuesta arriba de la cabeza. Elegimos el CLI de Claude Code en vez de la API HTTP por
dos razones: no necesita API key (reusa la sesión que ya tenés autenticada) y no
necesita ningún permiso del sistema.

Dos detalles del subproceso:

- una app GUI **no hereda tu `PATH`**, así que `ClaudeCLIBridge` busca el binario a mano
  en los lugares donde se instala Claude Code y le arma un `PATH` razonable al hijo;
- leemos los pipes **antes** de esperar al proceso: si el buffer se llena, el hijo se
  bloquea escribiendo y nunca termina.

La respuesta se aplana a una línea y se corta a 240 caracteres — la burbuja es una
burbuja, no un chat. Mientras espera, la mascota se queda "pensando" con los puntitos.

La alternativa (**Preferencias ▸ General ▸ Qué hace con tu pregunta ▸ Mandar a Claude
Desktop**) copia al portapapeles, trae Claude Desktop al frente, espera a que sea
efectivamente la frontmost y simula ⌘V + ⏎ con `CGEvent`, restaurando el portapapeles
después. Esa sí necesita Accesibilidad; sin el permiso el texto queda copiado y la
burbuja lo dice en vez de fallar en silencio.

### Pixel-art

Grilla 16×16 declarada como strings en `ClawdSprite.bodyRows`, dibujada con `Canvas` +
rectángulos sólidos — sin bitmaps ni interpolación. Las patas se dibujan por código
para animarlas (ciclo de 4 frames + pose quieta).

Tres detalles que importan para que se vea "pixel" y no borroso:

- el rebote de la caminata es **entero** (0 o 1 píxel de grid): con offsets
  fraccionarios cada fila se antialiasea contra la de al lado y aparecen costuras
  horizontales en el cuerpo;
- la posición del sprite se redondea a punto entero antes de dibujar;
- **el alto de la ventana-franja también se redondea**. Este es el sutil: la posición
  del sprite se calcula desde el borde de abajo, así que si la franja mide 228,4 pt de
  alto el sprite termina dibujado en medio píxel y se ve borroso y torcido aunque su
  posición interna sea entera. Con `floorY`, `stripHeight` y `spriteSide` enteros, la
  posición final en pantalla cae siempre en un punto entero.

Todo el color sale de `ClawdTint.tint(theme:state:)`: los tres temas y los estados
viven en una sola función.

### Watchdog del estado "pensando"

Si un hook manda `thinking` y nunca llega el `idle` (se cortó la sesión, cerraste la
terminal), la mascota vuelve sola a idle después de 15 minutos
(`PetController.thinkingTimeout`).

## Permiso de Accesibilidad

Se usa para tres cosas: ubicar la ventana de la app que te reclama, medir el ancho del
Dock, y escribir en Claude Desktop. No lee contenido de ventanas.

El permiso se le da a **una copia concreta** de la app, identificada por su firma.
*Preferencias ▸ Permisos* muestra la ruta de la copia que está corriendo: esa es la que
tiene que estar autorizada. Si concediste el permiso a otra (la de DerivedData, o una
build anterior), esta no lo hereda.

Si ya lo diste y la app lo sigue viendo en rojo, es una de estas dos:

- **La firma cambió.** macOS asocia el permiso a la firma del binario, no a su ruta.
  Cada recompilación cambia la firma ad-hoc y el permiso deja de aplicar aunque el
  switch siga encendido. Solución: quitarlo con «−» y volver a agregarlo con «+».
- **`AXIsProcessTrusted()` está cacheado en el proceso.** Si concediste el permiso con
  la app ya abierta, hay que reiniciarla — hay un botón para eso en *Preferencias ▸
  Permisos*.

### Que el permiso deje de romperse en cada build

Una firma ad-hoc produce un requisito designado que es un hash desnudo del binario:

```
designated => cdhash H"ddc3844057e51075084af91a04a75b637e2016a8"
```

macOS guarda **ese** requisito cuando le das el permiso. Cambiás una línea, recompilás,
el hash cambia — y el permiso deja de aplicar aunque el switch siga encendido. Es la
causa de casi todos los «ya se lo di y sigue sin andar».

```bash
./Scripts/setup-signing.sh
```

Genera un certificado auto-firmado, lo importa a tu llavero y lo marca como confiable
para firmar código (macOS te va a pedir la contraseña en ese último paso: es para tocar
los ajustes de confianza del llavero). A partir de ahí el requisito pasa a ser:

```
designated => identifier "com.clawdpet.ClawdPet" and certificate leaf = H"…"
```

…que sobrevive a las recompilaciones. `build-without-xcode.sh` y `release.sh` detectan
la identidad solos; en Xcode es *Signing & Capabilities ▸ Manual ▸ ClawdPet Dev*.

Después de eso, concedé el permiso una vez más (la firma cambió) y ya no hace falta
volver a hacerlo.

### Si la app no aparece en la lista de Accesibilidad

macOS muestra el diálogo de permiso **una sola vez por identidad**; si ya lo
descartaste, no vuelve a aparecer y agregar la app a mano con «+» no siempre funciona
para apps *accessory*. Para volver a empezar de cero, sin tocar los permisos de ninguna
otra app:

```bash
tccutil reset Accessibility com.clawdpet.ClawdPet
open /Applications/ClawdPet.app
```

Al arrancar sin permiso, la app dispara el diálogo del sistema sola — y ese diálogo es
lo que la registra en la lista.

## Debug

```bash
clawdpet ping        # servidor, permiso, tira del Dock y qué está haciendo la mascota
curl -s http://127.0.0.1:8787/dock-debug   # ítems del Dock con identifier y posición
curl -s "http://127.0.0.1:8787/ax-debug?app=com.anthropic.claudefordesktop"
```

`ax-debug` vuelca el árbol de Accesibilidad de una app: sirve para averiguar si expone
alguna señal con la que engancharse. Ojo que eso incluye texto de la interfaz de esa
app, servido por HTTP local — es una herramienta de diagnóstico, no algo que quieras
dejando corriendo si te importa ese detalle.

> Corré la app con `open`, no invocando el binario directo. Al lanzarla desde una shell,
> macOS le atribuye los permisos al **proceso responsable** (la terminal que la lanzó) en
> vez de a la app, y `AXIsProcessTrusted()` devuelve `false` aunque el permiso esté dado.

`ping` imprime algo así, que es lo que uso para diagnosticar sin adivinar por
screenshots:

```
mascota: idle x=574 destino=130 límites=130…1340
mascota: needsAction x=750 destino=750 límites=36…1434 app=Code(ícono-dock) rebotando
```

Y para probar la UI sin buscar el ícono en la barra de menú:

```bash
APP=/Applications/ClawdPet.app/Contents/MacOS/ClawdPet
CLAWDPET_SHOW_PREFS=1     $APP   # abre Preferencias al arrancar
CLAWDPET_OPEN_PROMPT=1    $APP   # abre el campo de texto
CLAWDPET_TEST_ASK="hola"  $APP   # manda esa pregunta como si la hubieras escrito
```

Corriendo el binario directo (en vez de `open`) los `NSLog` salen por stderr.

## Limitaciones conocidas

- Una sola pantalla a la vez: la mascota vive en la pantalla donde está el mouse al
  momento de recalcular la geometría (cada 1,5 s y ante cambios de pantalla).
- Con el Dock a los costados o auto-oculto no hay altura de Dock que medir y la mascota
  camina sobre el borde inferior. Se compensa con el slider **Altura**.
- El binario `clawdpet` va embebido en `Contents/Resources/`. Alcanza para uso local y
  para distribuir ad-hoc; para notarizar conviene moverlo a un helper bundle firmado
  aparte.
