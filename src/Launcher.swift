import Cocoa
import CryptoKit
import UniformTypeIdentifiers

enum VendorPackage {
    static let filename = "tubitak-esign-1.21.0.jar"
    static let checksum = "416f247a015e30e05d156b04382b7c56f03bc4459c68b45442370ac4dc769391"
    static let source = URL(string: "https://e-imza.tubitak.gov.tr/sublimity-ess/jnlp/sublimity-esign-client-swingui-1.21.0-SNAPSHOT-jar-with-dependencies.jar")!

    static func verify(_ file: URL, checksum expected: String = checksum) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue <= 100 * 1024 * 1024 else {
            throw failure("The signing package is not a regular file of the expected size.")
        }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == expected else {
            throw failure("The downloaded package failed its integrity check. Check for a helper update; this package was not run.")
        }
    }

    static func failure(_ message: String) -> NSError {
        NSError(domain: "TubitakSigningHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func prepare(at destination: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try verify(destination)
                    completion(.success(destination))
                    return
                }
                let buildCache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("TubitakSigningHelper/" + filename)
                if FileManager.default.fileExists(atPath: buildCache.path) {
                    try verify(buildCache)
                    try FileManager.default.copyItem(at: buildCache, to: destination)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
                    completion(.success(destination))
                    return
                }
                download(from: source, checksum: checksum, to: destination, completion: completion)
            } catch { completion(.failure(error)) }
        }
    }

    static func download(from source: URL, checksum: String, to destination: URL,
                         completion: @escaping (Result<URL, Error>) -> Void) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 600
        let session = URLSession(configuration: configuration)
        session.downloadTask(with: source) { temporary, response, error in
            defer { session.finishTasksAndInvalidate() }
            do {
                if let error = error { throw error }
                guard let temporary = temporary, let response = response as? HTTPURLResponse,
                      response.statusCode == 200, response.url?.scheme == "https",
                      response.url?.host == source.host else {
                    throw failure("TÜBİTAK did not return the expected signing package. Please try again later.")
                }
                try verify(temporary, checksum: checksum)
                try FileManager.default.moveItem(at: temporary, to: destination)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
                completion(.success(destination))
            } catch { completion(.failure(error)) }
        }.resume()
    }
}

enum AkisDriver {
    static let supportURL = URL(string: "https://akiskart.bilgem.tubitak.gov.tr/en/support/")!
    static let source = URL(string: "https://akiskart.bilgem.tubitak.gov.tr/wp-content/uploads/sites/33/2026/11/Akia_macos_arm_6.8.13.pkg_.zip")!
    static let archiveChecksum = "d35cbe5498650722ec17f4f2696ce03436b9d364eff00e69ae6fb6667fde7d3a"
    static let packageChecksum = "af6b01c79d55808081fab148ab1f6a41bf7bcda2ef406d1070b72116180e2265"
    static let packageName = "Akia_6.8.13_arm64.pkg"

    static var installed: Bool {
        supportsArm64(URL(fileURLWithPath: "/usr/local/lib/libakisp11.dylib"))
    }

    static func supportsArm64(_ file: URL) -> Bool {
        // Read the Mach-O architecture table directly: end users don't need Xcode's lipo tool.
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4096), data.count >= 8 else { return false }
        func word(_ offset: Int, little: Bool) -> UInt32 {
            let bytes = Array(data[offset..<(offset + 4)])
            return (0..<4).reduce(UInt32(0)) { value, i in
                value | UInt32(bytes[i]) << UInt32((little ? i : 3 - i) * 8)
            }
        }
        let magic = Array(data.prefix(4))
        if magic == [0xcf, 0xfa, 0xed, 0xfe] { return word(4, little: true) == 0x0100000c }
        if magic == [0xfe, 0xed, 0xfa, 0xcf] { return word(4, little: false) == 0x0100000c }
        let little: Bool
        let stride: Int
        switch magic {
        case [0xca, 0xfe, 0xba, 0xbe]: little = false; stride = 20
        case [0xbe, 0xba, 0xfe, 0xca]: little = true; stride = 20
        case [0xca, 0xfe, 0xba, 0xbf]: little = false; stride = 32
        case [0xbf, 0xba, 0xfe, 0xca]: little = true; stride = 32
        default: return false
        }
        let count = Int(word(4, little: little))
        guard count > 0, count <= 64, 8 + count * stride <= data.count else { return false }
        return (0..<count).contains { word(8 + $0 * stride, little: little) == 0x0100000c }
    }

    static func unpack(_ archive: URL, to package: URL) throws {
        try VendorPackage.verify(archive, checksum: archiveChecksum)
        FileManager.default.createFile(atPath: package.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let output = try FileHandle(forWritingTo: package)
        defer { try? output.close() }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        // Extract only the reviewed file, never archive paths or installation scripts.
        p.arguments = ["-p", archive.path, packageName]
        p.standardOutput = output
        p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw VendorPackage.failure("Could not open the AKİS download.") }
        try VendorPackage.verify(package, checksum: packageChecksum)
        let signature = Process()
        signature.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        signature.arguments = ["--check-signature", package.path]
        signature.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        let details = Pipe()
        signature.standardOutput = details
        signature.standardError = FileHandle.nullDevice
        try signature.run()
        let text = String(data: details.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        signature.waitUntilExit()
        guard signature.terminationStatus == 0, text.contains("(7ZWFF63P66)") else {
            throw VendorPackage.failure("The AKİS installer could not be verified as a TÜBİTAK package. It was not opened.")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let status = NSTextField(wrappingLabelWithString: "Ready to open a TÜBİTAK signing request.")
    private var signingProcess: Process?
    private var pending: [String] = []
    private var ready = false
    private var cardCheck: Process?
    private var preparingVendor = false
    private var preparingDriver = false
    private let driverStatus = NSTextField(labelWithString: "")
    private lazy var driverButton = NSButton(title: "Install AKİS driver…", target: self, action: #selector(setupDriver))

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

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 390),
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
        driverStatus.font = .systemFont(ofSize: 12)
        driverStatus.textColor = .secondaryLabelColor
        driverButton.bezelStyle = .rounded
        let driverRow = NSStackView(views: [driverStatus, driverButton])
        driverRow.orientation = .horizontal
        driverRow.spacing = 12
        let footnote = NSTextField(wrappingLabelWithString:
            "Java is included. TÜBİTAK’s original signing application is downloaded and verified on first use. An AKİS card driver is required. This helper is unofficial.")
        footnote.font = .systemFont(ofSize: 11)
        footnote.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, description, buttons, driverRow, status, footnote])
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
        refreshDriver()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let first = pending.first { pending.removeAll(); launch(first) }
    }

    func applicationDidBecomeActive(_ notification: Notification) { if ready { refreshDriver() } }

    private func refreshDriver() {
        let installed = AkisDriver.installed
        driverStatus.stringValue = installed ? "AKİS ARM driver detected" : "AKİS ARM driver needed for AKİS cards"
        driverButton.title = installed ? "AKİS support…" : "Install AKİS driver…"
        driverButton.isEnabled = !preparingDriver
    }

    @objc private func setupDriver() {
        if AkisDriver.installed { NSWorkspace.shared.open(AkisDriver.supportURL); return }
        guard !preparingDriver, !preparingVendor, signingProcess?.isRunning != true, cardCheck?.isRunning != true else {
            status.stringValue = "Finish the current signing window, download or card check first."
            return
        }
        let alert = NSAlert()
        alert.messageText = "Install the official AKİS ARM driver?"
        alert.informativeText = "Download AKİA 6.8.13 directly from TÜBİTAK BİLGEM and open Apple’s Installer. macOS will ask for administrator approval. If AKİA 6.7.6 or earlier is installed, follow TÜBİTAK’s removal instructions first."
        alert.addButton(withTitle: "Download and open Installer")
        alert.addButton(withTitle: "Official instructions")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if response == .alertSecondButtonReturn { NSWorkspace.shared.open(AkisDriver.supportURL); return }
        guard response == .alertFirstButtonReturn else { return }
        do { try prepareSupport() } catch { status.stringValue = error.localizedDescription; return }
        preparingDriver = true
        refreshDriver()
        status.stringValue = "Downloading the official AKİS ARM driver…"
        let directory = support.appendingPathComponent("Driver", isDirectory: true)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                let archive = directory.appendingPathComponent(UUID().uuidString + ".zip")
                VendorPackage.download(from: AkisDriver.source, checksum: AkisDriver.archiveChecksum, to: archive) { result in
                    do {
                        let downloaded = try result.get()
                        defer { try? FileManager.default.removeItem(at: downloaded) }
                        let package = directory.appendingPathComponent("Akia_macos_arm_6.8.13.pkg")
                        try AkisDriver.unpack(downloaded, to: package)
                        DispatchQueue.main.async {
                            self?.preparingDriver = false
                            self?.refreshDriver()
                            if NSWorkspace.shared.open(package) {
                                self?.status.stringValue = "Complete the AKİS installation, then return here and check your USB card."
                            } else { self?.status.stringValue = "Could not open Apple’s Installer. Visit AKİS support for installation instructions." }
                        }
                    } catch { self?.driverFailed(error) }
                }
            } catch { self?.driverFailed(error) }
        }
    }

    private func driverFailed(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.preparingDriver = false
            self?.refreshDriver()
            self?.status.stringValue = "AKİS setup: \(error.localizedDescription) Use AKİS support if the download is unavailable."
        }
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
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            .credits: NSAttributedString(string: "Unofficial macOS helper. Includes Amazon Corretto 8; downloads the unchanged signing application directly from TÜBİTAK.")
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

    private func process(_ arguments: [String], jar: URL) -> Process {
        let p = Process()
        p.executableURL = java
        p.arguments = ["-Xmx512m", "-Xdock:name=TUBITAK E-Imza",
            "-Djava.library.path=/usr/local/lib", "-cp",
            resources.appendingPathComponent("Java").path + ":" +
            jar.path,
            "TubitakJnlpLauncher"] + arguments
        p.currentDirectoryURL = support
        return p
    }

    private func prepareSupport() throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: support.path)
        try FileManager.default.createDirectory(at: support.appendingPathComponent("Java"),
                                               withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
    }

    private func withSigningPackage(_ completion: @escaping (URL) -> Void) {
        do { try prepareSupport() } catch {
            status.stringValue = "Could not prepare the signing application: \(error.localizedDescription)"
            return
        }
        preparingVendor = true
        status.stringValue = "Preparing TÜBİTAK’s signing application. A first-use download may take a few minutes…"
        let destination = support.appendingPathComponent("Java/" + VendorPackage.filename)
        VendorPackage.prepare(at: destination) { [weak self] result in
            DispatchQueue.main.async {
                self?.preparingVendor = false
                switch result {
                case .success(let jar): completion(jar)
                case .failure(let error): self?.status.stringValue = error.localizedDescription
                }
            }
        }
    }

    private func launch(_ path: String) {
        if signingProcess?.isRunning == true || cardCheck?.isRunning == true || preparingVendor || preparingDriver {
            status.stringValue = "Finish the current signing window, download or card check first."
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard URL(fileURLWithPath: path).pathExtension.lowercased() == "jnlp" else {
            status.stringValue = "Choose a .jnlp file downloaded from TÜBİTAK."
            return
        }
        withSigningPackage { [weak self] jar in self?.startSigning(path, jar: jar) }
    }

    private func startSigning(_ path: String, jar: URL) {
        do {
            try prepareSupport()
            let log = support.appendingPathComponent("signing.log")
            FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let handle = try FileHandle(forWritingTo: log)
            let p = process([path], jar: jar)
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
        guard signingProcess?.isRunning != true, cardCheck?.isRunning != true, !preparingVendor, !preparingDriver else {
            status.stringValue = "Finish the current signing window, download or card check first."
            return
        }
        withSigningPackage { [weak self] jar in self?.startUSBCheck(jar: jar) }
    }

    private func startUSBCheck(jar: URL) {
        do {
            try prepareSupport()
            let p = process(["--check-card"], jar: jar)
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

if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--verify-driver" {
    do {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        try AkisDriver.unpack(URL(fileURLWithPath: CommandLine.arguments[2]), to: directory.appendingPathComponent("AKIS.pkg"))
        print("DRIVER_PACKAGE_VERIFIED")
    } catch { fputs("Driver verification failed: \(error.localizedDescription)\n", stderr); exit(1) }
} else if (2...3).contains(CommandLine.arguments.count) && CommandLine.arguments[1] == "--driver-status" {
    let installed = CommandLine.arguments.count == 3
        ? AkisDriver.supportsArm64(URL(fileURLWithPath: CommandLine.arguments[2])) : AkisDriver.installed
    print(installed ? "AKIS_ARM_DRIVER_DETECTED" : "AKIS_ARM_DRIVER_MISSING")
    exit(installed ? 0 : 2)
} else if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--verify-vendor" {
    do {
        try VendorPackage.verify(URL(fileURLWithPath: CommandLine.arguments[2]))
        print("VENDOR_PACKAGE_VERIFIED")
    } catch { fputs("Vendor verification failed: \(error.localizedDescription)\n", stderr); exit(1) }
} else {
    let delegate = AppDelegate()
    let application = NSApplication.shared
    application.setActivationPolicy(.regular)
    application.delegate = delegate
    application.run()
}
