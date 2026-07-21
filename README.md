# Builders vs Behemoth

An asymmetric "cat and mouse" scenario mod for Factorio 2.0: one player is
the lone hunter (the **Behemoth**); everyone else are mutually-allied
**Builders** who hide, build an economy, and defend chokes, then turn and
kill the hunter. The Behemoth's only income is damage dealt to Builder
structures; Builders farm currency from Generators and spend it on Wall/
Turret tiers, while the Behemoth spends its damage-income on combat stat
upgrades and a Scanner Sweep reveal ability. Inspired by the StarCraft II
Arcade mode "Probes vs Zealot 2". See `openspec/changes/core-loop-mvp/` for
the full proposal, design, and task breakdown.

## Status

**MVP, feature-complete for the core loop** (task groups 1-8 of
`core-loop-mvp` are done): mod skeleton, match lifecycle (role selection,
staggered start, win/lose), builder economy (Generator + tiers), builder
defenses (Wall/Turret + tiers + recolor), Behemoth combat (damage income,
stat upgrades, Scanner Sweep), hiding/vision (native fog of war), and the
shop GUI are all implemented end to end.

All game-balance numbers (generator/wall/turret tier costs and outputs,
Behemoth stat costs, head-start delay, Scanner Sweep radius/cooldown, item
recipe costs) are explicit **placeholders** — see each module's `CONFIG`
table and `openspec/changes/core-loop-mvp/design.md`'s "Open Questions" —
to be re-tuned during an actual playtest pass, not final values.

Static validation (JSON + Lua syntax + luacheck) has been done on this dev
machine; **no in-engine testing has happened yet** (no Factorio install
here). See `docs/verification.md` for the full spec-to-code trace and the
checklist of items that specifically need confirming on a running game
(fog-of-war timing, wall collision, turret targeting, GUI rendering,
multiplayer determinism).

## Development environment

This dev machine does **not** have Factorio installed. Authoring and
static checks happen here; runtime testing happens on the actual game or a
headless server.

### Static checks

- **JSON validation** (`info.json`):
  ```sh
  python3 -m json.tool info.json >/dev/null && echo OK
  # or: jq . info.json >/dev/null && echo OK
  ```
- **Lua syntax check** (`luac5.4`, available on this machine): run against
  every Lua file — this catches syntax errors even without a Factorio
  runtime or luacheck:
  ```sh
  find . -name '*.lua' -not -path './openspec/*' -exec luac5.4 -p {} \;
  ```
- **Lua static checks** (`luacheck`): not preinstalled, but installable
  locally without touching system Lua:
  ```sh
  sudo apt-get install -y luarocks
  TMPDIR=~/.cache/tmp luarocks --local install luacheck
  ~/.luarocks/bin/luacheck .
  ```
  `.luacheckrc` declares the Factorio runtime/data-stage globals (`data`,
  `script`, `defines`, `rendering`, `settings`, ...) as read-only, and
  `game`/`storage` as mutable (both are legitimately written through at
  runtime), plus the Factorio-added `table.deepcopy` stdlib extension. As
  of task 8.2 this passes with 0 warnings / 0 errors.

## Installing into Factorio

The Factorio `mods/` folder location depends on OS:

- **Linux**: `~/.factorio/mods/`
- **Windows**: `%APPDATA%\Factorio\mods\`
- **macOS**: `~/Library/Application Support/factorio/mods/`

Steps:

1. Copy (or symlink) this repository into that `mods/` directory under the
   name `builders-vs-behemoth_0.1.0` (matching `info.json`'s
   `name`/`version`), or zip the repo contents (so `info.json` is at the
   zip root) and drop the zip into `mods/` as
   `builders-vs-behemoth_0.1.0.zip`.
2. Enable the mod from the in-game mod list, or via `mod-list.json`.

This ships as a **mod** rather than a bundled scenario (design.md D1):
custom prototypes (Generator/Wall/Turret tiers, the Behemoth's weapon) need
a data stage, which a scenario alone doesn't run. A freeplay surface is
enough to start a match — `scripts/match.lua` handles role selection and
spawning itself in `on_init`/the lobby GUI, no bundled map is required for
the MVP.

## Running on a headless server for playtesting

This is currently the **only** way to actually exercise this mod's
gameplay — see "Status" above and `docs/verification.md` for what still
needs confirming this way.

1. Install/copy the mod into the headless server's `mods/` directory as
   above.
2. Generate a save with the mod enabled:
   ```sh
   ./factorio --create ./saves/bvb.zip
   ```
3. Start the headless server against that save:
   ```sh
   ./factorio --start-server ./saves/bvb.zip
   ```
4. Connect with regular Factorio clients (same mod version required) — at
   least two players total, so one can volunteer as (or be randomly
   assigned) the Behemoth and at least one other as a Builder — to
   playtest the asymmetric match: role-selection GUI on join, staggered
   start countdown, shop purchases (generator/wall/turret tiers for
   Builders; stat upgrades + Scanner Sweep for the Behemoth), and win/lose
   detection.

## In-engine test checklist

`docs/verification.md` has the full scenario-by-scenario trace of every
capability spec against the implemented code, plus a specific
"Needs in-engine verification" checklist (fog-of-war reveal timing, Wall
collision actually blocking movement, Turret targeting via force
hostility, the ammo-turret damage trigger schema, GUI rendering, and
multiplayer determinism) to run through on the headless server /
real game before calling any of this balanced or bug-free.
