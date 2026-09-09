# Gnog Schedules

A private period & medication calendar for Chesa. No account, no tracking, no ads —
all health data stays on the phone.

## What it does

- **Today** — hero card with pill-pack progress ring, period status and medication
  streak; tap-to-check medication lists (8:00am: prebiotic, probiotic, iron /
  1:30pm: Liza on active pill days, Lexapro, Abilify); flow / mood / note logging.
- **Calendar** — month view with period, predicted-period and logged-mood markers;
  tap any day for detail and to mark/remove period starts.
- **Pack** — visual 28-day pill strip (21 active + 7 placebo), fully editable anchor
  (shift days, start a new pack today). Shows a sync code to keep reminders aligned.
- **Insights** — cycle history, average cycle/period length, mood frequency by phase.
- **Settings** — medication & reminder-time editor, push-notification setup,
  JSON/CSV export, JSON restore.

## The two halves

| Half | Where | Notes |
|---|---|---|
| PWA (`index.html`, `css/`, `js/`, `sw.js`) | GitHub Pages: `marcustayye93/gnog-schedules` | Installable, offline-first, receives pushes |
| Push sender (`~/workspace/gnog-push/`) | This machine (crons) | Sends the daily 8:00am / 1:30pm reminders via Web Push |

Notifications are **Web Push** (iOS 16.4+ supports it for Home-Screen PWAs).
The PWA cannot schedule local notifications itself, so a small sender on this
machine fires them. The sender stores only the push subscription + pack anchor —
never health logs.

## Push plumbing (for maintainers)

- VAPID keys: `~/workspace/gnog-push/vapid_private.pem` (600) + `vapid.json`
  (public key; the public key is also baked into `js/app.js` as `VAPID_PUBLIC_KEY`).
- `send_push.py <morning|afternoon>` — computes today's pack phase from
  `config.json`'s `packAnchor` and sends a phase-aware reminder.
  Exits quietly when `subscription.json` doesn't exist yet.
- `add_subscription.py 'GNOGPUSH:<code>'` — stores the subscription Chesa pastes
  from the app's Settings → Enable reminders flow.
- Crons `nog-morning-meds` / `nog-afternoon-meds` (Asia/Singapore) run the sender.
  They are owned by the tracked item `goal:gnog-schedules-medication-reminders`.
- If Chesa changes her pack schedule in-app, she pastes the new `PACK:YYYY-MM-DD`
  sync code into chat → update `config.json`'s `packAnchor`.

## Native iOS app (future)

`ios/` holds the complete SwiftUI + SwiftData + WidgetKit + HealthKit app source
(same feature set, plus widgets, lock-screen widgets and Apple Health sync).
It needs a Mac with Xcode and an Apple Developer account to build & ship via
TestFlight / App Store. See `ios/README.md`.

## Deploy

Pushing to GitHub requires the `gnog-schedules` repo to exist (the deploy PAT
cannot create repos). Once created with Pages enabled (branch `main`, root):

    python3 /tmp/publish-nog.py

After changing CSS/JS, bump the `?v=` query strings in `index.html` and the
`SHELL` list + `CACHE` name in `sw.js` so installed copies update.
