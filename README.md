# TipM8 — COS tipping log

Truck tipping log and rate tracker for the ROM pad. Tap a button each time a truck tips
to the COS, log the delays in between, and watch the shift rate against target.

Everything the app does lives in `index.html` (markup, styles, script). No build step,
no dependencies. The other files only exist to make it installable and offline-capable.

## Run locally
Open `index.html` in a browser, or in VS Code use the Live Server extension
(right-click → Open with Live Server). Service worker registration is skipped on
`file://`, so install and offline only kick in once it is served over http(s).

## Deploy to Netlify
- Drag the project folder onto app.netlify.com/drop, or
- Push it to a repo and connect it in Netlify. `netlify.toml` sets publish dir to `.`
  with no build command.

## Using it

**Tipping.** The amber button logs one truck tip at `payload × fill factor` tonnes,
stamped with the ore source and the fleet counts running at the time. Space bar tips,
1–4 pick the ore source. The shift clock starts on the first tip if it is not already
running.

**Delays.** Tap a reason chip — No trucks, Crusher, Screen, Loader down, Blast, Weather,
Shift change, Meal, Other — to open a delay. It runs a clock until you end it, and
logging a tip closes it automatically, on the grounds that the delay is over once
material moves again. Delay time is subtracted from elapsed time to give:

- **tph, delays excluded** — the rate the operation actually ran at
- **utilisation** — operating time over elapsed time
- **t forgone** — each delay's length priced at the operating rate

**Pace.** Set shift hours (default 12) and, optionally, a target tph. The bar under the
stats shows how far through the shift you are; beside it, projected end-of-shift tonnes
at the current operating rate, and the tph needed from here to land on target — green if
the projection clears the goal, amber if it does not.

**Corrections.** Tap any row in the load log to fix its time, tonnage or ore source.
Loads re-sort by time after an edit, so intervals and charts stay honest. Undo last tip
drops the most recent one.

**Shifts.** End shift stops logging and closes any open delay. New shift files the
finished one into Previous shifts with its tonnes, both tph figures, delay total and ore
split, then clears the deck. Fleet settings carry over.

## Data
Saved in the browser's local storage on each device (key `tipm8.v1`) — it survives a
refresh, but it is per-device and per-browser, and clearing site data wipes it.

- **Backup JSON** writes the whole store — current shift, delays, fleet settings and
  shift history — to a file. **Restore JSON** reads one back, replacing what is on the
  device. That is the way to move a log between devices.
- **Export CSV** gives one row per load, then the delay log, then a shift summary row.

## Live sync and the two portals

Local storage is per device, so sharing a shift needs a backend. TipM8 uses a Supabase
project (`TipM8`, ap-southeast-1) with three tables — `shifts`, `loads`, `delays`.

Two parties log the same trucks from opposite ends of the haul: mine geology as material
leaves the ROM pad, process operations as it tips at the COS. Both write to one shift and
the gap between them is reconciled. Each device picks a role from the toggle in the page
header, and Off is the default:

- **Off** — the device keeps its log to itself. Behaves exactly as it did before sync.
- **ROM pad** — mine geology's portal. The button reads Load, totals read as dispatched.
- **COS** — process operations' portal. The button reads Tip, totals read as delivered.
  Only one device per party should be logging; nothing enforces that.

`?party=rom` and `?party=cos` set the role from the URL, so each device can be set up
from a bookmark rather than a menu.
- **Watching** — a dashboard rather than the logger's screen, read only, polling every 8
  seconds while the tab is visible. The device's own log is parked while it watches and
  comes back when you switch off.

The watcher's dashboard leads with rate, because that is what someone glancing at it
needs first: tph over the last 30 minutes, shift average, tonnes to COS and the target,
sized to be read across a room and coloured green or amber against target. Under that
sits the pace bar and projection, then loads, elapsed, time left, operating tph,
utilisation, delay total and time since the last tip. The ore split, charts, load log and
delay log follow underneath unchanged.

A banner above the numbers calls out the thing worth interrupting someone for:

- **Delayed** — a delay is open, with its reason and a running clock
- **No tip** — nothing logged for over 15 minutes with no delay recorded, which usually
  means a delay nobody opened
- **Check** — more than one device is Logging. The watcher follows whichever shift started
  most recently, and says so rather than quietly picking one

The status dot goes amber and reports the age of the last successful poll if updates stop
for 30 seconds. Numbers that have quietly gone stale are worse than numbers that admit
it.

**It never blocks on the network.** A tip is written to local storage first and queued
for sending. If there is no signal the queue holds, the status line says so, and it
drains when the connection returns. A dropped signal costs lag, not data.

Sync is one function call, `sync_shift`, which upserts the shift and its loads and
delays and prunes anything deleted locally, in one transaction. Loads and delays carry
client-generated UUIDs so a retry can never double up a tip. Watchers call
`active_shift`, which returns the running shift — or the most recent finished one — with
its loads and delays in a single round trip.

Shift history stays on the device that logged it. Watchers see the live shift only.

### Shifts and reconciliation
A shift is keyed on site, date and Day/Night — 06:00 to 18:00 local, with the small hours
belonging to the night that started the evening before. Both parties derive the same key
from their own clock, so neither has to start a shift for the other, and a device whose
storage is cleared rejoins the shift it left instead of forking a new one.

`sync_party` upserts a party's rows and prunes what that **device** deleted locally. The
device scope matters: pruning by party alone meant a replacement iPad with an empty local
log would sync and delete everything the real device had recorded.

Reconciliation reads both streams back from the database rather than from local storage,
so a portal with an empty local log still reconciles against everything already recorded.
It reports loads and tonnes per party, the gap, and the gap per ore source, with the two
cumulative curves plotted together — where they separate is when the gap opened.

There is no truck number to pair on, so this is aggregate reconciliation: it tells you
the ROM pad logged three more loads than the COS and that all three were Kopra, not which
three trucks. A standing gap is normal, since trucks are always on the haul road; a gap
that keeps growing means taps are being missed. Both parties compute tonnes the same way,
from payload × fill held on the shift and shared between them, so tonnage variance is
load-count variance restated rather than an independent measurement.

### Access
The Supabase publishable key ships in the page, as it is designed to. It is not the
gate: anyone holding it can read and write these three tables, so **the site must stay
behind the Netlify site password**. Turn it on under Project configuration → Access &
security → Visitor access → Password protection. Nothing else in the project is exposed
by that key — no auth, no schema, no other tables.

## Offline and install
`manifest.webmanifest` plus `sw.js` make the page installable to an iPad or phone home
screen and keep it working with no signal. The service worker is network-first, so a
redeploy lands as soon as there is signal, and falls back to cache when there is none.
Google Fonts are cached after the first online load; without them the app falls back to
system fonts and still works.

Bump `CACHE` in `sw.js` if you ever need to force every device to drop its cached copy.

## Notes
- Ore sources are listed in `ORES` near the top of the script — edit names or colours
  there. Delay reasons are in `REASONS` just below.
- Charts are hand-rolled SVG; there is no charting library to update.
