# Distribution and Release Contract

Mochi publishes one version from one immutable Git tag through `.github/workflows/release.yml`. The workflow builds the universal application once, signs it with Developer ID, notarizes and staples the DMG, and then reuses the resulting checksum and release manifest for every channel.

## Channels

1. GitHub Releases owns the canonical `Mochi.dmg`, versioned ZIP, checksum, and release manifest.
2. The first-party Homebrew tap receives a cask generated from that manifest. Moving to `homebrew/cask` changes only the publication step, not the artifact.
3. The separate `mochi-web` repository owns the React website and deploys it through Vercel. Its download button resolves GitHub's latest-release `Mochi.dmg` asset, so the website does not rebuild or mirror the application.

No channel rebuilds or re-signs the application. Verification fails the release if the public checksum differs from the manifest.

## Required GitHub environment secrets

- `CERTIFICATE_P12_BASE64`
- `CERTIFICATE_PASSWORD`
- `APPLE_SIGNING_IDENTITY`
- `NOTARY_KEY_BASE64`
- `NOTARY_KEY_ID`
- `NOTARY_ISSUER_ID`
- `MOCHI_TAP_TOKEN`

The `release` environment should require approval and restrict deployments to protected semantic-version tags. Prefer replacing `MOCHI_TAP_TOKEN` with a short-lived GitHub App installation token when the tap is provisioned.

## Release procedure

1. Land and verify the release commit on `main`.
2. Create and push an annotated `vMAJOR.MINOR.PATCH` tag.
3. Approve the protected release environment.
4. Confirm the GitHub Release checksum and tap cask match, then verify the Vercel website resolves the latest release download.

Sparkle must consume the versioned ZIP from this same release and may not introduce another build. Its signing key and feed generation will be enabled when the updater framework is integrated into the app.
