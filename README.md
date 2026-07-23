# Serey for Ubuntu Touch

A native Ubuntu Touch client for the [Serey](https://serey.io) social network. It
is built with QML and Lomiri for the 24.04 platform (Qt 5.15) and runs against the
same production API as the Serey web and mobile apps.

The app is a hybrid. The Homepage tab embeds the Serey community web app, while
News, Video, and Settings are native QML screens built directly on the API.

## Features

- Community feeds for news and video, with a regional community switcher (Global,
  countries, and their sub-communities)
- Upvoting and flagging, with optimistic counts
- Reading and posting comments
- Publishing blog posts and videos from the app
- Self-custody signup with keys generated on the device
- Offline video downloads and saved articles for offline reading
- Notifications over push and a background poll
- In-app subscription payments by crypto and Stripe
- A subscription-gated wizard to create your own community platform
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
clickable desktop    # desktop preview in the 24.04 container, fastest feedback
clickable            # build, install, and launch on a connected device
clickable build      # build a .click package only, no install
clickable logs       # device logs, useful for AppArmor denials or QML errors
```

The app targets the `ubuntu-touch-24.04-1.x` framework and will not install on
20.04 devices. There is no separate test or lint step; the desktop preview is the
main check.

## Configuration

By default the app talks to production at `https://global-api.serey.io/api/v2`.
To point it at a local `serey-api`, set `useLocalDev` in
[`qml/Theme/Config.qml`](qml/Theme/Config.qml).

A physical device cannot reach `localhost`. To use a local server from a device,
forward the port over ADB with `adb reverse tcp:5050 tcp:5050`, or set the dev URL
to your machine's LAN IP.

## Project structure

```
qml/
├── Main.qml         App shell: global header, four tabs (Homepage, News, Video,
│                    Settings), bottom nav that becomes a side rail on wide windows.
├── Theme/           Singletons: Config (API base URL and community state),
│                    Style (design tokens), and shared app state such as Toast,
│                    notifications, and payments.
├── Session/         Auth and local SQLite stores: session, offline downloads,
│                    saved posts, and the feed cache.
├── services/        Plain-JS API layer over XMLHttpRequest, one file per domain.
│                    Mappers.js normalises the API's quirks into clean view-models.
├── components/      Reusable UI: cards, bottom sheets, web views, and inputs.
└── pages/           Full screens for feeds, detail views, composers, and settings.

plugins/Serey/FileUtils   Small C++ plugin for chunked file reads during large
                          video uploads, so the whole file is not held in memory.
```

## Notes for contributors

- `Mappers.js` is the single place that knows the API's quirks. Some list fields
  come back as stringified Python lists (for example `image_url = "['https://...']"`)
  and nulls arrive as the string `"None"`. Keep that normalisation in the mapper so
  the QML always works with clean objects.
- The session is persisted in SQLite, not `Qt.labs.Settings`. Settings only flushes
  on a clean shutdown, so a swipe-kill would otherwise drop the token.
- Do not verify the stored token by calling `POST /auth/authenticated` on launch.
  That route also runs a device-JWT check the native client cannot satisfy and
  always returns 401, which would log the user out on every relaunch. Trust the
  stored token; the endpoints the app uses only need a normal JWT.
- The feed list endpoints accept `?community_id=`, which filters server-side and
  recursively so a parent community includes its children. Community id `0` is the
  combined Global feed (no filter).

The app identity is `serey.serey-io`, and it must match across `manifest.json.in`,
`Main.qml`, and `serey.desktop`.
