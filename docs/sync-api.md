# Sync API

The protocol DueBar clients speak to the sync server, so another client (the planned Android app) can implement it. The server is a separate private project; it never looks inside the entity payloads described below.

All bodies are JSON over HTTPS. Authenticated calls send `Authorization: Bearer <token>`.

## Sign-in

`POST /v1/auth/google` with `{ "idToken": "<Google ID token>" }` returns `{ "token": "...", "user": { "email", "name", "picture" } }`.

- The client signs in with Google (OAuth, PKCE; desktop uses a loopback redirect) requesting only the `openid email profile` scopes, and sends the resulting **ID token**. Google's access and refresh tokens are never kept.
- The server accepts the token only if its audience is one of its configured OAuth client IDs (one per platform: macOS, Android, ...).
- `token` is the server's own opaque session token. It lasts 180 days and renews while in use. A `401` on any call means the session is gone: sign in again.

Other calls: `GET /v1/me` (the profile above), `POST /v1/logout`, `DELETE /v1/account` (removes the account and every synced record immediately).

## Sync

`POST /v1/sync` with `{ "cursor": <int>, "changes": [Record] }` returns `{ "cursor": <int>, "more": <bool>, "accepted": <int>, "changes": [Record] }`.

1. Push every record changed locally since it was last acknowledged (`changes`, up to 5000), and send the `cursor` from the previous reply (0 on a fresh device).
2. The reply holds up to 1000 records stored after that cursor. Apply them, keep the new `cursor`, and repeat while `more` is true.
3. A pushed record is stored only if its `updatedAt` is newer than the stored one, so the newest write wins per record. The reply may include records the client just pushed; applying them is harmless.
4. Mark a pushed record as synced only if it did not change again while the request was in flight.

```
Record = {
  "kind": "payment" | "event",
  "id": string,
  "updatedAt": int,        // milliseconds since 1970, client clock; strictly increases per record
  "deleted": bool,         // tombstone; "data" must then be null
  "data": string | null    // the entity as a JSON string
}
```

A client should make each write strictly newer than the version it replaces (`max(now, previous + 1)`), so two edits in the same millisecond, or a clock that stepped back, never lose.

## Entities (the `data` JSON)

Dates are calendar days without a time zone (`"2026-11-13"`): a bill due on the 5th is due on the 5th wherever you are. Money is a decimal **string** (`"1250000.50"`), never a float. Times are milliseconds since 1970.

**payment**

| field | type | |
|---|---|---|
| `id`, `name` | string | |
| `amount` | string | decimal |
| `currency` | string | ISO code, e.g. `IDR`, `USD` |
| `category` | string | `utilities` `internet` `subscription` `rent` `loan` `insurance` `tax` `credit` `education` `other` |
| `startDate` | day | first due date of the current series |
| `repeatRule` | object | `{ "unit": "none"\|"day"\|"week"\|"month"\|"year", "interval": int, "end": { "type": "never" } \| { "type": "date", "date": day } \| { "type": "count", "count": int } }` |
| `resolvedCount` | int | occurrences of the series already paid or skipped |
| `reminderOffsets` | [int] | days before the due date; `0` = on the day |
| `reminderMinute` | int | minutes after midnight |
| `notes`, `url` | string | |
| `paused`, `archived` | bool | |
| `createdAt` | int | ms |

The next due date is occurrence number `resolvedCount` of the series, always computed from `startDate`, not from the previous occurrence, so a monthly bill on the 31st goes Jan 31 → Feb 28 → Mar 31 (`Sources/DueKit/Recurrence.swift`).

**event** (history of one resolved occurrence)

| field | type | |
|---|---|---|
| `id` | string | `"<paymentId>_<dueDate>"`, so resolving the same occurrence on two devices collapses into one record |
| `paymentId`, `name` | string | |
| `kind` | string | `paid` or `skipped` |
| `dueDate` | day | |
| `amount`, `currency`, `category` | | as in payment |
| `resolvedAt` | int | ms |

Deleting a payment writes tombstones for the payment and for each of its events.
