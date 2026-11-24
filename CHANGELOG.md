# Changelog

## 0.6.1

- **Rollouts**: any ring can open as a column out of its action bar button instead of a ring (ring editor: LB, or the Ring/Rollout button). Step through it with the stick up/down, then let go of the ring button or press A. A tap opens it and it stays open.
- **Slot keys**: give any slot of your own rings its own button (ring editor: RB, then press the button). It only counts while that ring is open, so any button works, even the one that opens the ring: rollout on X with Immolate on O and Corruption on X means X > O = Immolate, X > X = Corruption. Optional: the stick still works. The key shows on the slot.
- Fixed (hopefully for good): some sessions the controller couldn't aim in rings until a /reload, while the mouse worked. The ring now also reads the aiming stick itself, so out of combat it aims even when the client doesn't deliver the stick's direction buttons; release the ring button or press A to pick. (In combat the game only allows the secure path.)
- New `/frings debug`: open a ring, move the stick, close it, then type it. It shows whether the stick and its direction buttons reach the addon. Please paste the result in a comment if the controller still doesn't aim.
- The ring learns which way is up from your stick, for clients that report it the other way round.

## 0.6.0

- **Hover cast** (Settings > Party heals): open the Party ring, aim at someone and press A, B, X or Y, or hold L2 or R2 with them: twelve heals, each landing on whoever you aim at without changing your target. The ring stays open so you can keep healing; its button closes it. Works whether L2/R2 are plain buttons or set as Alt/Shift/Ctrl.
- **Party ring as a pizza**: every member is a big slice that fills with solid colour from the crust toward the centre (green to red, grey when dead), names on the slices. Works with the client's secret health in combat. Sharp, anti-aliased edges.
- Hover cast uses **what's on your action bar** under A, B, X and Y (and L2/R2 + them, when the client treats those as modifiers) unless you pick a spell yourself.
- **Dispellable debuffs** on the Party ring: up to three icons under a name, for debuffs you can dispel.
- The Party ring drops the circles around names; whoever needs healing most pulses their slice red.
- **Party button** (Settings): *Tap*: tap, aim, one heal and it closes. *Toggle*: tap, heal as many as you like, tap again to close. *Hold*: open while you hold the button, let go to close (needs a key bound with `/frings bind party <key>`; an action bar button only sends one click).
- **Health fills from** (Settings): the crust inward, or the centre outward.
- **Your buffs** (Settings): *HoTs only* skips your buffs over five minutes (Blessing of the Bronze...); hide any by name with `/frings hidebuff <name>`.
- **Your HoTs** on the Party ring: a green circle around the name and the icons above it while your HoT or shield is on someone.
- **Ring opacity** (Settings): make everything but the slot you aim at see-through, down to 0%.
- **Hold still while aiming** (was *Hold camera still*): aiming with the left stick no longer walks your character.
- **Retail**: the addon loads in retail too (Interface 120105, 120107).
- Fixed: "Secret values are only allowed during untainted execution" (SetCooldown) in retail combat. Secret cooldowns and usability are left alone.

- **Party ring, for healers on a controller.** You (on top) and your group in a circle, each with a health bar and their name in class colour. Aim at someone and release: your heal lands on them **without changing your target**. Works in combat.
  - Pick the heal in the settings screen: open the Party ring, press A and choose from Spells. X clears it; without a spell, the ring targets whoever you aim at.
  - Whoever needs healing most (below 80%) pulses red. Members out of range fade, dead ones turn grey.
  - Tap the ring's button to heal the same person again.
  - In a raid it shows your own group of five.
  - Joining or leaving a group updates the ring after combat.
  - **Party heals** (Settings): *One spell*, or *Spell per button*: release, A, X and Y each cast their own heal on whoever you aim at. Aim at the tank, press X for the big heal, Y for the HoT.
  - **Party order** (Settings): *Group order*, or *By role*: you on top, the tank always right, a healer left and DPS below, in five fixed places so nobody moves when the group changes.

## 0.5.4

- Fixed: menus with a micro menu button (Character, Spellbook, Talents, Quest log, Group finder...) didn't open from a ring. They're now a secure click on that button.
- Fixed: "SecureTemplates.lua:561: attempt to call a nil value" when picking Settings, Bags, Map, Social or Calendar from a ring (mouse or action bar).

## 0.5.3

- **Menu ring**: the game panels in one ring: Character, Bags, Spellbook, Talents, Quest log, Map, Social, Group finder (what your client has). It's in Main by default.
- **Every game panel can go in your own rings**: new picker category *Menus* with Character, Bags, Spellbook, Talents, Quest log, Map, Social, Guild, Group finder, PvP, Achievements, Collections, Calendar and Game menu.
- **Reset Main** (Settings > Main ring) puts Main back to its default slots, Settings slot included.
- Clearing a slot asks first: press X (or right-click) twice.
- **Markers: Clear** in the middle of the ring: press A without aiming, tap the ring's button, or click the middle.
- Fixed: from an action bar button, menus, markers and the Settings slot did nothing (a macro can't start another macro). They now run without a macro: menus as a secure click on their micro menu button, markers as a secure raid mark. No more "action blocked" / secret value errors.
- **Mouse aims from the middle of the ring**, wherever the mouse was when the ring opened. Not moving it still means "tap to repeat".
- **Cleaner settings screen.** Every view has a title row (where you are, e.g. *Main > slot 4*) with its buttons on the right, so nothing overlaps.
- **Editing a ring lists its slots** on the left: click one to choose what goes in it, right-click to clear it, drag things onto it. Up/Down on a controller.
- The picker categories (Bags, Spells, Mounts, Toys, Macros, Rings) have their own row and can be clicked. LB/RB still switch them on a controller.

## 0.5.2

- **Rings live on your action bar now, not on hidden buttons.** Every ring row has **Edit**, **Set key**, **Clear**, **+** and **-**. *Set key* asks you to press the action bar button where the ring should go (L2/R2 combos included) and puts it there; *Clear* takes it off your bars. `/frings bar <ring>` puts it in the first free visible slot.
- Ring buttons set in older versions are removed once, so the game's own gamepad bindings work again. (If a button still does nothing, restore Blizzard's default gamepad bindings in the Key Bindings menu.)
- **+** adds something to a ring, **-** deletes it (click twice). While editing a ring, **Back**, **Rename**, **+** (add a slot) and **-** (clear the slot) sit above the list. The bottom-right buttons are gone.
- **Works the same on a controller**: in the ring list, Left/Right walks a row's buttons and A presses one; Y is Set key. The right stick browses too.
- **Every ring has its own icon** (Main, Mounts, Quest, Tools and empty rings showed none). Sub-ring slots show the icon of the ring they open.
- Fixed: a ring bound to the D-pad took that button away from the settings screen.
- Fixed: right after a reload the controller couldn't move through the settings screen until you reopened it. The screen now reads the gamepad itself.

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
