# Star Squad ⭐

A single-page reward chart for kids. Tap a chore to earn stars, watch the
scoreboard and confetti celebrate it, then cash stars in for prizes. Built as
one static HTML file with no backend — all progress is saved locally in the
browser (`localStorage`), with a manual backup/restore option for moving data
between devices.

## What it does

- **Multi-kid scoreboard** — tap a name to switch whose turn it is; each kid has
  their own point total, goal, and progress bar, with a crown shown for
  whoever's ahead.
- **Task grid** — tap an emoji tile (brush teeth, get dressed, tidy toys,
  etc.) to mark it done for the day and award points; each task can only be
  completed once per day per kid.
- **Growing pet** — each kid picks a pet (puppy, kitten, butterfly, chick,
  avocado, or tree) that visibly grows through its stages as they earn
  points toward their goal.
- **Bank** — kids can tap the bank icon on their card to stash their current
  points; banked points still count toward prizes but are kept separate
  from the in-progress total shown on the goal bar.
- **Prize shop** — a horizontal row of redeemable prizes that light up once a
  kid has enough points (spending from points first, then the bank);
  redeeming deducts the cost and triggers a celebration.
- **Celebrations** — confetti (canvas-based), a random cheer message, and a
  short WebAudio chime play whenever a task is completed or a prize is
  redeemed.
- **Tweaks panel** (🎛️ icon) — pick a color mood (Peach Cozy, Ocean Calm,
  Berry Pop), an energy level (Playful or Chill, which calms the
  animations), and celebration style (Big or Quiet).
- **Grown-Up Settings** (lock icon) — a parent-only panel to rename/re-emoji
  each kid, change their star goal, adjust points-per-task, and add/edit/
  remove prizes.
- **New Day** — clears which tasks are marked done so kids can start earning
  again, without resetting their point totals.
- **Backup / Restore** — exports the current state (kids, tasks, prizes,
  progress) as a downloadable JSON file, and can re-import it later so
  progress isn't lost if the browser's local storage is cleared.

Everything — layout, styling, and logic — lives in `index.html`; there's no
build step and nothing to install. A small revision tag (e.g. `rev 5 ·
2026-07-09`) is shown under the title and bumped in-file (the `REV` /
`REV_DATE` constants) with each shipped update.

## Changelog

**Rev 5 — 2026-07-09**
- Added a growable pet for each kid to choose from.
- Reworked the color palette to a calmer, more pastel look (plus alternate
  Ocean Calm / Berry Pop themes via the Tweaks panel).
- Added the bank option for saving up points.
- Added the in-app revision tag.
- Fixed a stored-XSS hole in `esc()`: it escaped `<`, `>`, and `&` but not
  quote characters, so a kid name, task, or prize field (including one
  loaded via **Restore**) containing a `"` could break out of an `value="..."`
  attribute in the Grown-Up Settings modal and inject a live event handler.
  `esc()` now escapes `"` and `'` as well.

## Privacy note

This repo is public, so `index.html` ships with generic placeholder names
(`Kid 1`, `Kid 2`) rather than real ones. Set actual names via **Grown-Up
Settings** (the lock icon) after opening the app — that write goes only to
the browser's `localStorage` on that device, never back into this repo.
Don't hardcode real names into `index.html`.

## Files

| File | Purpose |
|---|---|
| `index.html` | The entire app: markup, styles, and JavaScript logic (state, rendering, confetti, sound) in one file. |
| `staticwebapp.config.json` | Azure Static Web Apps routing config — falls back to `index.html` for any unmatched route (so this single-page app works on refresh/deep links), and sets caching/MIME-type behavior. |

## Deployment

This app is deployed to Azure Static Web Apps by the
[`static-web-app-deploy.yml`](../../.github/workflows/static-web-app-deploy.yml)
workflow whenever a change lands under `apps/star-squad/**` on `main` (or the
workflow is run manually). See
[`Patterns/common/static-web-app/README.md`](../../Patterns/common/static-web-app/README.md)
for how the underlying Azure resources are provisioned.
