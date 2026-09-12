# TipM8 — COS tipping log

Single-file app: everything lives in `index.html` (markup, styles, script). No build step, no dependencies.

## Run locally
Open `index.html` in a browser, or in VS Code use the Live Server extension (right-click → Open with Live Server).

## Deploy to Netlify
- Drag the `tipm8` folder onto app.netlify.com/drop, or
- Push this folder to a repo and connect it in Netlify. `netlify.toml` sets publish dir to `.` with no build command.

## Notes
- Data is saved in the browser's local storage on each device (key `tipm8.v1`). Export CSV to get it off the device.
- Ore sources are listed in `ORES` near the top of the script — edit names or colours there.
- Keyboard: space logs a tip, 1–4 picks the ore source.
