<p align="center"><img src="icon_source.svg" width="128" height="128" alt="Shuffleboard icon: three lanes on wooden deck boards, with pucks as cards"></p>

# Shuffleboard

**An unofficial native macOS client for [Nextcloud Deck](https://github.com/nextcloud/deck).** Shuffle the cards on your Deck boards from a fast, native Mac app.

> Shuffleboard is an independent project. It is not the official Nextcloud client and is not affiliated with or endorsed by Nextcloud GmbH. For official Nextcloud apps, see [nextcloud.com/install](https://nextcloud.com/install/).

### Why "Shuffleboard"?

It's a board where you shuffle cards around, and shuffleboard is the game played on a ship's deck. The name nods to Deck without borrowing it: [Nextcloud's trademark guidelines](https://nextcloud.com/trademarks/) ask third-party clients not to use "Nextcloud" in their name, and we'd rather respect the project that makes this app possible. Until October 2026 this app was called "Nextcloud Deck for macOS", which used Nextcloud's trademark in a way it shouldn't have.

### Upgrading from "Nextcloud Deck for macOS"

Shuffleboard has a new app identity (bundle ID `ie.unicornops.shuffleboard`), so macOS treats it as a new app:

1. In the old app, choose **Sign Out** from the account menu. This revokes its app password on your server (in versions that support it). Otherwise, remove the old device under **Nextcloud → Settings → Security**.
2. Delete the old `NextcloudDeck.app`.
3. Open Shuffleboard and sign in once.

Your boards live on your Nextcloud server, so nothing is lost. The old app's Keychain entry can be removed in Keychain Access (search for `nextclouddeck`).

## Features

- **Sign in** with your Nextcloud server URL: the app opens your browser to sign in (including two-factor authentication) using [Nextcloud Login Flow v2](https://docs.nextcloud.com/server/latest/developer_manual/client_apis/LoginFlow/index.html), receives an app password and stores it securely in the system Keychain. Signing out revokes the app password.
- **Boards** listed in the sidebar; switch between them to focus on one board at a time.
- **Kanban board view**: stacks as columns, cards in each column. Create lists (stacks) and cards, open cards to edit title and description.
- Built with **SwiftUI** and follows current macOS design (toolbars, sidebar, materials).

## Requirements

- macOS 14.0+
- Xcode 15+ (to build)
- A Nextcloud server with the [Deck](https://apps.nextcloud.com/apps/deck) app installed.

## Developer tooling

The project uses several tools to enforce code quality. Install them all with Homebrew:

```bash
brew install pre-commit swiftformat swiftlint pmd
pre-commit install && pre-commit install --hook-type commit-msg
```

| Tool | Purpose | Config |
|------|---------|--------|
| [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) | Code formatting | `.swiftformat` |
| [SwiftLint](https://github.com/realm/SwiftLint) | Style & lint rules | `.swiftlint.yml` |
| [PMD](https://pmd.github.io) | Static analysis + copy-paste detection | `pmd-ruleset.xml` |
| [pre-commit](https://pre-commit.com) | Runs all checks before each commit | `.pre-commit-config.yaml` |

### PMD

PMD runs two checks on every commit and on every pull request:

- **Static analysis** (`pmd check`) — all four built-in Swift rules:
  - `ProhibitedInterfaceBuilder` — flags accidental `@IBOutlet`/`@IBAction` usage in this pure-SwiftUI app.
  - `UnavailableFunction` — ensures `@available(*, unavailable)` stubs call `fatalError()`.
  - `ForceCast` — prohibits `as!` which can crash at runtime.
  - `ForceTry` — prohibits `try!` which suppresses structured error handling.
- **Copy-paste detection** (`pmd cpd`) — finds duplicated blocks of 50+ tokens across all Swift source files.

To suppress a specific PMD violation in source (use sparingly, with a reason):

```swift
let value = foo as! Bar // NOPMD - safe: type is guaranteed by the API contract
```

Run PMD locally at any time:

```bash
# Static analysis
pmd check --rulesets pmd-ruleset.xml --dir Shuffleboard --format text

# Copy-paste detection
pmd cpd --minimum-tokens 105 --dir Shuffleboard --language swift --format text
```

## Build and run

1. Open `Shuffleboard.xcodeproj` in Xcode.
2. Select the **Shuffleboard** scheme and a Mac destination.
3. Press **Run** (⌘R).

Or from the terminal:

```bash
xcodebuild -scheme Shuffleboard -configuration Debug -destination 'platform=macOS' build
open ~/Library/Developer/Xcode/DerivedData/Shuffleboard-*/Build/Products/Debug/Shuffleboard.app
```

### Running tests

Unit tests live in `ShuffleboardTests/` and run inside the app. Press **⌘U** in Xcode, or:

```bash
xcodebuild test -scheme Shuffleboard -destination 'platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
```

They never touch the real Keychain or a real server: `AppState` takes an in-memory `CredentialStore` and a `URLSession` that talks to `StubURLProtocol`. They run on every pull request.

### Building a signed DMG for distribution

From the repo root:

1. **Generate the app icon** (requires [librsvg](https://wiki.gnome.org/Projects/LibRsvg) for SVG→PNG, or place a 1024×1024 `icon_1024.png` in `Shuffleboard/Assets.xcassets/AppIcon.appiconset/`):

   ```bash
   ./generate-appicon.sh
   ```

2. **Build Release** (sign with your Developer ID before creating the DMG if you want a signed app):

   ```bash
   xcodebuild -project Shuffleboard.xcodeproj -scheme Shuffleboard -configuration Release -derivedDataPath build/DerivedData build
   ```

3. **Create the DMG**:

   ```bash
   APP_PATH=$(find build/DerivedData/Build/Products -name "Shuffleboard.app" -type d | head -n 1)
   ./create-dmg.sh "$APP_PATH" Shuffleboard-1.0.0.dmg "Shuffleboard 1.0.0"
   ```

The icon source is `icon_source.svg`; edit it and re-run `./generate-appicon.sh` to refresh the app icon.

## Releases

On each published GitHub release, the **Build and Attach Release Assets** workflow builds the app (signed and notarized), generates a DMG and a ZIP, and attaches them to the release.

- **Icon**: The workflow runs `./generate-appicon.sh` (using `librsvg` on the runner) so the built app and DMG use the icon from `icon_source.svg`.
- **Signing and notarization**: The workflow signs and notarizes the app by default. Configure these repository secrets for the release job to succeed: `APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_TEAM_ID`, `APPLE_DEVELOPER_ID`, `APPLE_APP_PASSWORD`.

## API

The app uses only the documented [Nextcloud Deck REST API](https://deck.readthedocs.io/en/latest/API/): v1.0 for boards, lists, cards and labels, and v1.1 for attachments (Deck 1.3 or later):

- `GET /boards` – list boards
- `GET /boards/{id}/stacks` – list stacks (columns) with cards
- Create/update/delete for boards, stacks, and cards
- `PUT /boards/{id}/stacks/{id}/cards/{id}/reorder` – move a card within or between lists
- `/boards/{id}/stacks/{id}/cards/{id}/attachments[/{type}/{id}]` (v1.1) – list, download, upload and delete attachments

Authentication uses Basic auth with the app password obtained through Login Flow v2 (`POST /index.php/login/v2`, then polling). Sign-out revokes it with `DELETE /ocs/v2.php/core/apppassword`.

## Project structure

- **Shuffleboard/** – main app target
  - **Models/** – `Board`, `Stack`, `Card`, `DeckLabel` (Deck API types)
  - **Services/** – `DeckAPI`, `NextcloudAuth`, `KeychainStorage`
  - **Views/** – Login, board list, board detail (columns + cards), card sheet, new stack sheet
  - **Helpers/** – `Color+Hex` for label/board colors

## License

Shuffleboard is free software, licensed under the [GNU General Public License v3.0](LICENSE). You may use, study, share and modify it; if you distribute it or a modified version, you must do so under the same licence and make the source code available.

Nextcloud is a trademark of Nextcloud GmbH. Shuffleboard is an independent, unofficial client for the Deck app and is not affiliated with or endorsed by Nextcloud.
