import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: MainController!
    var splash: SplashWindow?
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        LiveData.shared.start()
        controller = MainController()
        controller.onGaugeClosedWhileHidden = { NSApp.terminate(nil) }
        // Warm up while the splash runs
        DispatchQueue.global().async { _ = Apps.processTable(); _ = Disks.freeSpace() }
        splash = SplashWindow { [weak self] in
            guard let self = self else { return }
            self.splash = nil
            self.controller.showMain()
            self.controller.runScan()
        }
        NSApp.activate(ignoringOtherApps: true)
        splash?.makeKeyAndOrderFront(nil)
        setupStatusItem()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = NSImage(systemSymbolName: "waveform", accessibilityDescription: "AD Audio Optimizer") {
            img.isTemplate = true
            item.button?.image = img
        } else {
            item.button?.title = "AD"
        }
        let m = NSMenu()
        m.addItem(withTitle: "Open AD Audio Optimizer", action: #selector(openMain), keyEquivalent: "").target = self
        m.addItem(withTitle: "Show / hide LIVE OPT gauge", action: #selector(toggleGauge), keyEquivalent: "").target = self
        m.addItem(NSMenuItem.separator())
        m.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = m
        statusItem = item
    }

    @objc func openMain() { controller.showMain() }
    @objc func toggleGauge() { controller.toggleGauge() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.showMain()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { return false }

    func applicationWillTerminate(_ notification: Notification) { controller.settings.save() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)

// Minimal main menu so Cmd+Q and Cmd+W work
let mainMenu = NSMenu()
let appItem = NSMenuItem()
mainMenu.addItem(appItem)
let appMenu = NSMenu()
appMenu.addItem(withTitle: "Quit AD Audio Optimizer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appItem.submenu = appMenu
let winItem = NSMenuItem()
mainMenu.addItem(winItem)
let winMenu = NSMenu(title: "Window")
winMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
winMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
winItem.submenu = winMenu
app.mainMenu = mainMenu

app.run()
