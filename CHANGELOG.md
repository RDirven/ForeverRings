# Changelog

## 0.5.1

- **Spell ranks**: spells show their rank everywhere (picker, ring, slot names), e.g. *Arcane Intellect (Rank 2)*. The picker lists each spell's highest rank first.
- **Hold camera still** is now a setting (on by default) and actually holds it still: while a ring is open the sticks are taken away from the camera, so the right stick only aims.
- Fixed: the controller sometimes couldn't aim (while the mouse still worked) until a /reload. Rings now also listen to the stick while a modifier like R2 is held, and turn the stick direction buttons back on when something switched them off.

## 0.5.0

- **Rings on your action bar**: *Put on action bar* in the settings screen (or `/frings bar <ring>`) puts a macro on your cursor. Click it to open the ring, aim, then click again or left-click to use.
- **Mouse**: left-click picks from an open ring, right-click goes back or closes. Pressing the ring button again while the ring is open picks too.
- **Settings screen works with the mouse**: clickable Rings/Settings tabs and slots, mouse wheel, buttons for Edit, Set key, Rename and Back, right-click to clear a slot or step a setting back.
- **Drag and drop**: drop spells, items, mounts and macros on a slot or on a ring in the list.
- Middle and side mouse buttons can be set as ring buttons.
- **Button combos** like Shift + B: hold a modifier (or a pad button the client treats as Shift/Ctrl/Alt) while setting a ring's button.
- Ring buttons now win over Blizzard's own gamepad bindings on the same button.
- Drag a ring out of the list to get its action bar button.
- Fixed: *Put on action bar* and the Macros picker failed on clients without `MAX_ACCOUNT_MACROS`.
- **The camera holds still** while a ring is open, so aiming with the right stick no longer looks around.
- **Pick on stick release** (new setting, on by default): aim, let go of the stick, and that slot is used, like Blizzard's own radial menus. Turn it off to have letting go keep the selection instead; then release the ring button or press A to use it.
- Fixed: the sticks couldn't aim when the client setting `GamePadStickAxisButtons` was off. It's now turned on for you.
- Fixed: mouse aiming read the cursor before the ring was shown.
- **Fully playable without a keyboard**
  - First login opens the settings screen with a short welcome, Main already selected.
  - New **Settings** slot in the Main ring opens the settings screen. (Not remembered for tap to repeat.)
  - New page under **Options > AddOns > Forever Rings** with an "Open" button.
  - Rename your own rings by picking a name (Y in the ring editor).
- **Cooldowns and usability**: slots show cooldown swipes; things you can't use are dimmed, and blue when you lack mana/energy.
- **Macros**: put your own WoW macros in any ring (picker category "Macros"). Edits to a macro are picked up automatically.
- **Ring size**: 80% to 150% in Settings.
- **New look**: soft backdrop, a glowing inner track with a light that follows your aim, halos and rims on the slots, a ripple on every new selection, and a flash of the icon when you use something. Rings open with a staggered pop.
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
