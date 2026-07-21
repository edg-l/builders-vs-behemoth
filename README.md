# Builders vs Behemoth

An asymmetric "cat and mouse" scenario mod for Factorio 2.0: one player is
the lone hunter (the **Behemoth**); everyone else are mutually-allied
**Builders** who hide, build an economy, and defend chokes, then turn and
kill the hunter. Inspired by the StarCraft II Arcade mode "Probes vs Zealot
2". See `openspec/changes/core-loop-mvp/` for the full proposal, design, and
task breakdown.

## Status

Mod skeleton only (task group 1): `info.json`, `data.lua`, `control.lua`,
and the `scripts/` module stubs are wired up, but gameplay prototypes and
event-handler bodies are not implemented yet — see the `TODO(n.n)` markers
in `scripts/*.lua` for what each later task group fills in.

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
- **Lua static checks** (`luacheck`): `luacheck` is **not installed** on
  this machine. `.luacheckrc` is already configured with the Factorio
  runtime/data-stage globals (`data`, `game`, `storage`, `script`,
  `defines`, `rendering`, `settings`, ...) as read-only globals, so once
  luacheck is available, running it from the repo root is enough:
  ```sh
  luacheck .
  ```

## Installing into Factorio

1. Copy (or symlink) this repository into your Factorio `mods/` directory
   under the name `builders-vs-behemoth_0.1.0` (matching `info.json`'s
   `name`/`version`), or zip the repo contents and drop the zip into
   `mods/`.
2. Enable the mod from the in-game mod list, or via `mod-list.json`.

## Running on a headless server for playtesting

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
4. Connect with regular Factorio clients (same mod version required) to
   playtest the asymmetric match.

This section will grow with concrete server-config and multi-client
playtest steps once the full match loop (task groups 2-7) is implemented.
