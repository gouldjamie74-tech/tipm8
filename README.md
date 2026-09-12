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
