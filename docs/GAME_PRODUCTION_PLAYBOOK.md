# Calico Yarn Quest implementation handbook

This handbook maps the working horizontal-platformer reference to its extension points. The generated [README](../README.md) owns the shared [workflow](../README.md#shared-game-development-workflow), [art and audio production](../README.md#shared-art-and-audio-production), [typography](../README.md#default-typography), and [delivery](../README.md#shared-web-runtime-and-delivery-contract) requirements. Keep this document specific to the implementation.

## Runtime ownership

```text
data/stages/                    Authored course definitions
config/tuning.json              Typed tuning descriptors and defaults
scripts/
  game.gd                      Run/stage routing, world, timer, HUD, results
  stage_catalog.gd             Ordered IDs and validated course loading
  player.gd, touch_input.gd    Movement, actions, transient input
  entities.gd, yarn_ball.gd    Fish, robots, blocks, exits, projectiles
  run_score.gd, save_store.gd  Awards, immutable results, local persistence
  tutorial_director.gd         Event-driven player onboarding
  title_screen.gd              Profile, language, loading and Start
  pause_menu.gd                Pause and guarded navigation
  menu_modal.gd, menu_style.gd Shared modal/focus ownership and presentation
  settings_panel.gd            Persistent player audio/display/motion controls
  leaderboard_panel.gd         Local top-ten standings
  tuning_store.gd              Validation, requested/active values, run integrity
  tuning_panel.gd              Descriptor-driven owner-preview controls
  game_audio.gd, audio_catalog.gd  Music lifecycle and semantic cue routing
  visual_effects.gd            Bounded feedback and warm filter
  world_art.gd, viewport_policy.gd Responsive scenery and game surface
  sprite_grounding.gd          Alpha-aware visual foot alignment
  brick_surface.gd, surface_finish.gd Continuous textured terrain edges
autoload/i18n.gd               Translation lookup and saved locale
localization/                  English and Simplified-Chinese strings
test/                          Gameplay, presentation and export regressions
```

## Courses and the complete run

The route is Title → Sunlit Nook → stage-clear panel → Lofty Lounge → Victory. Timeout produces Defeat. Restart creates a new run from the first course; advancing preserves run score and resets stage actors, objective, checkpoint and timer.

| Definition | Width | Platforms / trees / blocks / placed fish | Exit requirement |
|---|---:|---|---|
| `data/stages/sunlit_nook.json` | 7,800 | 19 / 3 / 7 / 33 | Reach the exit |
| `data/stages/lofty_lounge.json` | 8,500 | 18 / 3 / 10 / 47 | Collect 12 fish, then reach the exit |

Both courses default to 180 seconds and 11 robots from their spawn lists. Falling or contact damage returns the cat to its current checkpoint and costs 10 seconds. The real-physics traversal test completes both courses in about 61 seconds of simulated active play; this compact reference does not establish a 10–15-minute human session.

To add a course, add its JSON and ID to `StageCatalog.STAGES`, then its `name_key` in both locales. Definitions contain `id`, `name_key`, `world_width`, `spawn`, `goal`, `checkpoint`, `grounds`, `platforms`, `trees`, `blocks`, `fish`, `enemies`, and `required_fish`. Grounds/platforms/trees use position-and-size pairs; other placements use points. `StageCatalog.validate()` rejects malformed/nonfinite geometry and impossible fish counts; loading failure has a usable localized error route. Validate the new route through actual movement and collisions, then update content-count and score assertions.

`game.gd` owns stage freeze and terminal guards. New pickups, combat rewards or callbacks must respect these guards so late events cannot change a completed stage or finalized result. Yarn uses swept collision and a ten-projectile cap; a missed shot can rebound three times before disappearing.

## Grounding and terrain geometry

| Object | Physical geometry | Visual anchoring |
|---|---|---|
| Cat | Capsule radius 18, height 52, offset `(0, -2)`; feet at local y = 24 | 192×192 source canvas at scale 0.62; idle plus 18 run frames |
| Robot | Rectangle 52×26, offset `(0, 6)`; feet at local y = 19 | Source canvas fits a 60-unit square; stomp squash stays anchored at the feet |
| Reward block | Stationary 52×52 rectangle | 8-unit outer corner radius; activation moves only the artwork up 10 units and back |
| Ground/platform | World rectangle defined by stage data | 256×256 source region tiled at 168 world units, with an 8-unit outer corner radius |

`SpriteGrounding.alpha_region()` caches each texture's used alpha rectangle. `canvas_rect()` keeps the authored horizontal canvas center and places the alpha bottom at the physical foot: `canvas_y = foot_y - alpha_bottom * pixel_scale_y`. Draw the full source canvas; independently stretching each frame's visible bounds would change body proportions and horizontal pivots. Apply recoil, bobbing and squash to visual scale, leaving the physics body unchanged. Running selects frames at 12 fps while grounded and moving faster than 40 units/second.

`SurfaceFinish` constructs one rounded perimeter with eight segments per corner, intersects it with each tile, and computes UVs against the full tile rectangle. Only the outside perimeter is rounded: internal joins remain opaque and the final partial tile is clipped without stretching. Physics collision remains separate. Preserve this separation when changing texture resolution or platform length.

The authored route's maximum required rise is 150 units, with 24 units of jump clearance. At default jump power 800 and gravity 1,750, the theoretical held-jump apex is `800² / (2 × 1750) ≈ 182.86`. Keep `REFERENCE_MAX_PLATFORM_RISE`, `MIN_JUMP_CLEARANCE`, tuning cross-field validation and real held-jump/traversal tests consistent when changing geometry or movement.

## Source media and presentation

The restore manifest contains 41 media files: 27 cat-theme images, one foreground image, nine audio files and four font files. `asset-provenance.json` records inherited identities; original generation prompts, tools and editable art/audio sources are unavailable and are not asserted here.

| Source under `assets/template/` | Runtime owner and purpose |
|---|---|
| `cat/idle.webp`, `cat/run/frame_00.webp` … `frame_17.webp` | `player.gd`: shared-scale cat animation |
| `cat/robot.webp`, `cat/fish.webp`, `cat/felt-special-block.webp` | `entities.gd`: robot, fish and reward block |
| `cat/yarn.webp` | `yarn_ball.gd`: projectile |
| `cat/felt-ground.webp` | `brick_surface.gd`: tiled ground/platform texture |
| `cat/cat-tree.webp` | `game.gd`: furniture surface artwork |
| `cat/warm-background.webp` | `world_art.gd`: screen-space background, horizontal camera factor 0.08 |
| `generated/foliage_near.webp` | `world_art.gd`: low foreground strip, camera factor 0.16, above world/below HUD |
| `cat/title-key-art.webp` | `title_screen.gd`: title composition |
| `audio/*.ogg` | `audio_catalog.gd`: inherited soundtrack and eight final effects |
| `fonts/` | Project/menu themes and `scripts/manus/game_fonts.gd`; see README typography |

`ViewportPolicy.BASE_SIZE` is a 1280×720 design reference. Default display mode retains a centered 16:9 surface; adaptive mode bounds the aspect between 1:1 and 16:6. Smaller windows use a smaller logical UI surface and a matching camera `world_scale()` so text/touch controls can reflow while authored world geometry stays unchanged. Size menus against the current viewport, preserve letterbox input boundaries, and clear transient touch/action state when opening a modal or leaving gameplay.

`VisualEffects` caps active bursts at 12 and particles per burst at 48. Run trails, collection, impact, death, checkpoint and finish feedback consume gameplay events. Reduced motion removes trails and uses static bursts; effects never change collision or awards. Stage/retry transitions clear outstanding feedback.

## Audio, score and persistence interfaces

The reference intentionally retains its supplied 64.4-second BGM and eight effects. This inherited-material exception does not establish custom-generation provenance. `GameAudio.begin_title()` waits for a real gesture on cold boot; idempotent `begin_game()` reuses the selected music. `stop_game()` clears active playback. The canonical browser adapter remains in `scripts/manus/`; the director owns one music player and eight shared one-shot voices.

Gameplay calls `GameAudio.play(cue)`; menus needing explicit feedback call `play_ui(cue)`. Standard buttons, sliders, option lists and text submission are already hooked centrally, including paused menus. Register new semantic paths, gain/pitch treatment and cooldowns in `audio_catalog.gd`; avoid duplicate UI hooks. Button metadata `audio_cue` can select a back/cancel cue. Player controls use `get_bus_volume`, `set_bus_volume`, `is_bus_muted` and `set_bus_muted` for `Master`, `Music`, `SFX` and `UI`, persisted separately in `user://audio.cfg`.

`RunScore.award()` owns fish (100), robot (250), block (50) and stage-clear remaining-second (10) awards. `finalize()` returns a once-only result snapshot, including eligibility and configuration hash. `SaveStore.record_run()` adds the player name, rejects duplicate/malformed records and retains ten entries sorted by score descending, duration ascending, timestamp ascending, then run ID. `user://save.json` holds local profile/records/tutorial version; there is no network leaderboard.

Names are limited to 24 characters and 96 UTF-8 bytes, with unsupported glyphs and control/markup characters rejected. `I18n.t(key, placeholders)` owns player-visible copy in English and Simplified Chinese. `TutorialDirector` advances from real move/jump/shot/damage/checkpoint/pause events; each step has an 18-second fallback and Skip. Completion is versioned in `SaveStore`, and title replay requests a fresh tutorial.

## Extending tuning without changing a run unexpectedly

`config/tuning.json` version 3 contains 30 descriptors across UI, Gameplay, Audio, Player, Enemies and Environment. Add a descriptor with type/range/default, localized label/description, application boundary and integrity classification; then connect its owner to the active value and add a relevant assertion.

| Boundary | Current application |
|---|---|
| `LIVE` | Camera, display/HUD, reduced motion, four audio multipliers, filter, particle density |
| `NEXT_ACTION` | Yarn attack cooldown |
| `NEXT_SPAWN` | Yarn speed, lifetime, gravity and launch speed |
| `NEXT_STAGE` | Enemy speed, gravity and count |
| `NEXT_RUN` | Movement, jump/gravity/coyote/buffer/stomp values and stage time |

`TuningStore.set_value()` / `set_values()` validate requested values; consumers read active values with `get_value()`. Owners call the appropriate `apply_boundary()`; requested and active values can differ. Applying non-default gameplay settings taints the current run permanently, even after reset; cosmetic settings preserve eligibility. Debug drafts persist in `user://platformer_tuning.json` and are ignored by release/checkpoint builds.

Normal Settings use `set_player_setting()` / `get_player_setting()` for the cosmetic whitelist, stored in `user://platformer_player_settings.json`. Audio preferences have their own store; debug audio values multiply them. The owner-preview tuning panel and shortcuts are gated by `owner_preview_enabled()` and do not appear in release/checkpoint builds.

## Focused regression map

Use the [README verification commands](../README.md#verification-commands-and-limits) for isolated storage, engine/export setup and handoff. Choose tests that exercise the behavior changed:

| Change | Existing checks |
|---|---|
| Stage data, score, results, names, tutorial | `test/gameplay_contract.gd`, `test/traversal.gd` (real physics) |
| Player grounding, surface shape, block collision | `test/player_grounding.gd`, `test/terrain_regression.gd`, `test/finish_regression.gd`, matching render tests |
| Yarn combat or stomp timing | `test/yarn_combat.gd`, `test/yarn_bounce.gd`, `test/stomp_regression.gd` |
| Menus, responsive input and localization | `test/ui_contract.gd`, `test/responsive_layout.gd`, `test/localization.gd`, `test/acceptance_capture.gd` |
| Tuning application/integrity or effects | `test/tweak_regression.gd`, `test/vfx_regression.gd` |
| Cue routing, music lifecycle, category controls | `pnpm test:audio`, `test/audio_completion.gd`; Addon repository `pnpm run test:game-bgm-browser` for adapter/lifecycle changes |
| Startup or exported dependencies | `test/startup_loading.gd`, `pnpm check`, `pnpm verify-export` |

Native render captures cover real game states; keep their images outside the project. Export filters include `localization/*.json`, `config/*.json` and `data/stages/*.json`. Preserve the distinction between contract/pack checks, rendered evidence, and user acceptance of the final browser experience and audio mix.
