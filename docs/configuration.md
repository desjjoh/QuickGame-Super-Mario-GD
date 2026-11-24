# Configuration

## Project settings

| Setting | Value |
| --- | --- |
| Main scene | `scenes/main/game.tscn` |
| Logical viewport | 256×240 |
| Initial window | 768×720, bordered and resizable |
| Stretch | Window-resolution `canvas_items`, fractional scaling with aspect preserved |
| Physics interpolation | Off |
| Windows rendering driver | Direct3D 12 |

Use Godot’s **Project → Project Settings → Input Map** to inspect bindings. See [setup](setup.md#controls) for gameplay controls.

## Areas and pipe routes

Select a `BaseLevelArea` and set its **Theme** to Overworld, Underground, Castle, or Underwater. The theme supplies compatible ground, decoration, and entity TileSets, plus entity and UI artwork. Keep source IDs and atlas coordinates compatible across themes so painted layouts survive a theme change.

Paint **Bridge deck** on **GroundLayout** for a solid bridge tile. Paint **Bridge railings** on **DecorationLayout**, one row above the deck, for the non-colliding guardrail. Both entries use compatible source IDs across all four themes.

Set **Background Music** independently to Overworld, Underground, Castle, Coin Heaven, Underwater, or None. Overworld is the default. 1-1 uses Underground in its secret area.

Under **Movement**, enable **Swimming Enabled** to use swim movement and bubbles. 2-2 enables it in MainArea. The player sinks during the underwater arrival lock, gains swim control when it ends, and resumes land movement after emerging in SurfaceArea. The 2-2 Arrival endpoint enables **Swim Entry Drop** and sets **Control Lock Ticks** to 34. The player drops 49 px over 33 swim ticks, holds position on tick 34, and can steer or stroke with held input on tick 35. A swim stroke or landing returns the player to ordinary swim gravity.

Place a `Whirlpool` scene anywhere under a swimming area to add a current. Its X position sets the left edge and **Width** sets the reach in pixels. The editor guide extends to the far edge of the tile containing the inclusive cutoff and marks the middle tile. The current spans the full water column, and the bottom input cutoff is measured from the area origin. Open `tests/fixtures/whirlpool_sandbox.tscn` to try the current in isolation.

The underwater `GroundLayout` includes a solid **Reef** tile from the Pipes and Scenery atlas. In 2-2, the three currents begin at area-local X1040, X2080, and X2496 and span 96, 160, and 128 pixels respectively.

Set **Transport Points** and **Pipe Routes** on the source area to link placed pipes to explicit area and destination IDs. A destination pipe supplies its exit pose. Paint **Sideways Pipe Entrance (1×2)** for a one-tile-wide mouth, as used at the underwater exit in 2-2. The reserved `player_spawn` target returns to the main area’s spawn. Standalone arrival markers are useful where an area needs a separate landing point.

Configure **Presentations → PipeOpening** with the intro area, painted castle cell, and the sideways pipe's **Entrance ID**. A fresh entry spawns at the castle doorway and walks into that pipe automatically. In 1-2, the pipe targets `main / arrival`, which uses **Areas → MainArea → Arrival**. Early deaths restart at **Players → PlayerSpawn**. Move each marker to set its placement independently.

In 1-2, the first upright pipe in MainArea leads to BonusArea's Arrival. The sideways pipe at the end of the coin room returns through MainArea's third upright pipe. The sideways pipe near the end of MainArea leads to the upright pipe in SurfaceArea.

Set **Stage Scene** on a transport destination for a cross-stage warp. After pipe entry, the stage completion flow loads that scene at its normal start. All three 1-2 Warp Zone pipes currently share a destination of 1-1.

Mario and Luigi carry their current form through normal stage completion and cross-stage warps. The next stage applies the form before the first pose or opening presentation. Death respawns use the stage's starting form.

### Place a Warp Zone

Instance `scenes/entities/warp_zone/warp_zone.tscn` under the area's **WorldObjects**. Position **RevealMarker** where the camera's left edge should reveal the banner. Place one or more `warp_zone_pipe.tscn` instances under **Pipes**. Set each pipe's **Display Text** and **Destination → Stage Scene** independently. The text follows the pipe when it moves.

Set **Pipe Occupant** on the zone to give its pipes plants before the reveal. Revealing the zone removes those occupants and enables the configured entrances. The 1-2 instance shows **1 1 1** because each pipe routes to 1-1.

**Presentations → FlagpoleEnding** binds to the painted flagpole and castle by area ID and cell. In 1-2, the ending uses the SurfaceArea markers. The castle in IntroArea provides the opening doorway. In Overworld areas, paint **Large Castle (9x11)** on **EntityLayout** for a tall finish like 1-3. The wall extends two tiles left of the stamped cell. Paint individual **Castle parts** on **EntityLayout** for scenery that participates in the shadow effect. These tiles have no collision. Set **Castle Cell** to the cell where you painted the stamp. This variant supplies the left doorway and shares the castle flag and fireworks sequence.

## Area background colour

Select an area such as **Areas → MainArea** and set **Background → Background Color**. Its fill spans **Camera2D → Area Left** and **Area Right**, measured in pixels from the area's origin, and the camera's visible vertical height. Moving the area moves the fill and horizontal camera limits together. Alpha zero reveals Game’s black backdrop during F5; standalone F6 retains the viewport default unless an area supplies a colour. Each area owns its colour independently of its theme and music. The fill sits behind decorations, receives foreground shadows, and never casts a shadow itself in F5 or standalone F6.

## Start-menu background

Open `scenes/main/game.tscn`, select **Game**, and assign **Presentation → Title Background** to the BaseLevel scene you want behind the start menu. An empty field uses the first entry in **Stages**; the authored Game leaves it empty, so its backdrop is 1-1. The selection is used on startup and on later returns to the menu; title actors remain suspended and background music stays silent. Choose a valid level scene, not the title UI scene. Gameplay still loads from **Stages**, independently of this background.

## Level rules

- Set **Area Left** and **Area Right** on the area camera to define the playable scroll range. A one-screen area starting at its origin uses 0 and 256, wherever it sits in the level scene.
- Set the timer limit and enable flag on the level. The HUD keeps the TIME label and hides the digits on the start screen, during transitions such as level intro, TIME UP, and GAME OVER, and whenever the timer is disabled.
- Set **Background Music** on the area to choose Overworld, Underground, Castle, Coin Heaven, Underwater, or None. 1-4 selects Castle. The 2-2 main area selects Underwater. The 2-1 cloud area selects Coin Heaven, which uses the Starman theme and its hurry-up loop.
- Hurry-up plays once when the timer falls from 100 to 99. A timed stage authored at 1–99 plays the warning at gameplay reveal and then uses the fast music. Starting below 100 is a deliberate extension for authored stages.
- In `scenes/main/game.tscn`, select **Game → Gameplay → Save Entity State Through Death**. Enabled by default, it carries saved entity state and runtime tile changes into the next attempt. Disable it to reload the stage's authored state after a death. Each entity's persistence setting still controls what is saved between area visits. Score and coins in the HUD carry forward in either mode, and death still costs a life.
- The Game scene supplies the stage list and the shared shadow master toggle. The first stage is 1-1. Open `scenes/main/game.tscn`, select **Game**, and use **Presentation → Shadow Style** to load `assets/shadows/soft.tres`, `crisp.tres`, or `outer_blur.tres`. Clear the field for no shadow effect. Outer Blur is the current authored Game selection. One selection applies to the title and every stage; standalone F6 previews read the saved Game selection and master toggle. Decorations remain outside the effect.

### Halfway restarts

Add a `Marker2D` under **Players** at the desired feet position and assign it to the level's **Death → Halfway Spawn** field. On **Areas → MainArea → Camera2D**, enable **Halfway Restart → Halfway Check Enabled** and set **Halfway Camera Left** in pixels from the main area's origin. The 2D editor draws a labeled dashed guide that moves with the area. At life loss, the active camera and the threshold are compared in world coordinates.

1-1 uses a marker at `(1328, 208)` and a camera-left threshold of `1280`. 1-2 uses `(1584, 208)` and `1536`. 1-3 uses `(1072, 208)` and `1024`. 2-2 uses `(1328, 208)` and `1280`. 2-3 uses `(1840, 208)` and `1792`. These coordinates are relative to each stage's main area. At a halfway restart, the camera starts at the threshold and Mario's sprite starts 40 px from the left edge. Main-area deaths before the threshold use PlayerSpawn. Side-area deaths use the active camera's world position, so 1-1's authored secret room restarts at PlayerSpawn and 1-2's authored bonus room uses the halfway marker. 2-2 restarts underwater after losing a life on the surface.

On the first main-area load of a halfway restart, EnemyLayout placements with a spawn trigger left of the last visible pixel are skipped for that area load. In 1-2 this skips the Goomba triplet near the checkpoint. Enemies with triggers at or beyond the right edge and occupants attached to pipes can spawn normally.

## Known reference differences

Choose **Apply Tiered Power-Up Reward** in the **EntityLayout** block reward brush, then click a painted question block, hidden question block, reward brick, or alternate reward brick. The translucent red mushroom marks the tiered reward. The block chooses a Super Mushroom for Small Mario or Luigi and a Fire Flower for Super or Fire when it releases the reward. Previously painted Super Mushroom assignments use the same tiered behavior. Coin remains the default.

Both items grant 1,000 points on pickup. Super Mushroom grows Small to Super. Fire Flower grows Small to Super, upgrades Super to Fire, and grants points to an already-Fire player.

Choose **Apply Starman Reward** in the same brush to paint a fixed star reward. The translucent star uses the area's item art. Starman can be collected after rising four pixels and grants 1,000 points and about 12 seconds of contact protection. While active, touching Goombas, Koopas, or shells knocks them out. The player cycles through the area's alternate palettes and the Starman theme temporarily overrides the area music. The effect clears on pipe transfer, flagpole grab, and death. Clearing at the flagpole grab is a deliberate difference from the NES.

Timed multi-coin rewards use independent, fixed 231-physics-tick windows instead of the NES's shared, phase-dependent timer. Loading or hitting another block cannot alter an existing window. Pause and unloaded areas freeze remaining time; death follows the existing progress-reset policy.

## Paint pipe occupants

Select **EntityLayout** and paint a vertical **Pipe Entrance (2×2)**. In the 2D toolbar, choose **Apply Green Piranha Plant** and click either half of the pipe mouth. A translucent preview uses the area theme and stays visible when you switch brushes. Use **Clear Pipe Spawn** on the mouth to remove it. Both brushes support undo and redo.

Each mouth has one occupant entry. Decorative, entrance, and exit pipes can all host a plant. Pipe destinations are configured separately. The plant uses an enemy slot and shares the one-attempt-per-area-load rule with other painted enemies.

## Shared entity registry

Add standard marker-to-scene mappings to **BaseLevel: Entity Scenes** in scenes/levels/base/base_level.tscn. Levels inherit this registry. Do not create a per-level dictionary override: Godot replaces the inherited dictionary rather than merging entries. Levels own their painted placements and reward overrides.

The game uses 256×240 logical framing with window-resolution canvas_items rendering. The bordered, resizable window starts at 768×720; fractional aspect-preserving scaling fits other sizes with bars as needed. Enable **Game → Presentation → Integer Scaling** to fit the canvas at a whole-number scale. At 900×844, the setting centers a 768×720 canvas inside the window. Shader masks can render smoothly while foreground artwork uses nearest sampling.

## Source configuration and ownership

`Game.stages` defines completion order and lists 1-1, 1-2, 1-3, 1-4, 2-1, 2-2, and 2-3. Clearing the final registered stage returns to the title. **Game → Start Stage Override** selects the starting BaseLevel scene for new runs. Leave it empty to use the first entry. Selecting a registered scene starts at its position in the list. A scene outside the list returns to the title after ordinary completion. The title backdrop is configured separately. Single-stage test fixtures assign `game.stages.assign([scene])`.

Use typed GameHandler methods/properties and `player_status` for score, coins, lives, form, top score, stage label, and timer values. Generic `set_session_value()` / `get_session_value()` are for run metadata such as area/arrival IDs; reserved-key writes are rejected. The existing `session_value_changed` signal carries both typed-value and metadata notifications.

In `scenes/main/game.tscn`, select **Game → Gameplay → Enemy Limit** to set the number of enemies that can be active at once. The default is **5** and standalone level previews also use five. Set it to **0** to disable enemy spawns. The single power-up slot is independent. Ordinary painted spawners attempt once per area load and do not retry after rejection. Reward blocks may explicitly replace the current power-up. Unlisted categories remain unlimited and untracked.

Paint one **Goomba Pair Spawner**, **Goomba Triplet Spawner**, or **Green Koopa Pair Spawner** marker on the 16×16 **EnemyLayout** at the NES trigger column. The group activates when the marker enters the 48-pixel lookahead. Its first member starts at the last visible pixel on the camera's right edge, with members 24 pixels apart. The editor draws the trigger in gold and outlines each member's spawn cell in cyan at the first eligible camera position. Toggle **Show Group Spawn Preview** on **EnemyLayout** to hide the guides. If the group runs out of enemy slots during activation, the remaining members are skipped for that area load.

Paint **Red Koopa Spawner** on **EnemyLayout** in the cell immediately above its support. A walking Red Koopa turns at ledges, and its kicked shell can roll off them.

Paint **Red Parakoopa Spawner** on **EnemyLayout** to place a Red Koopa that flies vertically. The marker sets its starting position. Its flight range follows the reference's starting-height rule. The cyan guide marks the spawn point and both turning heights. Toggle **Show Flight Paths** on **EnemyLayout** to hide it. The first stomp removes its wings and awards 400 points, after which it walks and uses the shared shell states. In 1-3 the two markers are at (74, 4) and (114, 5).

Paint **Green Parakoopa Spawner** on **EnemyLayout** for the hopping variant. Each marker activates one enemy at that cell. The 2-1 markers are at (151, 12), (169, 12), and (171, 12).

Paint **Blooper Spawner** on the underwater **EnemyLayout** at the intended start cell. Blooper starts eight pixels below the marker's top edge and uses the normal enemy slot limit. The slot determines whether a turn aims toward Mario or follows his movement direction.

Instance [Swimming Cheep Cheep Spawner](../scenes/entities/spawners/swimming_cheep_cheep_spawner.tscn) under an underwater area's **WorldObjects**. The marker's X sets the camera's left-edge activation point. **Active Distance** limits how far the camera can travel while the stream is active. Leave it at 0 for a stream with no end marker. The spawner shares the first three enemy slots with other enemies and waits 32 physics ticks after each successful spawn. Both colors draw from the same eight spawn heights. Leave **Favor Red** off for World 2's color distribution. The editor draws labeled camera-left start and stop lines. In 2-2 they are at area-local X931 and X2723. Fish already spawned keep swimming past the stop line.

## Place moving lifts

Instance `scenes/entities/spawners/lift_spawner.tscn` under the area's **WorldObjects**. Its X position is the lift's left edge. Put the marker at the incoming edge and set **Direction** to **Up** or **Down**. For a 240 px view starting at Y=0, use Y=248 for Up or Y=−8 for Down.

**Initial Offsets** lists each lift's starting distance from the marker, in pixels along the travel direction. The default is one lift at offset 0. Add distinct offsets to stagger multiple lifts in the same lane. Each lift cycles independently, with a replacement at the incoming edge when it exits the far edge. Lifts use no enemy slots.

For a single back-and-forth lift, instance `scenes/entities/spawners/single_lift_spawner.tscn` under **WorldObjects** and choose **Horizontal** or **Vertical** in **Axis**. Place the node at the left end of the platform's starting surface. A horizontal lift starts moving left. A vertical lift starting in the upper half of the reference playfield moves down first. The camera activates each spawner once per area visit. The lift is freed when it leaves the camera's cleanup bounds.

Both spawners offer **Platform Width**. Small, Medium, and Large are 32, 48, and 64 pixels wide. Medium is the default. The width controls both the artwork and the contact surface.

On a single lift, leave **Travel Distance** at −1 to use the original oscillation, or set it to 0 for a fixed platform. A positive value sets the distance from the marker to the turn point, left for horizontal lifts and down for vertical lifts. The lift travels back and forth at 15/16 pixel per physics tick. In 1-4, the Small horizontal lift uses the original oscillation.

Set the single lift spawner to **Right on Landing** for a cloud platform. It waits at the marker, moves right at 1 px per tick after Mario lands, and keeps moving after he steps off. In 2-1, the medium platform is at (256, 160) in Coin Heaven.

The 2D editor draws guides from the platform's left edge to its right edge at the travel limits. Vertical lifts show both sides of the travel lane. Single lifts mark the starting surface, and repeating lanes mark the starting surfaces from **Initial Offsets**. **Right on Landing** shows the full starting surface and a rightward arrow that indicates one-way travel.

## Paint world coins

Paint **Coin** or **Coin Alt** on **EntityLayout**. **Coin Alt** uses the alternate frames from the area palette for colored backgrounds. Both use the same animation timing and pickup behavior. In 2-2, **Coin** matches the deep-blue water tiles. The underwater **Coin Alt** frames match the lighter blue.

## Configure a vine reward

Paint a **Reward Brick** on **EntityLayout** and select **Apply Vine Reward** in the Block Rewards brush, then click the painted brick. The editor previews the vine tip in the area palette. In 2-1 the vine reward is at (83, 5). It starts drawing at 8 px of growth and first becomes climbable at 32 px.

## Configure a Coin Heaven arrival

Add a node with the **CoinHeavenArrival** script under the level's **Presentations** node. Assign the source area and vine reward cell, then assign the destination area and its **Arrival** endpoint. The marker sets Mario's starting feet position below the destination screen. Paint **Cloud ground** on the destination's **GroundLayout** under the scripted walk-off. In 2-1, the marker is at (64, 272) in Coin Heaven and the landing surface begins at Y 208, with a one-tile gap for the vine.

Set the cloud area's **Fall Destination** to the main area's return endpoint. The route uses the shared area transition when Mario falls below the cloud area. In 2-1, **CoinHeavenReturn** is at (2608, 32), frames Mario's sprite 40 px from the left edge, and locks controls for the first 26 active fall ticks.

## Paint springboards

Paint **Springboard** on **EntityLayout**. The painted cell is the top of the uncompressed spring. In 2-1 it is at (188, 11), before the wall at columns 190–191. Jump onto it and press Jump again during compression for the high bounce.

## Try flying Cheep Cheeps

Open `tests/fixtures/flying_cheep_cheep_sandbox.tscn` and press F6. Its two placed fish claim ordinary enemy slots and finish one flight each. Restart the scene to try again. The bridge is solid for Mario and does not block the fish. **Launch Velocity** uses pixels per 60 Hz physics tick; the initial fraction properties support matching reused NES slot state. The actor's stomp rebound is -180 px/s, equivalent to the reference's -3 integer speed byte. For an ongoing stream, open `tests/fixtures/flying_cheep_cheep_spawner_sandbox.tscn` and press F6.


Instance `scenes/entities/spawners/flying_cheep_cheep_spawner.tscn` under an area's **WorldObjects**. Its map-column properties are measured from the marker's area-local X, in 16 px columns. **Start Column** starts the stream; **Stop Column** stops new launches while existing fish finish their flights. Leave Stop Column at -1 for an endless sandbox stream. **Restart Columns** supplies additional start commands for a halfway entry beyond the first start. The editor guides mark the camera-left positions where those columns begin streaming; the queued command takes effect on a later enemy update.

2-3 uses Start Column 26, Restart Columns `[137]`, and Stop Column 197. The start guides are at camera X64 and X1824; the stop guide is at X2784. The shared column clock models the two columns parsed over eight tasks for every 32 px of forward camera movement. At the halfway camera X1792, the stream waits for the second start command. Fish use only enemy slots 0–2, respect **Game → Enemy Limit**, and retain position fractions when a flying fish reuses its slot. Cooldowns are selected from 16, 96, 32, and 72 ticks. Launch offsets and horizontal speeds depend on Mario's speed and three random bytes. Pause and gameplay suspension freeze the source; area unloading removes the source and its fish. Set **Submerged Swimmer Origin** to a marker-relative NES origin to enable an ordinary below-screen swimming entry; negative X disables it. 2-3 uses `(2304, 248)`. The entry shares the enemy registry, activates through the same 48 px column lookahead, and is skipped if it has already passed the visible right edge. It swims left and bobs according to its slot; horizontal cleanup or NES Y256 retirement releases it. It does not respawn during the same area visit. Depending on the available slot and initial bob direction, its lifetime varies; it temporarily reduces flying capacity when assigned slot 0, 1 or 2.

## Place a castle bridge

Instance `scenes/entities/castle/castle_bridge.tscn` under the Castle area's **WorldObjects**. Align its origin to the top-left cell of the deck. **Deck** is a solid TileMapLayer, **Chain** is decorative, and **Axe** sits above the step at the far end. The axe shares the global palette animation and emits `touched` once when Mario lands on it.

Instance `scenes/levels/endings/castle_ending.tscn` under **Presentations** and assign it to the level's **Ending Presentation**. Set **Area ID**, **Bridge Path**, and **Rescue Path** to the ending area and its bridge and rescue scenes. The paths start at the area node. **Approach Camera Left** and **Rescue Camera Left** are measured from the area's origin. The axe starts a hold, and the presentation releases the approach stop when the scripted walk starts. In 1-4 the camera holds at 2022 px and scrolls to 2304 px during the walk.

The 2D editor draws labeled guides for **Approach Camera Left**, **Rescue Camera Left**, and **Boss Fall Cutoff Y** on each placed Castle Ending. The vertical lines mark the left edge of each camera position. The horizontal line marks the fall cutoff across the approach view. The guides follow the area selected by **Area ID**.

Set **Boss Path** relative to the ending area to link its boss actor. With a live boss, Castle Ending holds the camera as the bridge removes the chain and then its deck cells from right to left every four physics ticks. Each tile loses its collision, and the final removal emits `collapse_finished`. With an empty path, missing boss, or defeated boss, the axe disappears and the scripted walk begins on tick 3. The deck and chain stay intact.

Instance `scenes/levels/endings/castle_rescue.tscn` in **WorldObjects**. Place its origin at the final camera's top-left so the text aligns with the NES tile grid. Set **CastleRescue → PlayerStop** on the floor where Mario or Luigi should stop and enter Idle. The rescue scene provides Toad and the two messages. Castle Ending starts the castle-clear cue with the walk, reveals the character's thank-you once the camera settles, then shows the rescue message 128 ticks later. The stage list supplies the next stage.

## Deliberate gameplay differences

Enemy stomp scoring omits the NES shared StompTimer score modifier. A stomped Koopa instead has a shell-local 12-tick grace window; a kick does not refresh it. These rules are separate from the independent timed-coin windows above.

Area and pipe arrivals use a shared 17-active-physics-tick hold (about 0.28 seconds at 60 Hz), including grounded arrivals. Animated exits wait before emergence and release controls immediately afterward. Direct arrivals apply the input lock after placement. Death respawns restore control when the stage is revealed.

Add `scenes/entities/spawners/fire_bar_spawner.tscn` under an area's **WorldObjects**. Place its origin at the pivot and set **Length**, **Speed**, and **Direction** in the Inspector. The editor draws the pivot and nominal tip reach of 40 px for Short or 88 px for Long. To mount a Fire Bar on a spent block, paint the block on **GroundLayout** and put the spawner at the tile center. The first 1-4 bar is centered at (488, 168) pixels, over cell (30, 10).
