# Serey for Ubuntu Touch

A native Ubuntu Touch client for the [Serey](https://serey.io) social network,
built with QML and Lomiri for the 24.04 platform (Qt 5.15). It runs against the
same production API as the Serey web and mobile apps.

The app is a hybrid. The Homepage tab embeds the Serey community web app, while
News, Video, and Settings are native QML screens built directly on the API.

## Features

**Reading**

- Community feeds for news and video, with a regional platform switcher (Global,
  countries, and their sub-communities)
- Search and category filtering within News
- Gallery and Reels browsing
- Saved posts, offline article reading, and offline video downloads
- Article summaries

**Taking part**

- Upvoting and flagging, with optimistic counts
- Comments with nested replies, likes, and dislikes
- Following accounts and subscribing to platforms
- Publishing blog posts, videos, and gallery posts, with a per-platform publish
  scope, a category step at publish time, and a reader-style preview

**Accounts**

- Self-custody signup with keys generated on the device
- Two-factor authentication, active session management, and password change
  and recovery
- Anonymous invites, and redeeming one to join

**Moderation and safety**

- Blocking and unblocking accounts, hiding posts, and reporting content
- In-app bug reporting

**Running your own platform**

- A subscription-gated wizard to create your own community platform
- Platform administration: profile and information, settings, custom menu,
  blog and video management, and homepage management
- Platforms with no homepage of their own hide the Homepage tab automatically
  and open on News, with the owner able to switch it back on

**Platform integration**

- Notifications over push and a background poll
- In-app subscription payments by crypto and Stripe
- English and Dutch, via gettext catalogues and in-app translation
- A convergent layout that adapts from phone to tablet and desktop

## Requirements

- [Clickable](https://clickable-ut.dev/) 8.8.0 or newer, the build tool for Ubuntu Touch
- Docker, which Clickable uses to run the build in a container
- An Ubuntu Touch device on the 24.04-1.x framework for on-device testing

Clickable does not run natively on Windows. On Windows, build from WSL with Docker
available inside the WSL distribution.

```bash
pipx install clickable-ut    # or: pip install --user clickable-ut
```

## Build and run

From the project root:

```bash
clickable desktop            # desktop preview in the 24.04 container, fastest feedback
clickable                    # build, install, and launch on a connected device
clickable build              # build a .click package only, no install
clickable build --arch arm64 # build the arm64 package published on Releases
clickable logs               # device logs, useful for AppArmor denials or QML errors
```

The app targets the `ubuntu-touch-24.04-1.x` framework and will not install on
20.04 devices. There is no separate test or lint step; the desktop preview is the
main check.

Installing a downloaded package on the device:

```bash
pkcon install-local --allow-untrusted serey.serey-io_<version>_arm64.click
```

## Configuration

By default the app talks to production at `https://global-api.serey.io/api/v2`.
To point it at a local `serey-api`, set `useLocalDev` in
[`qml/Theme/Config.qml`](qml/Theme/Config.qml), which switches both the v2 and v1
base URLs to `http://localhost:5050`.

A physical device cannot reach `localhost`. To use a local server from a device,
forward the port over ADB with `adb reverse tcp:5050 tcp:5050`, or set the dev URL
to your machine's LAN IP.

## Project structure

```
qml/
├── Main.qml         App shell: global header, four tabs (Homepage, News, Video,
│                    Settings), bottom nav that becomes a side rail on wide windows.
├── Theme/           Singletons: Config (API base URLs and community state),
│                    Style (design tokens), and shared app state such as Toast,
│                    notifications, and payments.
├── Session/         Auth and local SQLite stores: session, offline downloads,
│                    saved posts, and the feed cache.
├── services/        Plain-JS API layer over XMLHttpRequest, one file per domain.
│                    Mappers.js normalises the API's quirks into clean view-models.
├── components/      Reusable UI: cards, bottom sheets, web views, and inputs.
└── pages/           Full screens for feeds, detail views, composers, moderation,
                     account security, and platform administration.

plugins/Serey/FileUtils   Small C++ plugin for chunked file reads during large
                          video uploads, so the whole file is not held in memory.

po/                       gettext catalogues (currently Dutch) plus the template.
```

## License

Released under the [GNU General Public License v3.0](LICENSE).

Bundled third-party components keep their own terms: the Noto fonts in
`assets/fonts/` under the SIL Open Font License (`assets/fonts/OFL.txt`), and
`qml/services/QrCodeGen.js` under the MIT license.
