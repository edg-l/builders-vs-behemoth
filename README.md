# Builders vs Behemoth

A multiplayer Factorio 2.0 mod where one player hunts and everyone else hides and builds.

It's asymmetric cat and mouse. A single **Behemoth** stalks the map hunting for bases to smash, while everyone else plays a **Builder**: scatter, hide, grow an economy, wall up the chokes, then arm up and turn the hunt around. The Behemoth earns currency only by damaging Builder structures, so your bases are its feeding ground; Builders earn from Generators and spend on Wall and Turret tiers. Last side standing wins. The Behemoth wins when every Builder is gone, the Builders win the moment the Behemoth dies.

Inspired by the StarCraft II Arcade classic "Probes vs Zealot 2".

## How a match goes

- Everyone picks a role in the lobby. Exactly one player is the Behemoth, chosen at random if nobody volunteers.
- Builders spawn first and scramble to hide. The Behemoth drops in after a short head start.
- Builders place a Generator for income, upgrade it, and fortify with Walls and Turrets. Staying unseen is half the game; the Behemoth can't hit what it can't find.
- The Behemoth scouts, smashes what it finds for currency, and spends it on damage, attack speed, armor, health, and a Scanner Sweep that reveals an area.
- It ends when the Behemoth falls, or when the last Builder does.

## Install

Drop the mod into your Factorio `mods/` folder:

- Linux: `~/.factorio/mods/`
- Windows: `%APPDATA%\Factorio\mods\`
- macOS: `~/Library/Application Support/factorio/mods/`

Either copy or symlink the repo as `builders-vs-behemoth_<version>`, or zip it (with `info.json` at the zip root) as `builders-vs-behemoth_<version>.zip`, matching the `version` in `info.json`, then enable it from the in-game mod list. A normal freeplay world is enough; the mod runs role selection and spawning on its own.

## Playtest on a headless server

You need at least two players, one Behemoth and one Builder.

```sh
./factorio --create ./saves/bvb.zip        # a save with the mod enabled
./factorio --start-server ./saves/bvb.zip
```

Then connect with clients on the matching mod version.

## Development

The code is plain Lua and JSON, so you can work on it without Factorio installed. Static checks:

```sh
find . -name '*.lua' -not -path './openspec/*' -exec luac5.4 -p {} \;   # syntax
luacheck .                                                             # lint
```

Design notes, specs, and the task breakdown live in `openspec/changes/core-loop-mvp/`. `docs/verification.md` maps every spec scenario to its code and lists what still needs checking inside the running game.

## License

AGPL-3.0. See `LICENSE`.
