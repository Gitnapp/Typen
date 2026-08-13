# Notarization

Release builds are signed with a Developer ID Application certificate and
notarized by Apple, so a downloaded `Typen.app` passes Gatekeeper without a
security warning.

## Releasing

```bash
./scripts/notarize.sh
```

This does `flutter build macos --release`, re-signs the app with the
Developer ID identity (Hardened Runtime + `macos/Runner/Release.entitlements`),
submits it to Apple's notary service and waits for a verdict, then staples
the notarization ticket to the app. Output: `build/macos/Build/Products/Release/Typen.app`.

The script depends on two things already present on this machine (see setup
below):

- a `Developer ID Application` signing identity, in the login keychain
- an App Store Connect API key (`.p8` file) at the path `notarize.sh` points
  `API_KEY_PATH` to

## One-time machine setup

Only needed on a machine that hasn't notarized a Typen build before (identity
and credentials live in the local keychain, not in the repo).

1. **Developer ID Application certificate**
   - Generate a CSR + private key:
     ```bash
     openssl req -new -newkey rsa:2048 -nodes \
       -keyout DeveloperIDApplication.key \
       -out DeveloperIDApplication.csr \
       -subj "/emailAddress=you@example.com/CN=Your Name/C=CN"
     ```
   - developer.apple.com → Certificates, Identifiers & Profiles → Certificates
     → **+** → *Developer ID Application* → G2 Sub-CA → upload the `.csr` →
     download the issued `.cer`.
   - Import both into the login keychain:
     ```bash
     security import DeveloperIDApplication.key -k ~/Library/Keychains/login.keychain-db -A
     security import DeveloperIDApplication.cer -k ~/Library/Keychains/login.keychain-db -A
     security find-identity -v -p codesigning   # confirm "Developer ID Application: ..." shows up
     ```
   - Delete the `.key`/`.csr`/`.cer` files afterward — the identity now lives
     in the keychain.

2. **notarytool credentials (App Store Connect API key)**
   - [appleid.apple.com](https://appstoreconnect.apple.com/access/api) →
     Keys → **+** → role *Developer* (notarization only needs that, not
     Admin) → generate.
   - Apple only lets you download the `.p8` once, at creation time. Save it
     to `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` — that's the
     path `notarize.sh` expects (`API_KEY_PATH`), and the conventional
     location `notarytool` itself searches by default.
   - Update `API_KEY_ID` and `API_KEY_ISSUER` in `scripts/notarize.sh` to
     match the key you generated (the issuer ID is shown on the same Keys
     page, one per account — not per key).
   - Preferred over the older Apple-ID + app-specific-password +
     `--keychain-profile` method: an app-specific password can get silently
     invalidated (a password change, a security review) and there's no
     signal until the next release breaks — this key doesn't expire that
     way, and doesn't depend on keychain state at all.

If the identity name in `scripts/notarize.sh` (`IDENTITY=`) doesn't match
what `security find-identity -v -p codesigning` shows on a new machine,
update that line — it must be copied verbatim, including the Team ID suffix.

## Verifying a build

```bash
codesign --verify --deep --strict --verbose=2 Typen.app
spctl -a -vvv --type execute Typen.app   # should print "accepted, source=Notarized Developer ID"
xcrun stapler validate Typen.app
```

## Why post-build signing, not Xcode automatic signing

The Xcode project builds Release with `CODE_SIGN_IDENTITY = "-"` (ad-hoc) and
no `DEVELOPMENT_TEAM`, matching how `flutter build macos` invokes `xcodebuild`
directly (no archive/export step, so Xcode's automatic-signing/export-method
flow doesn't apply). Rather than reconfigure Xcode signing and provisioning
for that flow, `scripts/notarize.sh` re-signs the already-built `.app` with
`codesign --options runtime` after the Flutter build — same end result,
without disturbing Debug/Profile builds or requiring a provisioning profile.
