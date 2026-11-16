# TÜBİTAK E-İmza — macOS Apple Silicon

A macOS helper that opens TÜBİTAK's `.jnlp` signing requests in its original signing application, with **ARM64 Java 8 included inside the app**. Select the documents, choose your certificate, and enter your USB card PIN in the TÜBİTAK signing window.

This is an **unofficial community project**, independent of TÜBİTAK and Kamu SM. It does not modify TÜBİTAK's signing algorithms or original signed JAR. The repository contains the launcher, installer, and build scripts; the official application and Java runtime are downloaded from their publishers when you build it.

## Requirements

- An Apple Silicon Mac with macOS 13 or later.
- Xcode Command Line Tools. The installer starts Apple's installation prompt if they are missing; finish that installation and run the command again.
- A USB e-signature reader, card, and an appropriate ARM64 card driver. For AKİS, use the **Mac OS Arm (Apple Silicon)** package from [TÜBİTAK BİLGEM's AKİS support page](https://akiskart.bilgem.tubitak.gov.tr/tr/destek/).
- A valid signing request downloaded from TÜBİTAK.

You do not need a separate Java installation or Rosetta.

## Install

Run as your normal user:

```bash
curl -fsSL https://raw.githubusercontent.com/otcan/tubitak-eimza-mac-arm64/main/kur.sh | bash
```

The installer builds and locally signs **TUBITAK Signing Helper.app**, installs it in `~/Applications`, and registers it with macOS. It downloads a pinned Amazon Corretto 8 ARM64 runtime and the official TÜBİTAK application, checks their SHA-256 hashes, and verifies the JAR signature. It does not replace system Java or change global Gatekeeper settings.

## Sign a document

1. Connect the USB reader and insert your e-signature card.
2. Start the signing process on the TÜBİTAK website and download its `.jnlp` file.
3. Open **TUBITAK Signing Helper**, click **Open JNLP…**, and choose that file. Finder's **Open With → TUBITAK Signing Helper** is also supported.
4. Review the documents in the official signing window, select your certificate, and enter your PIN there.
5. Complete signing, then return to TÜBİTAK and verify the document's signing status.

**Check USB card** checks the reader and reads available signing certificates through the official client libraries. It does not ask for a PIN or create a signature.

The `.jnlp` identifies a server-side signing job; it is not the document being signed. The helper retrieves the current descriptor from the original TÜBİTAK HTTPS URL, validates it again, and confirms that it still refers to the same job. An expired job needs a fresh signing request from the website.

## What is supported

The supported workflow is the legacy `SignApplet` served by:

```text
https://e-imza.tubitak.gov.tr/sublimity-ess/jnlp/
sublimity-esign-client-swingui-1.21.0-SNAPSHOT-jar-with-dependencies.jar
```

This is a TÜBİTAK-specific launcher. It rejects other codebases, application classes, JAR versions, signing destinations, duplicate parameters, external XML entities, oversized files, and symbolic links.

Verified on an Apple Silicon Mac running **macOS 26.2**: native app launch, bundled Java execution, and opening a real TÜBİTAK signing request. USB reader enumeration is implemented through the official libraries; additional card/provider combinations need testing. Confirm the final signing result on the TÜBİTAK website.

## Build and test

```bash
git clone https://github.com/otcan/tubitak-eimza-mac-arm64.git
cd tubitak-eimza-mac-arm64
zsh ./build.sh                # build/TUBITAK Signing Helper.app
bash scripts/test-parser.sh  # synthetic requests; no card or real signing job
```

`bash ./kur.sh` builds and installs a local checkout. Downloads and signed build artifacts are cached outside the repository in `~/Library/Caches/TubitakSigningHelper`. The app under `build/` is a symlink to the signed artifact; keeping the bundle outside a synced Documents folder avoids Finder metadata breaking its code signature.

For an already reviewed Java 8 JDK and official JAR, `TUBITAK_JDK8_HOME` and `TUBITAK_OFFICIAL_JAR` override the dependency paths. The JAR must still match the pinned hash. `TUBITAK_HELPER_INSTALL_DIR` changes the installation directory.

## Troubleshooting

- **No USB reader detected:** reconnect the reader and press **Check USB card**. Close other applications using the card.
- **Card found but no certificate:** verify that the certificate is active and the correct card driver is installed.
- **Request unavailable or no documents returned:** download a new JNLP from the signing queue and open it again.
- **macOS blocks opening a downloaded JNLP:** open the helper first and select the file with **Open JNLP…**. [TÜBİTAK JNLP Guard](https://github.com/kadirseker00/tubitak-jnlp-macos-helper) is a separate, optional tool for the repeated macOS download-quarantine prompt.
- **Checksum mismatch during installation:** the cached file or official package differs from the reviewed version. Check for a repository update; do not disable checksum verification.

Local signing diagnostics are stored in:

```text
~/Library/Application Support/TubitakSigningHelper/signing.log
```

These logs can contain signing-job or certificate information. Redact them before attaching them to an issue. Do not upload real `.jnlp` files, PINs, or private application documents.

## Implementation and limits

- A Swift/AppKit launcher handles file selection and macOS document-open events.
- A small Java `AppletStub` host supplies the validated JNLP parameters to TÜBİTAK's unchanged `SignApplet`.
- The app contains its own Corretto 8 runtime. The system's PKCS#11 card driver provides access to the USB card.
- The build applies an ad-hoc local code signature. The app is not notarized.
- Only the reviewed TÜBİTAK application version is bundled. Upstream changes need a reviewed dependency/hash update.
- CI checks the request parser using synthetic data. It does not perform hardware signing or submit documents to TÜBİTAK.

## License and related work

The helper's source is [MIT licensed](LICENSE). Amazon Corretto/OpenJDK and TÜBİTAK's application retain their own licenses; see [third-party notices](THIRD_PARTY_NOTICES.md). The build copies Corretto's license notices into the generated app.

Related projects include [TÜBİTAK JNLP macOS Helper](https://github.com/kadirseker00/tubitak-jnlp-macos-helper) and [TNB E-İmza for Apple Silicon](https://github.com/saidsurucu/tnb-eimza-mac-arm64).
