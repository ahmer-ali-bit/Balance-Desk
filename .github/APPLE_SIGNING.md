# macOS release signing and notarization

The macOS release workflow intentionally refuses to publish an ad-hoc-signed app. The previous DMG had no Developer ID identity (`codeSigningID` and `codeSigningTeamID` were empty in the crash report), so macOS did not trust it as a distributable app. For a DMG that can be copied into Applications and launched normally, configure these **GitHub Actions repository secrets**:

| Secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE_P12_BASE64` | Base64-encoded export of the **Developer ID Application** certificate and private key (`.p12`) |
| `APPLE_CERTIFICATE_PASSWORD` | Password used when exporting that `.p12` file |
| `APPLE_TEAM_ID` | Apple Developer Team ID associated with the certificate |
| `APPLE_ID` | Apple ID used for notarization |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for that Apple ID (not the account password) |

Create/export a Developer ID Application certificate and its private key using Apple Developer and Keychain Access. On macOS, encode the exported `.p12` without adding line breaks:

```sh
base64 -i DeveloperID.p12 | tr -d '\n'
```

Save that output as `APPLE_CERTIFICATE_P12_BASE64`, and save the export password as `APPLE_CERTIFICATE_PASSWORD`. Create an app-specific password from the Apple ID account security settings for `APPLE_APP_SPECIFIC_PASSWORD`. Add all five values under the repository's **Settings → Secrets and variables → Actions → New repository secret**. Do not commit the certificate, private key, or passwords, and do not paste them into chat.

After the secrets are configured, run **Build macOS DMG** with `workflow_dispatch` (or push to the branch). The workflow signs the app with Developer ID and hardened runtime, submits the DMG to Apple's notary service, staples Apple's approval, and validates the staple before publishing the artifact. A notarized DMG is required for the normal drag-to-Applications installation flow to launch without Gatekeeper warnings or the invalid-signature termination.
