// ==UserScript==
// @name         Claw'd Pet — claude.ai
// @namespace    https://github.com/juanigomez/claude-pet
// @version      1.0
// @description  Hace que la mascota refleje lo que pasa en claude.ai en el navegador
// @match        https://claude.ai/*
// @run-at       document-idle
// @grant        none
// ==/UserScript==

/*
 * Por qué esto existe
 * -------------------
 * Claude Code tiene hooks: una API de verdad para avisar qué está pasando. Claude
 * Desktop y el navegador no tienen nada equivalente, y su contenido tampoco llega a la
 * Accessibility API de macOS (lo comprobamos: la ventana de Claude Desktop expone tres
 * botones sin título y nada más). Dentro del navegador, en cambio, sí se puede mirar
 * el DOM — y para eso hace falta un userscript.
 *
 * Instalación: pegalo en Tampermonkey o Violentmonkey y recargá claude.ai.
 *
 * Cómo detecta el estado
 * ----------------------
 * Mientras Claude genera, la interfaz muestra un botón de detener. No nos atamos a una
 * clase CSS concreta (cambian seguido): buscamos por rol y etiqueta accesible, que es
 * lo más estable, y probamos varias formas. Si claude.ai cambia y deja de andar,
 * abrí la consola y corré `__clawdpet.debug()` para ver qué encuentra.
 */

(function () {
  'use strict';

  const PORT = 8787;
  const ENDPOINT = `http://127.0.0.1:${PORT}/notify`;

  // Varias formas de encontrar el botón de "detener". La primera que exista, gana.
  const STOP_SELECTORS = [
    'button[aria-label*="Stop" i]',
    'button[aria-label*="detener" i]',
    'button[data-testid*="stop" i]',
    '[role="button"][aria-label*="Stop" i]'
  ];

  function findStopButton() {
    for (const selector of STOP_SELECTORS) {
      const el = document.querySelector(selector);
      if (el && el.offsetParent !== null) return el;
    }
    return null;
  }

  let lastState = null;
  let debounce = null;

  function send(state, message) {
    if (state === lastState) return;
    lastState = state;

    // Todo por query string, en un GET simple:
    //  - `no-cors` sólo deja mandar Content-Type "simple", así que un POST con
    //    application/json se convertiría en preflight y quedaría bloqueado;
    //  - un GET sin headers propios no dispara preflight ni necesita CORS.
    // Mixed content no es problema: 127.0.0.1 cuenta como origen seguro.
    //
    // No mandamos `app`: sin PID ni identificador, Claw'd Pet usa la app que está al
    // frente, que es justamente el navegador desde donde salió esto. Así funciona
    // igual en Chrome, Safari, Arc o el que uses.
    const params = new URLSearchParams({ state });
    if (message) params.set('message', message);

    fetch(`${ENDPOINT}?${params}`, { mode: 'no-cors', keepalive: true }).catch(() => {
      /* La app no está abierta. No es un error: seguimos como si nada. */
    });
  }

  function evaluate() {
    clearTimeout(debounce);
    // Un respiro: durante el render la interfaz parpadea y mandaríamos ruido.
    debounce = setTimeout(() => {
      send(findStopButton() ? 'thinking' : 'idle');
    }, 250);
  }

  const observer = new MutationObserver(evaluate);
  observer.observe(document.body, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ['aria-label', 'data-testid', 'disabled']
  });

  // Al cerrar la pestaña, que la mascota no quede pensando para siempre.
  window.addEventListener('pagehide', () => send('idle'));

  evaluate();

  // Ayuda para cuando claude.ai cambie y esto deje de detectar.
  window.__clawdpet = {
    debug() {
      console.log('[clawdpet] estado actual:', lastState);
      console.log('[clawdpet] botón de detener:', findStopButton());
      STOP_SELECTORS.forEach(s =>
        console.log(`[clawdpet]   ${s} →`, document.querySelector(s)));
      console.log('[clawdpet] botones con aria-label:',
        [...document.querySelectorAll('button[aria-label]')]
          .map(b => b.getAttribute('aria-label')));
    },
    send
  };

  console.log('[clawdpet] activo. `__clawdpet.debug()` para diagnosticar.');
})();
