import Cocoa
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let status = NSTextField(wrappingLabelWithString: "Ready to open a TÜBİTAK signing request.")
    private var signingProcess: Process?
    private var pending: [String] = []
    private var ready = false
    private var cardCheck: Process?

    private var resources: URL { Bundle.main.resourceURL! }
    private var java: URL { resources.appendingPathComponent("Runtime/bin/java") }
    private var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TubitakSigningHelper", isDirectory: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appMenu = NSMenuItem()
        let mainMenu = NSMenu()
        let menu = NSMenu()
        menu.addItem(withTitle: "About TÜBİTAK Signing Helper", action: #selector(about), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open JNLP…", action: #selector(openFile), keyEquivalent: "o")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.submenu = menu
        mainMenu.addItem(appMenu)
        NSApp.mainMenu = mainMenu

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 290),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "TÜBİTAK Signing Helper"
        window.center()
        let title = NSTextField(labelWithString: "Open, review and sign")
        title.font = .systemFont(ofSize: 23, weight: .semibold)
        let description = NSTextField(wrappingLabelWithString:
            "Open the .jnlp downloaded from TÜBİTAK. Its signing window will let you review the documents, choose your certificate and enter your USB card PIN.")
        description.font = .systemFont(ofSize: 14)
        let open = NSButton(title: "Open JNLP…", target: self, action: #selector(openFile))
        open.bezelStyle = .rounded
        open.keyEquivalent = "\r"
        let check = NSButton(title: "Check USB card", target: self, action: #selector(checkUSB))
        check.bezelStyle = .rounded
        let buttons = NSStackView(views: [open, check])
        buttons.orientation = .horizontal
        buttons.spacing = 12
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        let footnote = NSTextField(wrappingLabelWithString:
            "Java is included in this app. An AKİS card driver is required. This helper is unofficial; signing uses TÜBİTAK’s original application.")
        footnote.font = .systemFont(ofSize: 11)
        footnote.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, description, buttons, status, footnote])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 17
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 26),
            description.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footnote.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        ready = true
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let first = pending.first { pending.removeAll(); launch(first) }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let first = filenames.first {
            if ready { launch(first) } else { pending = [first] }
        }
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window?.makeKeyAndOrderFront(nil)
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if signingProcess?.isRunning == true {
            let alert = NSAlert()
            alert.messageText = "The signing window is still open"
            alert.informativeText = "Close the signing window before quitting the helper."
            alert.addButton(withTitle: "Keep helper open")
            alert.runModal()
            return .terminateCancel
        }
        return .terminateNow
    }

    @objc private func about() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "TÜBİTAK Signing Helper",
            .applicationVersion: "0.1.0",
            .credits: NSAttributedString(string: "Unofficial macOS helper. Includes Amazon Corretto 8 and the unchanged TÜBİTAK signing application.")
        ])
    }

    @objc private func openFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose a TÜBİTAK JNLP file"
        panel.allowedContentTypes = [UTType(filenameExtension: "jnlp") ?? .xml]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = panel.url { self?.launch(url.path) }
        }
    }

    private func process(_ arguments: [String]) -> Process {
        let p = Process()
        p.executableURL = java
        p.arguments = ["-Xmx512m", "-Xdock:name=TUBITAK E-Imza",
            "-Djava.library.path=/usr/local/lib", "-cp",
            resources.appendingPathComponent("Java").path + ":" +
            resources.appendingPathComponent("Java/tubitak-esign-1.21.0.jar").path,
            "TubitakJnlpLauncher"] + arguments
        p.currentDirectoryURL = support
        return p
    }

    private func prepareSupport() throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
    }

    private func launch(_ path: String) {
        if signingProcess?.isRunning == true || cardCheck?.isRunning == true {
            status.stringValue = "Finish the current signing window or card check first."
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard URL(fileURLWithPath: path).pathExtension.lowercased() == "jnlp" else {
            status.stringValue = "Choose a .jnlp file downloaded from TÜBİTAK."
            return
        }
        do {
            try prepareSupport()
            let log = support.appendingPathComponent("signing.log")
            FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let handle = try FileHandle(forWritingTo: log)
            let p = process([path])
            p.standardOutput = handle
            p.standardError = handle
            p.terminationHandler = { [weak self] process in
                try? handle.close()
                DispatchQueue.main.async {
                    self?.signingProcess = nil
                    if process.terminationStatus == 2 {
                        self?.status.stringValue = "Request unavailable. Download a fresh JNLP from TÜBİTAK."
                    } else if process.terminationStatus == 0 {
                        self?.status.stringValue = "Signing window closed. Check the result on TÜBİTAK."
                    } else {
                        self?.status.stringValue = "The signing client could not open this request. Check the local signing log."
                    }
                    self?.window.makeKeyAndOrderFront(nil)
                }
            }
            signingProcess = p
            try p.run()
            status.stringValue = "Signing window opened. Review the documents before entering your PIN."
        } catch {
            signingProcess = nil
            status.stringValue = "Could not start the bundled signing client: \(error.localizedDescription)"
        }
    }

    @objc private func checkUSB() {
        guard signingProcess?.isRunning != true, cardCheck?.isRunning != true else {
            status.stringValue = "Close the signing window before checking the USB card."
            return
        }
        do {
            try prepareSupport()
            let p = process(["--check-card"])
            let output = Pipe()
            p.standardOutput = output
            p.standardError = FileHandle.nullDevice
            p.terminationHandler = { [weak self] process in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    self?.cardCheck = nil
                    if process.terminationStatus == 0, let line = text.split(separator: "\n").last {
                        let fields = Dictionary(uniqueKeysWithValues: line.split(separator: " ").compactMap { field -> (String, Int)? in
                            let pair = field.split(separator: "=", maxSplits: 1)
                            guard pair.count == 2, let value = Int(pair[1]) else { return nil }
                            return (String(pair[0]), value)
                        })
                        if fields["readers", default: 0] == 0 {
                            self?.status.stringValue = "No USB reader detected. Connect your reader and check again."
                        } else if fields["cards", default: 0] == 0 {
                            self?.status.stringValue = "USB reader detected. Insert your e-signature card."
                        } else if fields["certificates", default: 0] == 0 {
                            self?.status.stringValue = "Card detected, but no signing certificate was found."
                        } else {
                            self?.status.stringValue = "USB card ready. \(fields["certificates", default: 0]) signing certificate(s) found."
                        }
                    } else {
                        self?.status.stringValue = "Could not read the card. Check the AKİS driver and USB connection."
                    }
                }
            }
            cardCheck = p
            try p.run()
            status.stringValue = "Checking the USB reader and signing certificate…"
        } catch {
            cardCheck = nil
            status.stringValue = "Could not run the card check: \(error.localizedDescription)"
        }
    }
}

let delegate = AppDelegate()
let application = NSApplication.shared
application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()
