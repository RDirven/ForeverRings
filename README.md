# Forever Rings

**Controller-first radial rings for WoW Forever.** Hold a button, aim with the stick, release. Your food, usable items and mounts are already in there, because the rings fill themselves from your bags.

## Features

- **Made for controllers.** Aim with the right stick (or left stick / D-pad). Release to use, **A** to select, **B** to go back.
- **Rings that fill themselves**
  - **Food**: food & drink from your bags, best first.
  - **Bag**: every usable item (potions, scrolls, quest items…).
  - **Mounts**: your favorites, or all usable mounts.
- **Main ring with sub-rings.** One button for everything: Main → Food / Mounts / Bag / Tools / your own rings.
- **Separate rings too.** Every ring can also get its own button.
- **Your own rings.** Spells, items and toys, plus other rings as sub-rings.
- **Works in combat.** Picking and using happen in secure code.
- **Two styles.** *Clean* (round, minimal) or *Classic* (Blizzard borders).
- Keyboard and mouse work too: aim by moving the mouse.

## Getting started

1. Type `/frings` (or bind **Open settings**) to open the settings screen.
2. Select **Main**, press **Y** and press the button you want for it, for example a shoulder button. (A and B are kept for selecting and going back inside rings.)
3. Close with **B**. Hold your button, push the stick toward a slot and release.

## Settings screen

Fully playable on a controller. Mouse and keyboard work too.

| Button | Does |
|---|---|
| **LB / RB** | Switch between Rings and Settings, or between picker categories |
| **D-pad** | Move |
| **A** | Open a ring, choose a slot, pick an item |
| **B** | Back / close |
| **X** | Clear a slot, delete a custom ring (press twice) |
| **Y** | Set the button that opens a ring |

Fill slots from **Bags**, **Spells**, **Mounts**, **Toys** or other **Rings** (sub-rings). The preview shows the ring exactly as it will appear.

## Commands

Everything in the settings screen is also available as a command (`/frings help`):

| Command | What it does |
|---|---|
| `/frings new <name>` | Create a ring |
| `/frings add <ring> <shift-click item/spell>` | Add an action |
| `/frings add main ring:<name>` | Put a ring inside the main ring |
| `/frings remove <ring> <n>` | Remove slot *n* (see `/frings list <ring>`) |
| `/frings delete <name>` | Delete a ring |
| `/frings bind <ring> <key>` | Bind a ring directly, e.g. `PADLSHOULDER` |
| `/frings style clean\|classic` | Switch style |
| `/frings input rstick\|lstick\|dpad` | Choose what you aim with |

Each ring holds up to 8 slots, one per stick direction. Use sub-rings for more.

## Known limitations

- Ring contents update out of combat. During combat a ring shows what was in your bags when the fight started (counts do update).
- Early release: please report issues!
