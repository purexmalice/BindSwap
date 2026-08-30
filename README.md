# BindSwap

Keybinding profiles for World of Warcraft Retail. Save as many keybind layouts
as you want, swap between them from an in-game window, and let each character
load its own layout automatically at login.

Built for people who play on more than one setup — a desk with a full keyboard
and mouse, a laptop with a cramped one — and don't want to rebind everything
every time they move.

Interface: `120100` (retail 12.1.0). Check yours in-game with
`/dump select(4, GetBuildInfo())` and update the `## Interface:` line if it differs.

## Install

Copy the `BindSwap` folder into your AddOns directory:

- macOS: `/Applications/World of Warcraft/_retail_/Interface/AddOns/`
- Windows: `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\`

Restart WoW fully — a `/reload` won't pick up a brand-new addon.

## Using it

Type `/kb` to open the window. It's also in the addon compartment dropdown next
to the minimap, and under **Settings → AddOns → BindSwap**.

The window gives you:

- **A list of every saved profile**, with its key count.
- **A checkbox per profile** — tick it and that profile loads automatically when
  *this character* logs in. Each character gets its own choice.
- **Save** — type a name, hit Save, and your current keybinds are stored under it.
  Reusing an existing name overwrites it.
- **Load / Rename / Delete** for the selected profile. Double-clicking a row
  loads it. Delete asks once before it commits.
- **Undo** — puts back the keybinds you had before the last load.

### Typical setup

1. Bind your keys the normal way (Escape → Options → Keybindings).
2. `/kb`, type `desktop`, hit **Save**.
3. Rebind for the other setup.
4. `/kb`, type `laptop`, hit **Save**.

Now swap with two clicks, or tick the checkbox so a character always starts on
the right one.

## Slash commands

Everything the window does, in case you prefer typing:

```
/kb                      open the window
/kb save <name>          save current keybinds as <name>
/kb load <name>          switch to <name>
/kb list                 show saved profiles
/kb delete <name>        remove a profile
/kb rename <old> <new>   rename a profile
/kb auto <name>          autoload <name> on this character
/kb auto off             stop autoloading on this character
/kb undo                 restore the binds from before the last load
```

`/bindswap` is a longer alias if `/kb` collides with another addon.

## Trackpad setup

If you play on a laptop, the **Trackpad setup** button binds a movement scheme
that needs no movement keys at all, leaving your left hand free for abilities:

| Key | Does |
|---|---|
| Middle mouse | Run and steer (a two-finger drag, via a trackpad helper) |
| `\` | Auto-run |
| `=` / `-` | Camera zoom |

Camera zoom moves onto keys because the two-finger drag consumes two-finger
scroll inside the game.

Presets **overwrite**. If a key they need is already doing something else, they
take it -- that is the point, since a preset that politely declined would
achieve nothing. Every displaced command is named in chat, and **Undo** puts the
whole layout back in one click.

On macOS the middle-button gesture is supplied by
[TrackSteer](../tracksteer), a small helper that turns a two-finger drag into a
held middle mouse button inside WoW only. Most Windows laptop trackpads have a
middle click already and need nothing extra.

## Behaviour worth knowing

- **A load replaces everything.** Every key is unbound first, then the profile is
  applied, so keys that exist only in your current setup end up cleared. That's
  what makes a swap clean instead of merging two layouts into a mess. **Undo**
  reverses it.
- **Undo is a toggle.** It swaps between the current binds and the ones from
  before the last load, so hitting it twice puts you back where you were.
- **Combat is handled.** Blizzard blocks binding changes in combat. A load during
  a fight is queued and applied the moment you drop out, rather than failing.
- **Multi-key binds survive.** The keybind UI only shows two keys per command,
  but WoW allows more. BindSwap saves and restores all of them.
- **Autoload runs once per session,** about a second after login, and never
  overrides a load you did yourself.
- **Profiles follow your binding set.** If you're on character-specific bindings,
  saves go there; otherwise account-wide.

## Two computers

Profiles live in SavedVariables, inside each WoW installation's `WTF` folder,
so they do **not** sync between machines on their own. Two options:

1. **Save them separately on each machine.** Since each install has its own
   store, the laptop's copy only needs the laptop profile — tick its autoload
   box there and it just works. This is the simple path.
2. **Copy the file between installs.** With WoW closed on both ends, copy
   `WTF/Account/<ACCOUNT>/SavedVariables/BindSwap.lua`. WoW rewrites that file on
   logout, so copying it while the game is running will get your changes
   overwritten.

Per-character autoload choices live in
`WTF/Account/<ACCOUNT>/<Realm>/<Character>/SavedVariables/BindSwap.lua`.

## Tests

The binding API is mocked so the profile, autoload, undo, and combat logic can be
exercised outside the game. Needs a Lua 5.1 interpreter — the version WoW uses:

```bash
lua tests/test_core.lua BindSwap/Core.lua
```

38 checks covering round-trip fidelity, per-character autoload, login timing,
combat deferral, rename/delete side effects, and bad input. `UI.lua` isn't
covered — it needs the real frame system, so it's verified in-game.

## Layout

```
BindSwap/
  BindSwap.toc   manifest
  Core.lua       binding engine, profile store, slash commands, autoload
  UI.lua         the window; built lazily and guarded so a broken
                 UI template can't take the slash commands down with it
tests/
  test_core.lua  mocked-API test suite
```
