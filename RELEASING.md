# Signed macOS releases

Use an Apple Silicon Mac with Xcode Command Line Tools, a valid **Developer ID Application** certificate and its private key, and access to the same Apple Developer team for notarization.

Save notarization credentials using Apple's interactive password prompt:

```sh
xcrun notarytool store-credentials tubitak-release --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
```

Use an Apple app-specific password. Do not put passwords in commands, repository files, CI logs, or release notes. Alternatively, use a separately configured notarytool Keychain profile with `NOTARY_PROFILE`.

```sh
export CODE_SIGN_IDENTITY='Developer ID Application: YOUR_IDENTITY (YOUR_TEAM_ID)'
zsh scripts/release.sh prepare
python3 tests/test-native.py 'build/TUBITAK Signing Helper.app/Contents/MacOS/TubitakSigningHelper'
zsh scripts/release.sh notarize
```

Artifacts and private notarization logs are written outside the repository under `~/Library/Caches/TubitakSigningHelper/releases/0.2.0`.

The workflow signs native files inside-out with secure timestamps, then signs nested frameworks and the app. Hardened runtime applies to native code. Only the Java executable receives JIT, unsigned executable memory and disabled library validation entitlements: Java 8 needs JIT support, and AKİS provides a separately signed PKCS#11 library. The native Swift launcher receives no exception entitlements. No debugger or get-task-allow entitlement is enabled.

The app is submitted to Apple's notary service, its ticket is stapled and checked with Gatekeeper, and then the containing DMG is signed, notarized, stapled and checked separately. Publish only after both submissions are **Accepted** and the final checks succeed. Inspect both notarization logs, including warnings.

For each binary release, also upload Corretto's matching source archive from:

```text
https://github.com/corretto/corretto-8/archive/refs/tags/8.512.09.1.tar.gz
SHA256 ca73085d35b9a9a44527ed41deb7aa4ce38a9b7976a62c3f19fd0455780c6997
```

Include `SHA256SUMS` covering the DMG and corresponding source archive. The helper's source is supplied by the release tag. Retain all runtime notices in the app. Do not upload the official TÜBİTAK signing JAR, AKİS installer, real JNLPs, signing logs, credentials, or private notarization logs.
