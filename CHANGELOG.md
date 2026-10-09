# Changelog

## 0.5.0

- **Fully playable without a keyboard**
  - First login opens the settings screen with a short welcome, Main already selected.
  - New **Settings** slot in the Main ring opens the settings screen. (Not remembered for tap to repeat.)
  - New page under **Options > AddOns > Forever Rings** with an "Open" button.
  - Rename your own rings by picking a name (Y in the ring editor).
- **Cooldowns and usability**: slots show cooldown swipes; things you can't use are dimmed, and blue when you lack mana/energy.
- **Macros**: put your own WoW macros in any ring (picker category "Macros"). Edits to a macro are picked up automatically.
- **Ring size**: 80% to 150% in Settings.
- If you never changed your Main ring, it gets the Settings slot automatically.

## 0.4.0

- **Quest ring**: usable quest items from your bags, filled automatically. (They no longer clutter the Bag ring.)
- **Markers ring**: all eight target markers, skull first. Pick one again to clear it.
- **Share rings**: `/frings export <ring>` gives a code to copy; friends load it with `/frings import <code>`.
- Main ring now also holds Quest and Markers. If you never changed your Main ring, it's updated for you.
- The button tip now depends on the stick you aim with (L3 or paddles when aiming with the right stick), with a warning when you pick the stick you aim with.

## 0.3.0

- **Tap to repeat**: tap a ring button without aiming to use the last thing you picked from that ring again. Remembered across reloads. Can be turned off in Settings.
- **Eat & Drink**: the Food ring now starts with one slot that eats your best food and drinks your best drink at the same time.
- **Vibration**: a short rumble when the stick moves to another slot (Settings → Vibration).
- **Animations**: rings pop open, the selected slot grows with a soft pulse, and a pointer swings toward where you aim.

## 0.2.1

- Recommend L3, R3 or paddles for ring buttons, and warn when binding a ring to a button Blizzard's gamepad UI already uses (shoulders for targeting, triggers as modifiers).

## 0.2.0

- New settings screen, built for controllers: type `/frings` or bind "Open settings".
  - LB/RB switch tabs, D-pad moves, A opens, B goes back, X clears/deletes, Y sets a ring's button.
  - Create rings, fill slots from Bags, Spells, Mounts, Toys or other rings, and see a live preview.
  - Settings tab for style, aim input and the settings button.
- `/frings` without arguments now opens the settings screen (`/frings help` lists commands).

## 0.1.1

- `/frings remove` now tells you when a slot number doesn't exist instead of doing nothing.

## 0.1.0

- First release: controller-first radial rings for WoW Forever.
- Auto-filled Food, Bag (usable items) and Mount rings.
- Main ring with sub-rings, custom rings, direct ring bindings.
- Clean and Classic styles.
