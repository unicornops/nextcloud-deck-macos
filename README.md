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
