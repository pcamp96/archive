# Archive

Archive is a native macOS notes app for working directly on Markdown files in a local workspace. It keeps files canonical on disk, treats `.archive/` metadata as optional workspace state, and gives you both list and board views over the same note set.

## App Icon

Early icon direction for Archive:

![Early Archive app icon](Archive/Resources/icon-marketing-1024.png)

This is an early version of the app icon and should be treated as a working draft rather than final brand artwork.

## Current Scope

- Browse a workspace of Markdown notes and folders
- Edit note bodies with a native macOS text editor bridge
- Read and write frontmatter-backed properties
- Switch between list and board presentations
- Search across note titles, body content, and properties
- Copy plain text or rendered HTML fragments for publishing workflows

## Stack

- SwiftUI for the app shell
- AppKit-backed text editing for the Markdown editor
- `swift-markdown` for Markdown handling
- `Yams` for frontmatter serialization
- `XcodeGen` for project generation from `project.yml`

## Requirements

- macOS 15 or later
- Xcode 16 or later
- Homebrew `xcodegen` if you want to regenerate the project file

## Development

Build:

```sh
xcodebuild build -project Archive.xcodeproj -scheme Archive -destination 'platform=macOS'
```

Test:

```sh
xcodebuild test -project Archive.xcodeproj -scheme Archive -destination 'platform=macOS'
```

Regenerate the Xcode project after changing `project.yml`:

```sh
xcodegen generate
```

## Repository Layout

- `Archive/`: app code
- `ArchiveTests/`: unit and integration-style tests
- `project.yml`: XcodeGen source of truth
- `Archive.xcodeproj/`: generated Xcode project checked into the repo

## GitHub Actions Release Plan

This repo is set up to support two different automation paths:

- Every push and pull request runs macOS build and test validation
- Version tags like `v0.1.0` or a manual workflow dispatch produce a signed, notarized release artifact

Important: the release workflow is designed around a `Developer ID Application` certificate for outside-the-Mac-App-Store distribution. That is different from an `Apple Development` certificate.

### Required GitHub Secrets

- `BUILD_CERTIFICATE_BASE64`: base64-encoded exported `.p12` Developer ID certificate
- `P12_PASSWORD`: password used when exporting the `.p12`
- `APP_STORE_CONNECT_API_KEY`: contents of the App Store Connect API `.p8` key
- `APP_STORE_CONNECT_KEY_ID`: App Store Connect key ID
- `APP_STORE_CONNECT_ISSUER_ID`: App Store Connect issuer ID

### Recommended Release Flow

1. Push branches normally and let CI build and test the app.
2. When you want a distributable build, create and push a version tag such as `v0.1.0`.
3. GitHub Actions archives the app, signs it with your Developer ID certificate, notarizes it with Apple, staples the notarization ticket, and uploads the final zip to a GitHub Release.

### Security Note

GitHub-hosted macOS runners can sign with your Developer ID certificate, but only because the workflow imports your certificate and notarization credentials from GitHub Secrets at runtime. That is workable, but it means a real signing identity is available to the release workflow. If you want tighter control, keep push CI on GitHub-hosted runners and move the signing/notarization job to a self-hosted Mac you control.
