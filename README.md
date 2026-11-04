# Forever Rings

**Controller-first radial rings for WoW Forever.** Hold a button, aim with the stick, release. Your food, usable items and mounts are already in there, because the rings fill themselves from your bags.

## Features

- **Made for controllers.** Aim with the right stick (or left stick / D-pad). Release to use, **A** to select, **B** to go back.
- **Tap to repeat.** Tap the ring button without aiming to use your last pick again: one tap to mount, one tap to eat.
- **Feel it.** A short rumble when the stick lands on a new slot, and smooth animations.
- **Rings that fill themselves**
  - **Food**: food & drink from your bags, best first, plus one **Eat & Drink** slot that does both at once.
  - **Bag**: every usable item (potions, scrolls, quest items…).
  - **Mounts**: your favorites, or all usable mounts.
  - **Quest**: usable quest items.
  - **Markers**: the eight target markers, skull first. Hard to do on a controller otherwise.
- **Main ring with sub-rings.** One button for everything: Main → Food / Mounts / Bag / Tools / your own rings.
- **Separate rings too.** Every ring can also get its own button.
- **Your own rings.** Spells, items, toys, mounts, your own **macros**, and other rings as sub-rings.
- **No keyboard needed.** Setup, buttons, names and settings all work on a controller.
- **Cooldowns and usability** on every slot.
- **Share rings.** `/frings export` gives a short code; friends paste it after `/frings import`.
- **Works in combat.** Picking and using happen in secure code.
- **Two styles.** *Clean* (round, minimal) or *Classic* (Blizzard borders).
- **Mouse and keyboard work too.** Aim by moving the mouse, left-click to pick, right-click to go back.
- **On your action bar.** *Put on action bar* in the settings screen (or `/frings bar <ring>`) gives you a macro to drop on any action bar slot. Click it to open the ring, aim, click again (or left-click) to use.
- **Drag and drop.** Drag spells, items, mounts and macros from your spellbook, bags or macro window straight onto a ring slot.

## Getting started

1. The settings screen opens by itself the first time. Later: the **Settings** slot in your Main ring, **Options > AddOns > Forever Rings**, or `/frings`.
2. Select **Main**, press **Y** and press the button you want for it. **L3 or back paddles** work best: you aim with the right stick, and Blizzard's gamepad UI already uses the shoulder buttons for targeting and the triggers as action bar modifiers. (A and B are kept for selecting and going back inside rings.)
3. Close with **B**. Press your button, push the stick toward a slot and let go of the stick: that slot is used. (Turn off *Pick on stick release* in Settings to pick by releasing the ring button or pressing A instead.)

## Settings screen

Fully playable on a controller. Mouse and keyboard work too.

| Button | Does |
|---|---|
| **LB / RB** | Switch between Rings and Settings, or between picker categories |
| **D-pad** | Move |
| **A** | Open a ring, choose a slot, pick an item |
| **B** | Back / close |
| **X** | Clear a slot, delete a custom ring (press twice) |
| **Y** | Set the button that opens a ring (in the ring editor: rename it) |

Fill slots from **Bags**, **Spells**, **Mounts**, **Toys**, **Macros** or other **Rings** (sub-rings). The preview shows the ring exactly as it will appear.

With a mouse: click the tabs, rows and slots, scroll the list with the wheel, and use the buttons at the bottom right (**Edit**, **Set key**, **Put on action bar**, **Rename**, **Back**). Drag a spell, item, mount or macro onto a slot in the preview, or onto a ring in the list to add it at the end. Right-click a slot to clear it. Drag a ring out of the list to put it on your action bar. When setting a key, a middle or side mouse button works too.

**Combos** (like L1 + Circle): hold a modifier while pressing the button. On a controller, a button only counts as a modifier when the client treats it as one, e.g. `/console GamePadEmulateShift PADLSHOULDER` makes L1 act as Shift (it then no longer targets allies).

## Commands

Everything in the settings screen is also available as a command (`/frings help`):

| Command | What it does |
|---|---|
| `/frings new <name>` | Create a ring |
| `/frings add <ring> <shift-click item/spell>` | Add an action |
| `/frings add main ring:<name>` | Put a ring inside the main ring |
| `/frings remove <ring> <n>` | Remove slot *n* (see `/frings list <ring>`) |
| `/frings delete <name>` | Delete a ring |
| `/frings bar <ring>` | Put a button for the ring on your cursor, to drop on an action bar |
| `/frings bind <ring> <key>` | Bind a ring directly, e.g. `PADLSTICK` (L3) or `PADPADDLE1` |
| `/frings export <ring>` | Get a share code for a ring |
| `/frings import <code>` | Add a ring from a share code |
| `/frings style clean\|classic` | Switch style |
| `/frings input rstick\|lstick\|dpad` | Choose what you aim with |

Each ring holds up to 8 slots, one per stick direction. Use sub-rings for more.

## Known limitations

- Ring contents update out of combat. During combat a ring shows what was in your bags when the fight started (counts do update).
- Early release: please report issues!
