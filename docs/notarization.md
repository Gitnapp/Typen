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

The script depends on two things already present in this machine's keychain
(see setup below):

- a `Developer ID Application` signing identity
- notarytool credentials stored under the keychain profile `typen-notary`

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

2. **notarytool credentials**
   - Generate an App-Specific Password at [appleid.apple.com](https://account.apple.com/account/manage)
     → Sign-In and Security → App-Specific Passwords.
   - Store it under the profile name `notarize.sh` expects:
     ```bash
     xcrun notarytool store-credentials "typen-notary" \
       --apple-id "your-apple-id@example.com" \
       --team-id "YOUR_TEAM_ID" \
       --password "xxxx-xxxx-xxxx-xxxx"
     ```
   - This validates the credentials against Apple and stores them in the
     keychain; you won't be prompted for the password again.

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
