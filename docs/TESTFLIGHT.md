# Releasing to TestFlight — runbook for Claude sessions

How to ship a build to TestFlight headlessly (no Xcode GUI, no signed-in Apple ID
in the keychain). This is the exact process that shipped build 3.

## When to release

**Only for significant milestones — not every commit.** e.g. the card-model
redesign (build 3), or the end of a phase (Phase 2). Routine commits don't go to
TestFlight. When unsure, ask the user before uploading.

## Credentials (never committed)

All identifiers live in the **git-ignored `.env`** at the repo root. Load them with
`set -a; source .env; set +a`. It defines:

| var | what |
|-----|------|
| `ASC_ISSUER_ID` | App Store Connect API issuer ID |
| `ASC_KEY_ID` | API key id (matches `AuthKey_<id>.p8`) |
| `ASC_KEY_PATH` | **path** to the `.p8` private key (in `~/Downloads`) |
| `APP_APPLE_ID` | the app's Apple ID (for ASC API queries) |
| `APP_BUNDLE_ID`, `DEVELOPMENT_TEAM` | bundle id / team id |

**Security:** reference the `.p8` by `ASC_KEY_PATH` only. Never `cat`/read its
contents — `xcrun altool --generate-jwt` reads it for you. If the key is missing,
the active one is the **newest** `~/Downloads/AuthKey_*.p8` (there may be two; the
latest is the live key) — also kept in `~/.appstoreconnect/private_keys/`.

## Toolchain

The watch target needs the **watchOS 27 SDK → Xcode 27 beta**, so every release
command is prefixed with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`.

## Steps

### 1. Bump the build number

App Store Connect rejects a duplicate `(version, build)`. Bump
`CURRENT_PROJECT_VERSION` across all target configs to the next integer, then commit.

```bash
NEXT=4   # whatever the next build number is
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $NEXT;/g" \
  "Adaptive Fitness Coach.xcodeproj/project.pbxproj"
git commit -am "Bump build to $NEXT for TestFlight"
```

### 2. Archive (iOS scheme embeds the watch app)

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project "Adaptive Fitness Coach.xcodeproj" -scheme "Adaptive Fitness Coach" \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build-archive/AdaptiveFitnessCoach.xcarchive archive
```

### 3. Export **and upload** with the API key

`ExportOptions-upload.plist` (committed, no secrets) has `destination: upload`. The
`-authenticationKey*` flags + `-allowProvisioningUpdates` let xcodebuild create the
**distribution certificate via the API** — no signed-in account or pre-existing cert
needed (this is why headless works).

```bash
set -a; source .env; set +a
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -exportArchive \
  -archivePath build-archive/AdaptiveFitnessCoach.xcarchive \
  -exportPath build-archive/upload \
  -exportOptionsPlist ExportOptions-upload.plist \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  -allowProvisioningUpdates
# -> "Upload succeeded" / "** EXPORT SUCCEEDED **"
```

### 4. Wait for processing, then confirm it's testable

Apple emails when processing completes (or poll). Export compliance is **already
declared** in the project (`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`), so new
builds should go straight to `IN_BETA_TESTING`. Generate a JWT and check:

```bash
set -a; source .env; set +a
JWT=$(xcrun altool --generate-jwt --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1 | grep -E '^eyJ' | tail -1)
curl -s -H "Authorization: Bearer $JWT" \
  "https://api.appstoreconnect.apple.com/v1/builds?filter%5Bapp%5D=$APP_APPLE_ID&filter%5Bversion%5D=$NEXT"
# look at attributes.processingState (VALID) and usesNonExemptEncryption (should be false)
```

### 5. Fallback — clear "Missing Compliance" (only if `usesNonExemptEncryption` is `null`)

Older builds (before the Info.plist declaration) stall in App Store Connect with
`usesNonExemptEncryption: None`, which keeps them out of TestFlight even when VALID.
This app uses only standard/HTTPS crypto (export-exempt), so set it to `false`:

```bash
BUILD_ID=...   # the build's id from step 4
curl -s -X PATCH -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
  "https://api.appstoreconnect.apple.com/v1/builds/$BUILD_ID" \
  -d "{\"data\":{\"type\":\"builds\",\"id\":\"$BUILD_ID\",\"attributes\":{\"usesNonExemptEncryption\":false}}}"
```

Then `GET /v1/builds/$BUILD_ID/buildBetaDetail` → `internalBuildState` should be
`IN_BETA_TESTING`. Tell the user to pull-to-refresh TestFlight (the device app caches).

## Notes

- **Internal** testers (App Store Connect users) get the build immediately once it's
  `IN_BETA_TESTING`. **External** groups (`externalBuildState: READY_FOR_BETA_SUBMISSION`)
  need a one-time Beta App Review submission first.
- `build-archive/` is git-ignored. `ExportOptions-upload.plist` and the bumped build
  number are the only things that get committed for a release.
