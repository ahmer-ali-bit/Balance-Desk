# Personal macOS install (no Apple Developer membership required)

The distributable DMG is ad-hoc signed for personal use, not Developer ID signed or notarized. The installed copy should be re-signed locally after copying into Applications; this creates a fresh signature on the Mac that will run it and avoids requiring an Apple Developer membership for this single-user install. Do not expect this build to be suitable for public distribution.

1. Open the DMG and drag `Ledger Pro.app` onto the Applications shortcut.
2. Open Terminal and run the following commands. macOS will ask for the Mac administrator password if the app is in `/Applications`:

   ```sh
   APP="/Applications/Ledger Pro.app"
   sudo xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
   sudo codesign --force --deep --sign - --timestamp=none "$APP"
   codesign --verify --deep --strict --verbose=2 "$APP"
   open "$APP"
   ```

3. Once it opens, Ledger Pro should be discoverable in Launchpad. Leave the app in `/Applications`; avoid modifying files inside the `.app` bundle afterward, since that invalidates its local signature.

If the app is installed somewhere other than `/Applications`, change `APP` to its actual path. This local signing workaround is specific to the user's Mac. A no-prompt app for general distribution still requires Developer ID signing and Apple's notarization.
