# Releasing

Step-by-step checklist for publishing a new Shellporter release.

## Prerequisites (one-time setup)

- [ ] Copy `.env.example` to `.env` and fill in your values (Apple identity, Team ID, Sparkle keys, etc.)
- [ ] Apple Developer ID certificate installed (the identity string goes in `APP_IDENTITY` in `.env`)
- [ ] Notarization credentials stored: `xcrun notarytool store-credentials "NOTARIZATION_PASSWORD" --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "<app-specific-password>"`
- [ ] Sparkle EdDSA private key available (path exported as `SPARKLE_PRIVATE_KEY_FILE`)
- [ ] Sparkle CLI tools installed (`brew install --cask sparkle`) — provides `generate_appcast`
- [ ] GitHub repo remote configured and `gh` CLI authenticated

## Release checklist

### 1. Bump version

Edit `version.env`:

```bash
MARKETING_VERSION=X.Y.Z
BUILD_NUMBER=<increment>
```

`BUILD_NUMBER` must be strictly greater than the previous release (Sparkle uses it to determine update order).

### 2. Update CHANGELOG.md

Add a new section at the top of `CHANGELOG.md`:

```markdown
## X.Y.Z

- What changed
- Another change
```

The version string must match `MARKETING_VERSION` exactly.

### 3. Run tests

```bash
swift test
```

### 4. Build, sign, and notarize

```bash
./Scripts/sign-and-notarize.sh
```

This produces `Shellporter-X.Y.Z.zip` (universal binary, signed, notarized, stapled).

### 5. Create a GitHub Release

```bash
git tag vX.Y.Z
git push origin vX.Y.Z

gh release create vX.Y.Z Shellporter-X.Y.Z.zip \
  --title "Shellporter X.Y.Z" \
  --notes-file <(sed -n '/^## X.Y.Z$/,/^## /{ /^## X.Y.Z$/d; /^## /d; p; }' CHANGELOG.md)
```

Or create the release manually on GitHub and upload the zip.

### 6. Generate the appcast

```bash
SPARKLE_PRIVATE_KEY_FILE=~/sparkle_ed25519_key \
  ./Scripts/make_appcast.sh Shellporter-X.Y.Z.zip
```

This updates `appcast.xml` with the new entry (version, download URL, EdDSA signature, embedded release notes).

### 7. Commit and push the appcast

```bash
git add appcast.xml
git commit -m "Update appcast for X.Y.Z"
git push origin main
```

The appcast is served from the URL configured as `SPARKLE_FEED_URL` in `.env`. Once pushed, existing users will see the update.

### 8. Verify

- [ ] `appcast.xml` contains the new version entry with an `edSignature`
- [ ] Download URL in the appcast returns 200: `curl -sI <url> | head -1`
- [ ] Install a previous version and click "Check for Updates" to confirm the flow works

## Environment variables reference

| Variable | Purpose |
|---|---|
| `SPARKLE_PRIVATE_KEY_FILE` | Path to Sparkle Ed25519 private key |
| `APP_IDENTITY` | Override signing identity (defaults to Developer ID) |
| `KEYCHAIN_PROFILE` | Notarization keychain profile (defaults to `NOTARIZATION_PASSWORD`) |
| `ARCHES` | Build architectures (defaults to `arm64 x86_64`) |
| `SPARKLE_DOWNLOAD_URL_PREFIX` | Override download URL base in appcast |
| `SPARKLE_FEED_URL` | Override appcast feed URL |
