i87# TipM8 — COS tipping log

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
1–4 pick the ore source. The shift clock starts on the first tip, measured from the
changeover rather than from the tip.

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

**Tips per hour, rolling against required.** Tonnes per hour has to be divided by a
payload in your head before it means anything standing on the pad, so the same pace is
also given in tips: the rolling rate over the last 30 minutes, beside the rate needed from
here to still land on the shift goal. The rolling figure turns amber the moment it drops
under what is required, so being behind is visible without doing the arithmetic. The
watcher's dashboard carries the same pair, and both read from one function, so the pad and
the dashboard cannot disagree about whether the shift is behind.

Required rises as you fall behind, because it is what it takes *from here* — not a flat
target. Once there is no plan left to catch up over it falls back to the flat target rate,
which is the only sensible answer at that point. Counted from the loads in the window
rather than converted from tph, so correcting a tonnage in the load log cannot drag the
rate away from the actual count. It needs five minutes of shift before it will show a
rate at all, and a target before it will show anything to judge against.

**Mill readings.** The COS pad has a *Tipped against milled* section at the head of the
right-hand column: a row for each hour of the shift, where the operator records the mill's
t/h once the hour closes. Blank clears an hour. The shift figure is the **average of the
hourly readings**, shown beside their **total**; an hour's reading is also that hour's
tonnes, which is why the two agree. Beside each reading sits what was tipped to the COS in
that same hour, the difference, and the running difference — which is what the COS
stockpile built or gave up. A closed hour with nothing recorded is marked *due*, and the
by-hour chart carries the average as a dashed line.

Hours run on the clock, as the plant reports them and the paper sheets record them: Day
06:00 to 18:00, Night 18:00 to 06:00. That is half an hour ahead of the 06:30 changeover,
deliberately — each of a shift's twelve hours has closed before that crew hands over, so the
crew that saw an hour is the crew that enters it. It does mean the first hour's tipping only
counts from 06:30, since the half hour before belongs to the previous shift's log.

**Tipping is only ever compared over the hours that have a reading.** Record three hours
and the comparison is tipped t/h over those three hours against the mill's average over the
same three, so a half-filled column cannot manufacture a stockpile, and a shift with eight
readings compares fairly with one that has twelve. The same rule holds on the dashboard, in
shift history and in the CSVs.

Milled figures are written to the pad first and queued, exactly like tips, so a dropped
signal costs lag rather than numbers. They send through their own call, `sync_milled`, so a
problem there can never hold up logging. Only the hours actually touched are sent, which
means a pad with nothing to say cannot wipe hours another pad entered.

The watcher's dashboard carries mill t/h average, milled total, tipped t/h over the same
hours and COS stock in the live row, the previous shift's mill average and total, and the
same by-hour and running-total charts. Previous shifts gains *Mill t/h*, *Milled t* and
*COS stock* columns — an average covering fewer than twelve hours says how many — three new
trends, *Mill t/h*, *Milled t* and *Tipped vs mill t/h*, and a mill section in each shift's
detail view and CSV. The ROM pad does not see any of it.

**Previous 24 hours.** Under the previous shift, the watcher's dashboard carries the last full
production day — a Day shift and the Night shift that follows it, 06:30 to 06:30 — which is
always the day before the shift running now, so during the night of the 17th it is still the
16th. Tonnes, loads, t/h over the 24 hours, delay, mill t/h average and total, and COS stock,
with a line splitting it by shift and saying how many of the 24 hours the mill covers. A
shift nobody logged says *not logged* rather than counting as zero. It is fetched on its own,
so the date filter on Previous shifts cannot hide it.

**Corrections.** Tap any row in the load log to fix its time, tonnage or ore source.
Loads re-sort by time after an edit, so intervals and charts stay honest. Undo last tip
drops the most recent one.

**Shifts.** Shifts change over on their own at **06:30 and 18:30**. The shift on the
deck is closed at the changeover instant rather than whenever the app next woke up, filed
into Previous shifts with its tonnes, both tph figures, delay total and ore split, and a
new shift opens stamped with the changeover time. Fleet settings carry over. Nobody has
to remember a tap: the changeover fires from the clock tick, from the next tip, and when
a sleeping device wakes, so an iPad left in a pocket across 18:30 catches up on unlock.

Anything stamped after the changeover moves across to the new shift rather than being
counted against the old one, and a delay still open at the boundary is closed on the old
shift and reopened on the new one, so neither shift is credited with the other's time.

There is no End shift, New shift or Start shift clock any more. With the changeover closing
and opening shifts on its own they could only do harm: on 17 Sep End shift followed by New
shift left a live shift marked as ended, freezing the dashboard, and a pad left on an ended
shift refuses tips until the next changeover — up to twelve hours. A pad that ended its
shift before the buttons went reopens it on load if it is still inside that shift's window.

## Data
Saved in the browser's local storage on each device (key `tipm8.v1`) — it survives a
refresh, but it is per-device and per-browser, and clearing site data wipes it.

- **Backup JSON** writes the whole store — current shift, delays, fleet settings and
  shift history — to a file. **Restore JSON** reads one back, replacing what is on the
  device. That is the way to move a log between devices.
- **Export CSV** gives one row per load, then the delay log, then a shift summary row.
  This one is the current shift on *this* device, from local storage.

### Getting shifts out as CSV
For anyone who wants the numbers outside the app, Previous shifts exports from the shared
log rather than from one device, so any shift can be pulled from any device — including
one that never logged it.

- **CSV** on a shift's row gives that shift in full: both parties' loads interleaved in
  time, each with its party, sequence, ISO timestamp, local time, ore, tonnes, interval,
  running total, fleet counts and the device that logged it. Then the delay log, then a
  summary per party with the ROM-less-COS gap. Sequence, interval and running total are
  counted **per party**, so a ROM row's interval is the time since the previous *ROM*
  load, not since whatever happened to be logged in between.
- **Export these shifts** gives one row per shift across whatever the date filter is
  showing — hours, loads, tonnes, tph, delay, ROM and COS tonnes, gap and ore split. That
  is the one for trending a month; the per-shift export is the one for auditing a shift.

Files land as `tipm8-2026-09-14-day.csv` and `tipm8-shifts-<from>-to-<to>.csv`, so they
sort by date on their own. `timestamp_iso` is the authoritative column; the `time` column
beside it is local to whichever device did the export, for reading rather than for maths.

## Live sync and the two portals

Local storage is per device, so sharing a shift needs a backend. TipM8 uses a Supabase
project (`TipM8`, ap-southeast-1) with three tables — `shifts`, `loads`, `delays`.

Two parties log the same trucks from opposite ends of the haul: mine geology as material
leaves the ROM pad, process operations as it tips at the COS. Both write to one shift and
the gap between them is reconciled. Each device picks a role from the toggle in the page
header, and **Watching is the default**:

- **ROM pad** — mine geology's portal. The button reads Load, totals read as dispatched.
- **COS** — process operations' portal. The button reads Tip, totals read as delivered.
  Only one device per party should be logging; nothing enforces that.

`?party=rom` and `?party=cos` set the role from the URL, so each device can be set up
from a bookmark rather than a menu. The bookmark asks for the passcode too — otherwise
the passcode would be one URL away.
- **Watching** — a dashboard rather than the logger's screen, read only, polling every 8
  seconds while the tab is visible. The device's own log is parked while it watches and
  comes back when you pick a logging role again.

### There is no Off any more
There used to be a fourth role, Off, which logged to the device and never synced. It was
the default, and it was a trap. A pad whose storage is cleared comes back with no role
stored, so it fell to Off — and on Off the sync strip was hidden, so the screen looked
identical whether the shift was reaching the shared record or going nowhere. On the
morning of 16 Sep an operator logged for ninety minutes into a device that was doing
exactly that.

Nothing was lost — the loads were on the device and went up the moment COS was picked —
but nobody could see them, and nobody could have known why.

Off is gone. A fresh or cleared device opens on **Watching**: read only, visibly doing
nothing, rather than invisibly doing nothing. Logging is now a deliberate act — pick a
party, enter the passcode. A device that was on Off keeps its log; it opens on Watching
with that log parked, and picking a logging role hands it straight back.

Off was never needed for working without signal, which is what people assume it was for.
A logging role writes to the device first and queues, and says so in the status line.

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

Sync is one function call, `sync_party`, which upserts a party's shift, loads and
delays and prunes what that device deleted locally, in one transaction. Loads and delays
carry client-generated UUIDs so a retry can never double up a tip. Watchers call
`active_shift`, which returns the newest shift with its loads and delays, plus a summary
of the shift before it, in a single round trip.

`active_shift` orders by `started_at desc` and nothing else. It used to prefer a shift
with no `ended_at`, which meant any shift left unclosed outranked every newer finished
one and quietly served days-old numbers to every watcher. Newest started always wins now;
shifts are keyed on date and Day/Night, so an older open shift is always a leftover.

Finished shifts are read back from the database with `shift_summaries(site, from, to,
limit)`, so a watching device that has logged nothing still sees the history. The
Previous shifts table takes a From and To date, reports loads, tonnes, tph, delay and the
ROM/COS gap per shift, and falls back to this device's own log when the page is offline
or set to Off — the note under the date boxes says which of the two you are reading.

### Looking back
The trend chart plots **tonnes, tph, loads or delay** across the shifts in view, picked
from the Trend box. Day and night are drawn in different colours and never merged: they
are different crews on different rates, and a trend that blends them hides the comparison
worth making.

**View** on any row opens that shift — headline tonnes, count, tph, tph with delays
excluded, utilisation and delay, then its **tonnes by hour**, its ore split and its delay
log. The hourly profile is the useful part: a shift average tells you a night was slow,
the profile tells you which two hours it happened in. Each hour is judged against the
target tph, since an hour's tonnes is that hour's rate; the target line is only drawn when
it fits on the scale, and the legend says so rather than claiming a line that is not there.

It reads through `shift_detail(id)`, the same call the CSV export uses, so a shift can be
opened from a device that never logged it — which is the point for anyone going over last
night from the office in the morning.

### Shifts and reconciliation
A shift is keyed on site, date and Day/Night — Day is 06:30 to 18:29 local and Night
18:30 to 06:29, with the small hours belonging to the night that started the evening
before. Both parties derive the same key
from their own clock, so neither has to start a shift for the other, and a device whose
storage is cleared rejoins the shift it left instead of forking a new one.

**A shift inherits its settings from the shift before it**, and a device that is not
contributing rows cannot overwrite them. Both come from the same morning: a wiped pad came
back carrying factory defaults, synced an empty shift, and zeroed the target tph for
everyone, because the upsert took the last writer's settings unconditionally. The rule now
is that a device's payload, fill, fleet, target and shift hours are written to the shift
only if that device is actually putting loads or delays into it. Otherwise the shift keeps
what it has, and a brand new shift starts from the previous one rather than from whatever
the first device to sync happened to be carrying.

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

### Where the database lives
Most of the schema is not in this repo — it was built migration by migration against the
Supabase project, which is its own source of truth and keeps its own history, newest last:

    tipm8_initial_schema                       tables
    tipm8_rls_policies
    tipm8_sync_function
    tipm8_active_shift_reports_contenders
    tipm8_two_party_reconciliation             rows carry party and device
    tipm8_prune_scoped_to_device
    backup_schema_for_deleted_shifts           backup.deleted_shifts, outside public
    active_shift_newest_started_wins           newest started_at wins, not newest unclosed
    shift_summaries_and_prev_shift             shared history, and prev on active_shift
    shift_detail_for_csv_export                one shift in full, both parties
    shift_start_anchored_to_changeover         a shift starts at 06:30/18:30, not first tip
    shift_settings_inherit_and_stop_clobber    a silent pad cannot overwrite settings
    loads_cannot_be_hijacked_across_parties    a load id belongs to the party that made it

From milled tonnes onward, migrations are also kept in `sql/`, because they have to be
applied by hand whenever the database connection is not available to whoever wrote them:

    sql/2026-09-17_milled_tonnes.sql           milled table, sync_milled, milled on the reads
    sql/2026-09-17_load_corrections.sql        corrections that stick; a live shift can't stay ended

Each one is safe to run twice. Paste it into the Supabase SQL editor and run it. Until
`2026-09-17_milled_tonnes.sql` has been applied the page still works: the COS pad keeps
milled figures on the pad and queues them, says the shared log is not taking them yet, and
sends them once it is; watchers show a dash rather than a zero.

To read what is actually deployed rather than trusting this file:

    select pg_get_functiondef(p.oid) from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('active_shift','sync_party','sync_milled','shift_summaries','shift_detail');

`backup.deleted_shifts` holds shifts removed by hand, as a JSON blob per shift. It sits
in a `backup` schema rather than `public` on purpose: PostgREST only exposes `public`, so
nothing there is reachable with the publishable key.

**Correcting a load from the office.** The pad owns its rows and re-sends its own copy of
every load on each sync, so a plain edit here lasts only until the next tip. Set
`loads.corrected_at = now()` alongside the change instead: `sync_party` then keeps that
row's time, ore and tonnage while the pad is still sending the old ones, the page adopts
the correction into the pad's own log on its next poll, and the mark clears itself the
first time the pad's copy matches — after which the pad owns the row again. First used on
17 Sep to spread thirteen catch-up loads, tapped in 33 seconds at 07:28, back across the
unattended hour from 06:30.

**A live shift cannot stay ended.** End shift followed by New shift used to leave the
shift marked as ended while trucks kept tipping into it, freezing elapsed on the dashboard.
A pad contributing loads or delays now sets or clears the end time; a silent pad still
cannot touch it.

Deleting a shift from the database does not make it stay deleted. A device that still
holds that shift as its current shift re-sends it on the next sync and `sync_party`
recreates it, new row id and all. Move the device off the shift first — a changeover does
this on its own now — and delete afterwards.

### Access
Watching is open; logging is not. Choosing **ROM pad** or **COS** asks for a four-digit
passcode, so the link can be handed to anyone who needs to watch a shift without them
being able to write trucks into it. Off and Watching never ask. A wrong code changes
nothing — the device stays on whatever role it already had.

The passcode is `LOG_PIN` near the top of the script, next to `ORES` and `REASONS`, and
ships as `1234`. Change it there and redeploy; every device picks it up on next load.

**Be clear about what that does and does not stop.** It stops a wrong tap and a borrowed
iPad. It is not a security boundary: the code sits in the page source, like the Supabase
publishable key beside it. Anyone willing to read the source or call the API directly can
still write, because the database itself still accepts writes from anyone holding that
key — every RLS policy on the three tables is `true` for `anon`, which also holds direct
INSERT, UPDATE, DELETE and TRUNCATE grants.

So **the site must stay behind the Netlify site password**, which is the only real gate.
Turn it on under Project configuration → Access & security → Visitor access → Password
protection. Nothing else in the project is exposed by that key — no auth, no schema, no
other tables.

Making watch-only genuinely enforced would mean moving the check into the database:
revoke `anon`'s table grants, make the three functions `SECURITY DEFINER`, and have
`sync_party` require a token the watching devices do not hold. Then the publishable key
would be read-only by construction. That has not been done.

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
- Charts are hand-rolled SVG; there is no charting library to update. Hover over any chart —
  or tap it on the pad — for the values at that point: each chart lays invisible full-height
  columns over its plot (one per block, load, hour or shift) built with `tipCols`, or
  `tipNearest` for a line through unevenly spaced points, and one shared tooltip follows the
  pointer. A new chart gets the same by adding columns before its closing `</svg>`.
