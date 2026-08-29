# BindSwap

Save and load keybinding profiles in WoW Retail with slash commands. Built for
switching between a desk setup (keyboard + mouse) and a laptop setup without
rebinding everything by hand.

Interface: `120100` (retail 12.1.0). Verify yours in-game with
`/dump select(4, GetBuildInfo())` and update the `## Interface:` line if it differs.

## Install

Copy the `BindSwap` folder into your AddOns directory:

- macOS: `/Applications/World of Warcraft/_retail_/Interface/AddOns/`
- Windows: `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\`

Then fully restart WoW (a `/reload` won't pick up a brand-new addon).

## Use

Set your keys up the normal way in the Escape menu, then:

```
/kb save desktop     save the current keybinds as "desktop"
/kb load desktop     switch to the "desktop" binds
/kb list             show saved profiles
/kb delete desktop   remove a profile
/kb undo             restore the binds from before the last load
```

`/bindswap` works as a longer alias if `/kb` collides with another addon.

Typical first run:

```
(bind everything for keyboard + mouse)
/kb save desktop
(rebind for the laptop)
/kb save laptop
```

After that it's `/kb load laptop` and `/kb load desktop`.

## Behaviour worth knowing

- **A load replaces everything.** Every key is cleared first, then the profile is
  applied, so keys that exist only in your current setup end up unbound. That's
  what makes a swap clean rather than a merge. `/kb undo` reverses it.
- **`/kb undo` is a toggle.** It swaps between the current binds and the ones from
  before the last load, so pressing it twice puts you back.
- **Combat is handled.** Blizzard blocks binding changes in combat. A `/kb load`
  mid-fight is queued and applied the moment you drop out of combat.
- **Multi-key binds are preserved.** The default UI only shows two keys per
  command, but WoW allows more; BindSwap saves and restores all of them.
- **Profiles follow the binding set you're on.** If you're using
  character-specific bindings, saves go there; otherwise account-wide.

## Two computers

Profiles are stored in SavedVariables, which live inside each WoW installation's
`WTF` folder. They do **not** sync between machines on their own. Two options:

1. Save the profiles separately on each machine (simplest).
2. Copy `WTF/Account/<ACCOUNT>/SavedVariables/BindSwap.lua` between installs
   while WoW is closed — WoW overwrites that file on logout.

## Tests

The binding API is mocked so the save/load/undo logic can be exercised outside
the game. Requires a Lua 5.1 interpreter (the version WoW uses):

```bash
lua tests/test_bindswap.lua BindSwap/BindSwap.lua
```
