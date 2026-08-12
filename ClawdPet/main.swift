import AppKit

// Entry point explícito.
//
// No usamos `@main` sobre `AppDelegate` ni un `App` de SwiftUI:
//  - `@main` sobre un NSApplicationDelegate delega en `NSApplicationMain()`, que espera
//    encontrar el delegate por el NIB principal / la anotación de `@NSApplicationMain`.
//    Sin eso la app arranca pero `applicationDidFinishLaunching` nunca se dispara.
//  - SwiftUI `App` traería un sistema de escenas que acá no usamos: todas las ventanas
//    son `NSWindow`/`NSPanel` creados a mano para controlar niveles y foco.
//
// El código top-level de `main.swift` corre en el hilo principal, así que
// `assumeIsolated` es seguro: sólo le confirma al compilador lo que ya es cierto.
let application = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
