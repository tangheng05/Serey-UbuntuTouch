# Serey Notifications — Flow Spec for the Ubuntu Touch Team

This document describes the **two independent notification mechanisms** in the Serey iOS
app so the Ubuntu Touch team can re-implement equivalent behaviour. It is written from
the iOS source as the reference implementation, but the contract it describes is the
**backend HTTP contract**, which is platform-agnostic.

The two mechanisms are:

1. **Push notifications** — real-time alerts delivered to the device while the app is
   backgrounded/closed (iOS uses APNs + Firebase Cloud Messaging).
2. **In-app Notification Center** — a pull/list of the user's notification history shown
   inside the app (no push involved; plain REST calls).

They are **separate systems with separate backends**:

| | Push notifications | In-app Notification Center |
|---|---|---|
| Backend host | `Constants.notificationCenterUrl` → `https://notification.serey.io` (prod) / `https://notification-testnet.serey.io` (dev) | `Constants.apiEndPoint` → `https://global-api.serey.io` |
| Path prefix | `/api/notification/user/...` | `/api/v2/notification/...` |
| Auth | Service login → bearer token (see §1.3) | User's bearer token |
| Purpose | Register/refresh the device push token | Fetch + mark-read the notification list |

---

## 1. Push Notification Flow

### 1.1 High-level sequence

```
App launch
  └─> configure push SDK (iOS: Firebase) 
  └─> request OS permission (.alert .badge .sound)
  └─> register with OS for remote notifications
          └─> OS returns a device push token (iOS: APNs token → FCM token)

User logs in  (or token refreshes, or app becomes active)
  └─> if (authenticated && notifications NOT disabled by user):
        └─> obtain current push token
        └─> POST register token to Notification Center backend  (see §1.3)
              └─> if backend says "already registered" (code == 1):
                    └─> POST updateToken instead

Server has an event for the user (comment / vote / follow / ...)
  └─> Notification Center backend sends a push via FCM/APNs
        └─> device receives payload
              └─> foreground: refresh in-app badge/list, show banner
              └─> background/tap: route via deep-link to the relevant screen
```

### 1.2 Device-side responsibilities (what iOS does)

Reference: `SereyIO/APNS/APNSHandler.swift`, `SereyIO/Helpers/Store/User/APNSTokenStore.swift`

1. **Init the push SDK at startup.** iOS calls `FirebaseApp.configure(...)` with a
   `GoogleService-Info.plist`. On Ubuntu Touch you will instead use the platform push
   mechanism (UBports Push Notifications / Google services are not available) — the
   important part is: **obtain a stable device push token string**.
2. **Ask for permission and register with the OS** for remote notifications
   (`requestAuthorization` + `registerForRemoteNotifications`).
3. **Receive the device token** in the OS callback, store it, and **send it to the
   Notification Center backend** (only when the user is authenticated).
4. **Refresh on token rotation** — whenever the push SDK issues a new token, re-send it.
5. **Re-assert on `applicationDidBecomeActive`** — reconnect and re-sync the token.
6. **On logout / disable-notifications** — call the backend `removeToken` endpoint.

Guard conditions before sending a token (`APNSTokenStore.saveToken`):
```
guard user is authenticated
guard NOT user-disabled-notifications (a local preference toggle)
```

### 1.3 Backend contract — Notification Center (push token management)

Base URL: `https://notification.serey.io` (prod) / `https://notification-testnet.serey.io` (dev)

> **Auth model is two-step.** This backend does NOT use the normal Serey user token.
> The client first does a **service login** with a fixed machine account to get a bearer
> token, then uses that bearer token for the token-management call.

**Step A — Service login**
```
POST /api/notification/user/login
Content-Type: application/json

{
  "username":   "mobile",
  "password":   "&_3W!nEv'}5cq}XX",
  "rememberMe": true
}

→ 200
{
  "status": { "responseCode": <int>, "responseMessage": "<string>" },
  "data":   { "token": "<bearer-token>" }
}
```
Use `data.token` as `Authorization: Bearer <token>` for Step B.

> ⚠️ Security note for the Ubuntu team: this service credential is currently hard-coded
> in the iOS client (`PushApi.login`). Treat it as a shared secret and confirm with
> backend whether Ubuntu Touch should use the same account or a dedicated one.

**Step B — Register the device token**
```
POST /api/notification/user/createToken
Authorization: Bearer <token from Step A>
Content-Type: application/x-www-form-urlencoded

username=<serey-username>
token=<device-push-token>
deviceType=IOS              # set an appropriate value for Ubuntu, confirm with backend
platformType=SEREY_WEB

→ { "status": { "responseCode": <int>, "responseMessage": "..." }, "data": ... }
```
If the response `status.responseCode == 1` it means **already registered** — the client
then calls `updateToken` (Step C).

**Step C — Update an existing token**
```
POST /api/notification/user/updateToken
Authorization: Bearer <token from Step A>
Content-Type: application/x-www-form-urlencoded

username=<serey-username>
newToken=<device-push-token>
platformType=SEREY_WEB
```

**Step D — Remove token (logout / notifications disabled)**
```
POST /api/notification/user/removeToken
Authorization: Bearer <token from Step A>
Content-Type: application/x-www-form-urlencoded

username=<serey-username>
```

> Note: every token-management call (B/C/D) is preceded by a fresh service login (A) in
> the iOS client.

### 1.4 Receiving / handling a push payload

iOS branches on app state (`APNSHandler.handleRecivedNotification`):

- **Foreground & not a user tap** → broadcast an internal `notificationRecived` event so
  the in-app badge / list refreshes; optionally show an in-app banner.
- **Background or user tapped the notification** → treat as "external"; pass the payload
  to the **deep-link router** (`Deeplinker.handldNotificationData(userInfo)`) which opens
  the relevant post/profile screen.

The payload is a standard push envelope. iOS reads the `aps` dictionary to decide it is a
displayable notification, then hands the full `userInfo` to the deep-linker. For Ubuntu
Touch, confirm with the backend the exact custom keys in the payload (post author/permlink
etc.) so you can route taps to the right screen — these mirror the in-app model fields in
§2.3.

### 1.5 Ubuntu Touch adaptation notes for push

- There is **no Firebase/APNs** on Ubuntu Touch. Replace the SDK layer with the UBports
  push service (or whatever transport the backend supports). **The only thing the backend
  cares about is the token string** you register in §1.3.
- Coordinate with the backend team on:
  - What `deviceType` / `platformType` values to send for Ubuntu (currently `IOS` /
    `SEREY_WEB`).
  - Whether the Notification Center can deliver to a non-FCM token, or whether a new
    push gateway is needed for Ubuntu Touch.
- Everything else (when to register, guard conditions, logout removal, deep-link routing)
  is platform-agnostic and can be copied directly.

---

## 2. In-app Notification Center Flow

This is a plain authenticated REST feature against the **main API**
(`https://global-api.serey.io`). No push involved — it's the "bell" screen listing the
user's history.

Reference: `SereyIO/Services/Notification/NotificationApi.swift`,
`NotificationService.swift`, `NotificationModel.swift`.

### 2.1 Auth

Uses the **normal Serey user bearer token**: `Authorization: Bearer <userToken>`.

### 2.2 Endpoints

**List notifications (paginated)**
```
GET /api/v2/notification/list-by-current-user-for-serey?offset=0&limit=<n>
Authorization: Bearer <userToken>

→ {
    "data": {
       "notifications": [ <NotificationModel>, ... ],
       ... (pagination metadata)
    }
  }
```
Pagination params (`PaginationRequestModel`): `offset` (default 0), `limit`
(default `Constants.limitPerPage`). Increase `offset` by `limit` to page.

**Mark one notification as read**
```
PUT /api/v2/notification/update-read-by-id/{id}
Authorization: Bearer <userToken>

→ { "notification": <NotificationModel> }
```

### 2.3 `NotificationModel` shape (JSON keys)

```jsonc
{
  "id":               "string",
  "owner":            "string",   // recipient username
  "actor":            "string",   // who triggered it
  "type":             "COMMENT" | "VOTE" | "FOLLOW",
  "is_read":          true,
  "actor_image_url":  "string|null",
  "created_at":       "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
  "updated_at":       "string|null",
  "information": {
     "comment_id":            "string|null",
     "description":           "string",
     "post_author":           "string|null",
     "post_permlink":         "string|null",
     "commented_on_author":   "string|null",
     "commented_on_permlink": "string|null",
     "voted_on_author":       "string|null",
     "voted_on_permlink":     "string|null",
     "post_thumbnail":        ["string", ...] | null
  }
}
```

### 2.4 Display / behaviour rules (from iOS)

- **Message text** is built client-side from `type` + `actor` (localized):
  - `COMMENT` → "{actor} commented on your post"
  - `VOTE`    → "{actor} voted on your post"
  - `FOLLOW`  → "{actor} started following you"
- `type` of `COMMENT` or `VOTE` is considered a **post-related** notification (`isPost`);
  tapping it should open the referenced post (use `post_author` / `post_permlink`, or the
  `commented_on_*` / `voted_on_*` fields). `FOLLOW` should open the actor's profile.
- Thumbnail = first element of `information.post_thumbnail`.
- Avatar = `actor_image_url`, with a colored letter-placeholder fallback derived from the
  username when null.
- Relative time string is computed from `created_at`.
- When a notification is opened/tapped, call **mark-as-read** (§2.2) and update the unread
  badge.

### 2.5 How the two flows connect

When a **push** arrives in the foreground, iOS fires an internal `notificationRecived`
event; the Notification Center screen listens and **re-fetches the list** (§2.2) so the
new item and unread badge appear. That is the only coupling between the two systems —
otherwise they are independent.

---

## 3. Quick checklist for Ubuntu Touch

Push:
- [ ] Acquire a device push token via the Ubuntu/UBports push transport.
- [ ] On login (and token refresh, and app-active), if authenticated + notifications
      enabled: service-login (§1.3 A) → `createToken` (B) → fall back to `updateToken`
      (C) on `responseCode == 1`.
- [ ] On logout / disable: `removeToken` (D).
- [ ] On received push: foreground → refresh list/badge; tap/background → deep-link route.
- [ ] Confirm `deviceType`/`platformType` values + delivery transport with backend.

In-app center:
- [ ] `GET list-by-current-user-for-serey` with `offset`/`limit`, user bearer token.
- [ ] Render via the `NotificationModel` mapping (§2.3) + message rules (§2.4).
- [ ] `PUT update-read-by-id/{id}` on open; maintain unread badge.
- [ ] Re-fetch on the in-app "notification received" signal from the push layer.

---

### Source references (iOS)
- Push token lifecycle: `SereyIO/APNS/APNSHandler.swift`,
  `SereyIO/Helpers/Store/User/APNSTokenStore.swift`,
  `SereyIO/APNS/Handlers/FireBaseHandler.swift`
- Push backend contract: `SereyIO/Services/Push/PushApi.swift`,
  `SereyIO/Services/Push/PushService.swift`
- In-app center: `SereyIO/Services/Notification/NotificationApi.swift`,
  `NotificationService.swift`, `SereyIO/Models/Notification/NotificationModel.swift`
- Base URLs: `SereyIO/Constants.swift` (`apiEndPoint`, `notificationCenterUrl`),
  `SereyIO/App/Configs/*.xcconfig` (`API_URL`, `NOTIFICATION_URL`)
</content>
</invoke>
