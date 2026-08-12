#!/bin/bash
# clawdpet-hook — avisa a Claw'd Pet desde un hook de Claude Code (o desde cualquier script).
#
#   clawdpet-hook <state> [mensaje] [app]
#
#   state : thinking | needs_action | idle
#   app   : opcional. Normalmente NO hace falta: mandamos nuestro PID y Claw'd Pet
#           sube por el árbol de procesos hasta la terminal o el editor de donde
#           venimos. Si lo pasás, gana sobre la detección automática.
#
# Claude Code invoca los hooks pasando un JSON por stdin; este script lo ignora
# a propósito para no depender de jq. Nunca falla: si la app no está corriendo,
# sale con 0 para no romper la sesión de Claude Code.

set -u

STATE="${1:-needs_action}"
MESSAGE="${2:-}"
APP="${3:-}"

CONFIG="$HOME/Library/Application Support/ClawdPet/config.json"
PORT="${CLAWDPET_PORT:-}"
if [ -z "$PORT" ] && [ -f "$CONFIG" ]; then
  PORT=$(/usr/bin/sed -n 's/.*"httpPort"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$CONFIG" | head -1)
fi
PORT="${PORT:-8787}"

# Escapado mínimo para URL y JSON, sin dependencias.
escape_url() {
  printf '%s' "$1" | sed -e 's/ /%20/g' -e 's/&/%26/g' -e 's/?/%3F/g' -e 's/#/%23/g'
}

escape_json() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\n'
}

# Claude Code nos pasa por stdin un JSON con el detalle del evento: el texto de la
# notificación, o qué herramienta quiere correr y con qué argumentos. Lo reenviamos
# TAL CUAL como cuerpo del POST y mandamos state/pid por query string, así no hay
# que escapar ni parsear nada acá (nada de jq, nada de python). Claw'd Pet lo
# interpreta del lado de Swift para poder decirte QUÉ te está pidiendo.
BODY=""
if [ ! -t 0 ]; then
  BODY=$(cat)
fi
if [ -z "$BODY" ]; then
  BODY=$(printf '{"message":"%s"}' "$(escape_json "$MESSAGE")")
elif [ -n "$MESSAGE" ]; then
  # Mensaje explícito en la línea de comandos: pisa lo que venga en el JSON.
  BODY=$(printf '{"message":"%s"}' "$(escape_json "$MESSAGE")")
fi

QUERY="state=$(escape_url "$STATE")&pid=$$"
if [ -n "$APP" ]; then
  QUERY="$QUERY&app=$(escape_url "$APP")"
fi

/usr/bin/curl -s -m 2 -X POST "http://127.0.0.1:${PORT}/notify?${QUERY}" \
  -H 'Content-Type: application/json' \
  --data-binary "$BODY" >/dev/null 2>&1

exit 0
