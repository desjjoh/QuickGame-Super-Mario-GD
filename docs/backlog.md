# Backlog

## Brick breaking

Breaking physics, themed debris, the cached shatter cue, delayed follow-up bonk, and 50 points without a popup are implemented. Accepted bumps and breaks collect a world coin directly above the block. Goombas, Koopas, shells, and mushrooms share ordered block-hit delivery.

- Compare receiver selection near brick seams if a block hit unexpectedly misses or catches an actor. The game currently uses a strip query where the NES uses an actor terrain probe.

Keep the accepted cached audio. Live shared noise-channel playback was removed after causing stutter.

## Level and entity authoring

- Define restart behavior for standalone F6 levels.
- Add standalone power-up painting when needed; no dedicated power-up layer currently exists.

## Presentation and reference checks

- Revisit the 1-1 secret-room return presentation. From the overworld switch, emergence starts on tick 29 in Godot and tick 25 in Mesen. Both rises take 96 ticks, and the Goombas now match Mesen's spacing at release (152 px and 176 px ahead). Keep the shared 17-tick arrival lock and emergence-based enemy activation when reviewing the four-tick loading gap.
- Revisit Fire Bar starting angles. Compare the third bar in 1-4 across different approach speeds before deciding whether to reproduce the NES's reused angle.

- Implement the later castle attack and reveal variants as those stages are built. Review the traced front and rear Starman outcomes before implementing that interaction.
- Compare castle-firework timing, blast playback, and the final music/hold handoff with Mesen.
- Compare generated cues and music with Mesen, including loop seams, pulse takeover, and voice balance.
- Reproduce occasional camera hitching at high refresh rates in a rendered build.
- Reproduce the intermittent moving-Koopa stray pixel and investigate fractional-position compositor differences.
- Reproduce the natural right-edge shell/pair contact report. Controlled rejection tests verify retry behavior but do not establish that the reported encounter is resolved.
- Extend movement comparison beyond the current flat-ground landing/turn/re-jump captures to broader terrain and rendered play.

## Verification

- Requalify the full suite when requested. The game-over, jump benchmark, timer fixture, Mario form fixture, and resolution-aware shadow checks now pass their focused checks.
- Resolve the default audio bus layout by resource path on a fresh import. A clean copy reports an unrecognized audio layout UID before the cache is populated. Using the layout's resource path in a separate copy imports without errors.
- Investigate native shutdown failures if reproducible. Regression teardown addresses the isolated deferred audio cleanup warnings; this does not certify every native shutdown path.
