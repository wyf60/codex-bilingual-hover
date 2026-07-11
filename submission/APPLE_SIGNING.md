# Apple Developer ID signing and notarization

The current public-review candidate is ad-hoc signed for local testing. OpenAI submission should use a stable Developer ID signature and Apple notarization.

## Prerequisites

1. Join the Apple Developer Program using the individual or business identity that will distribute the helper.
2. In Xcode or the Apple Developer portal, create and install a `Developer ID Application` certificate in the login keychain.
3. Confirm the identity appears with:

   ```bash
   security find-identity -v -p codesigning
   ```

4. Create an app-specific password or App Store Connect API key for `notarytool`.

## Build and sign

1. Build arm64 and x86_64 release binaries from the checked-in Swift source.
2. Combine them with `lipo` and place the universal binary in the app bundle.
3. Sign the app with hardened runtime and the real Developer ID Application identity:

   ```bash
   codesign --force --deep --options runtime --timestamp \
     --sign "Developer ID Application: YOUR VERIFIED NAME (TEAMID)" \
     "Codex Hover Translator.app"
   ```

4. Verify locally:

   ```bash
   codesign --verify --deep --strict --verbose=2 "Codex Hover Translator.app"
   spctl --assess --type execute --verbose=4 "Codex Hover Translator.app"
   ```

## Notarize and staple

1. Archive the signed app with `ditto`.
2. Submit the archive with `xcrun notarytool submit ... --wait`.
3. Staple and reassess:

   ```bash
   xcrun stapler staple "Codex Hover Translator.app"
   xcrun stapler validate "Codex Hover Translator.app"
   spctl --assess --type execute --verbose=4 "Codex Hover Translator.app"
   ```

4. Replace the ad-hoc app bundled in the plugin only after all checks pass, then rebuild the upload ZIP and update its checksum.

Never commit Apple certificates, private keys, app-specific passwords, API private keys, or notary credentials to this repository.
