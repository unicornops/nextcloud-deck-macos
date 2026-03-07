# Nextcloud Deck for macOS

A native macOS app for [Nextcloud Deck](https://github.com/nextcloud/deck) with a Trello-like board interface.

## Features

- **Sign in** with your Nextcloud server URL, username, and password. The app uses the [Nextcloud Login Flow / getapppassword](https://docs.nextcloud.com/server/latest/developer_manual/client_apis/LoginFlow/index.html) to obtain an app password and stores credentials securely in the system Keychain.
- **Boards** listed in the sidebar; switch between them to focus on one board at a time.
- **Trello-style board view**: stacks as columns, cards in each column. Create lists (stacks) and cards, open cards to edit title and description.
- Built with **SwiftUI** and follows current macOS design (toolbars, sidebar, materials).

## Requirements

- macOS 14.0+
- Xcode 15+ (to build)
- A Nextcloud server with the [Deck](https://apps.nextcloud.com/apps/deck) app installed.

## Build and run

1. Open `NextcloudDeck.xcodeproj` in Xcode.
2. Select the **NextcloudDeck** scheme and a Mac destination.
3. Press **Run** (⌘R).

Or from the terminal:

```bash
xcodebuild -scheme NextcloudDeck -configuration Debug -destination 'platform=macOS' build
open ~/Library/Developer/Xcode/DerivedData/NextcloudDeck-*/Build/Products/Debug/NextcloudDeck.app
```

### Building a signed DMG for distribution

From the repo root:

1. **Generate the app icon** (requires [librsvg](https://wiki.gnome.org/Projects/LibRsvg) for SVG→PNG, or place a 1024×1024 `icon_1024.png` in `NextcloudDeck/Assets.xcassets/AppIcon.appiconset/`):

   ```bash
   ./generate-appicon.sh
   ```

2. **Build Release** (sign with your Developer ID before creating the DMG if you want a signed app):

   ```bash
   xcodebuild -project NextcloudDeck.xcodeproj -scheme NextcloudDeck -configuration Release -derivedDataPath build/DerivedData build
   ```

3. **Create the DMG**:

   ```bash
   APP_PATH=$(find build/DerivedData/Build/Products -name "NextcloudDeck.app" -type d | head -n 1)
   ./create-dmg.sh "$APP_PATH" NextcloudDeck-1.0.0.dmg "Nextcloud Deck 1.0.0"
   ```

The icon source is `icon_source.svg`; edit it and re-run `./generate-appicon.sh` to refresh the app icon.

## Releases

On each published GitHub release, the **Build and Attach Release Assets** workflow builds the app (signed and notarized), generates a DMG and a ZIP, and attaches them to the release.

- **Icon**: The workflow runs `./generate-appicon.sh` (using `librsvg` on the runner) so the built app and DMG use the icon from `icon_source.svg`.
- **Signing and notarization**: The workflow signs and notarizes the app by default. Configure these repository secrets for the release job to succeed: `APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_TEAM_ID`, `APPLE_DEVELOPER_ID`, `APPLE_APP_PASSWORD`.

## API

The app uses the [Nextcloud Deck REST API](https://deck.readthedocs.io/en/latest/API/) (v1.0):

- `GET /boards` – list boards
- `GET /boards/{id}/stacks` – list stacks (columns) with cards
- Create/update/delete for boards, stacks, and cards

Authentication uses Basic auth with the app password obtained from `GET /ocs/v2.php/core/getapppassword` (or your existing app password if you sign in with one).

## Project structure

- **NextcloudDeck/** – main app target
  - **Models/** – `Board`, `Stack`, `Card`, `DeckLabel` (Deck API types)
  - **Services/** – `DeckAPI`, `NextcloudAuth`, `KeychainStorage`
  - **Views/** – Login, board list, board detail (columns + cards), card sheet, new stack sheet
  - **Helpers/** – `Color+Hex` for label/board colors

## License

Use and modify as you like. Deck and Nextcloud are their respective projects’ trademarks.
