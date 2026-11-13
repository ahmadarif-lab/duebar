# DueBar

A macOS menu bar app that reminds you of payments before they're due: bills, subscriptions, installments, insurance, taxes. Local-first, with optional Google sign-in to keep your data in sync across devices (an Android app is planned on the same API).

<p align="center"><img src="Resources/AppIcon.png" width="128" alt="DueBar icon"></p>

## What it does

- **Menu bar at a glance**: just the logo with a red badge counting what is overdue, due today, or inside its reminder window (a payment with reminders at 1, 2 and 7 days counts from 7 days before). Everything else stays under View All.
- **Dropdown**: leads with *Total Outstanding* as one number in your main currency, then the few payments that are due soon (numbers first, no icons). *View All* opens every payment grouped as Overdue / Today / This week / Later, plus the history. Hover a row for *Mark as paid*; the ⋯ menu has *Skip this time*, *Open payment link*, *Pause*, *Edit* and *Delete*, and every payment can be undone.
- **One total in your main currency**: pick a main currency (say IDR) and payments in USD or others are converted at the daily rate from [ExchangeRate-API](https://www.exchangerate-api.com); the rates are only fetched while a payment uses another currency.
- **Payments**: name, amount and currency, category, due date, notes, a payment link, and reminders.
- **Repeat**: daily, weekly, monthly, every 3 or 6 months, yearly, or custom (every N days/weeks/months/years), ending never, on a date, or after N payments. Monthly bills on the 29th–31st keep their day (Jan 31 → Feb 28 → Mar 31).
- **Reminders**: local notifications N days before and on the day, at a time you choose, with *Mark as paid* and *Remind in 1 hour* buttons. Late payments are nudged each morning for three days.
- **Manage everything from Settings → Data**: search, add, edit, pause, mark paid or delete payments, browse finished ones and the history, and export CSV or back up and restore JSON.
- **Themes** (System, Light, Dark), English and Bahasa Indonesia, start at login.

## Sync

Sign in with Google (Settings → Account) to sync across devices. Without signing in, nothing ever leaves the Mac.

```
DueBar (macOS) ──┐                          ┌── Google (ID token verified server-side)
                 ├── HTTPS ── sync API ─────┤
Android (later) ─┘   POST /v1/sync          └── PostgreSQL
```

- The app signs in with the system browser (OAuth PKCE on a loopback redirect), then trades Google's ID token for its own session. Google's access and refresh tokens are never stored.
- Every record carries an `updatedAt`; the newest write wins per record. Deleting leaves a tombstone, and marking the same occurrence paid on two devices collapses into one history entry.
- Dates are calendar days without a time zone, so a bill due on the 5th is due on the 5th wherever you are. Money travels as decimal strings.
- *Delete my account and cloud data* removes everything on the server.

The wire protocol is documented in [`docs/sync-api.md`](docs/sync-api.md). The server itself is a separate private project.

## Build

```sh
Scripts/run_dev.sh                  # debug run (uses ~/Library/Application Support/DueBar-dev)
DUEBAR_GOOGLE_CLIENT_ID=… DUEBAR_GOOGLE_CLIENT_SECRET=… Scripts/build_app.sh   # dist/DueBar.app
swift test                          # model, repeat, merge, parser tests
Scripts/integration_test.sh         # sync tests against the API server (needs a duebar-api checkout, see the script)
```

Without a client ID the app builds and runs fully local; the sign-in button is disabled.

### Google client ID

Create an OAuth client of type **Desktop app** in Google Cloud Console (project's consent screen with the `openid email profile` scopes), then give the same client ID to the server in `GOOGLE_CLIENT_IDS` so it accepts tokens issued for it. Android uses its own client ID, also added to that list.

### Layout

```
Sources/DueKit   Models, repeat rules, ledger merge, agenda, reminder planner, sync client (no UI)
Sources/DueBar   AppKit + SwiftUI app (status item, dropdown, editor, settings, notifications)
Tests/DueKitTests
docs/            Sync protocol
```

`DueKit` has no AppKit dependency; the Android app ports its small set of rules (repeat maths, last-write-wins merge) and speaks the same API.

## License

MIT
