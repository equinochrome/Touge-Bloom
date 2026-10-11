# Scenic Drift — Roblox Prototype Plan

## Context

The workspace (`Car Game/`) is empty: this is a greenfield Roblox project. The goal is a drift game where each seeded, procedurally generated closed circuit feels like a new scenic destination, and drifting is scored on angle, speed and how long combos last. Driving feel comes before strict simulation.

The first prototype needs one car, one setting (forest valley), one small generated circuit and basic drift scoring. The car gets tuned on a fixed test circuit **before** procedural generation is added. This document is a plan only. It contains no code.

**Assumptions (change these if they're wrong):**
- Scripts are written in VS Code and synced with **Rojo**. Assets live in the `.rbxl` place file or in `.rbxm` model files. Working Studio-only is also possible; only the folder layout below would change.
- Target hardware is PC and gamepad first, with mobile as a performance target. Mobile touch controls come after the prototype.
- Scale: the car is about 7 × 15 studs. The road is 30 studs wide. A "small" circuit is about 1,500–2,500 studs long, inside a map of about 1,200 × 1,200 studs.

---

## 1. Core technical decisions

| Area | Decision | Why |
|---|---|---|
| Car physics | **Custom raycast-suspension car**: a single invisible chassis body, four downward raycasts, and our own spring, damper and tire forces applied with impulses each frame. No physical wheel constraints. | Gives full control over drift feel. Avoids the jitter of HingeConstraint wheels and makes road seams far less noticeable. |
| Physics authority | The car's network owner is the driving client. The server only spawns it and checks scores for plausibility. | Input feels instant, which drifting needs. |
| Road visuals | An **EditableMesh** ribbon generated from the centerline, split into chunks that share edge vertices. UVs follow arc length. Built on each client from the seed. | Smooth, seamless and curved. Avoids the stair-stepped look of part chains. |
| Road collision | Invisible thin **box segments** about 4–6 studs long. They overlap slightly and follow the local pitch. They're tagged `Road`, have CanCollide/CanQuery on, and are built by the server. | Raycasts hit predictable flat geometry. Tiny steps between boxes get absorbed by the suspension. |
| Fallback road | The "two WedgeParts per triangle" technique, if EditableMesh fails the spike in Phase 0. | Proven, though it uses more instances. |
| Terrain | Roblox **smooth Terrain** written with `WriteVoxels` using fractional occupancy, shaped from a heightfield that blends toward the road. | Smooth, not blocky. Built-in grass, rock and water materials. Free grass decoration. |
| Vegetation | Mesh assets placed by **seeded Poisson-disk sampling**, built on each client from the seed and loaded in chunks near the player. | No replication cost. Density can scale with graphics quality. |
| Determinism | One `Random.new(seed)` per subsystem, each with a derived seed (road, elevation, terrain, vegetation, naming). Arrays only, with ordered iteration and never `pairs()` order. Plus a `GENERATOR_VERSION` constant. | Re-entering a seed rebuilds the identical circuit. Tweaking vegetation never shifts the road. |
| Server/client split | The server picks the seed, generates the centerline, writes the terrain and builds road collision. Clients receive the seed and build the road visuals, curbs, lines, vegetation and props locally. | Keeps replication small. Every client produces the same result because generation is deterministic. |

---

## 2. Scripts vs. assets

### Built by script (procedural or Luau)
- Car controller, tire model, suspension, assists, camera, input
- Drift scoring, combo state machine, lap and checkpoint logic, HUD layout
- Track centerline, elevation, validation, repair and reroll
- Road ribbon mesh, curbs (red and white strips as mesh ribbons), painted edge and center lines (thin ribbons), start/finish line
- Terrain heightfield, road shaping, material painting, water fill
- Vegetation and rock placement, plus chunk loading and unloading
- Lighting, Atmosphere, Clouds and post-processing presets for each setting
- Destination identity (name, time of day, mood) from the seed
- Skid marks (Beams or Trails driven by script), tire smoke emitters (scripted rate)

### Must be modeled (Blender) or sourced (Creator Store or purchased; check licenses and remove any embedded scripts)
| Asset | Notes |
|---|---|
| Car body mesh | Low-poly (~5–10k tris). Wheels are separate meshes. Brake/tail lights as separate parts for glow. Uses a SurfaceAppearance PBR set. |
| Wheel and tire mesh | One mesh, mirrored for left and right. |
| Asphalt texture set | Albedo, normal and roughness. Tileable along the road's length. A subtle worn racing line is optional. |
| Curb and line textures | Optional. Plain colors also work for the first pass. |
| Trees | 2–3 conifers and 1–2 broadleaf. Each ≤ ~2k tris. Proper pivot at the trunk base. Leaves use alpha cards sparingly. |
| Bushes, ferns, rocks | About 3 bushes and 4–5 rocks in a few sizes, so they read as natural. |
| Skybox | 6 faces, or use the built-in sky combined with Atmosphere and Clouds. |
| Guard rail or barrier mesh | For drops. Needed for coastal and mountain settings later; optional in the forest prototype. |
| Audio | Engine loop at about 3 RPM layers, tire squeal loop, impact sounds, and forest ambience (wind, birds, stream). |
| Particle textures | Tire smoke and dust. |
| Terrain MaterialVariants | Optional. Custom grass, forest floor and rock textures to lift the look beyond the default materials. |

---

## 3. Codebase layout (Rojo)

```
Car Game/
  default.project.json, selene.toml, stylua.toml
  src/
    shared/                       -> ReplicatedStorage.Shared
      Config/        CarConfig, ScoringConfig, GenConfig, Biomes/ForestValley
      Gen/           Rng, Noise (fBm on math.noise), Spline (centripetal Catmull-Rom +
                     arc-length resample), TrackGenerator, TrackValidator,
                     Heightfield (natural height + road blend), Placement (Poisson),
                     DestinationNamer, TestCircuits (hand-authored control points)
      Car/           TireModel, DriftMath (slip angle, drift angle)
      Scoring/       DriftScorer (pure state machine, fed telemetry)
    server/                       -> ServerScriptService
      CircuitService, TerrainBuilder, RoadCollisionBuilder, CarSpawner, ScoreService
    client/                       -> StarterPlayer.StarterPlayerScripts
      CarController, CameraController, RoadVisualBuilder, VegetationStreamer,
      DriftHUD, Effects (skids/smoke/audio), LightingPresets
    tests/                        -> ServerScriptService.Tests (Studio-only runner)
```
Assets such as the car model, tree and rock meshes and sounds go in `ReplicatedStorage.Assets` inside the place file. Rojo does not manage them.

Pure modules like `Spline`, `TrackGenerator`, `TrackValidator`, `DriftScorer` and `TireModel` take no Instances, so tests can call them directly.

---

## 4. Driving model (what "feel over simulation" means in practice)

1. **Chassis.** A box body with tuned density. A dense invisible "ballast" part is welded low to bring the center of mass down. The collider is rounded or raised so it never touches the road; the raycasts do all the ground contact.
2. **Suspension.** For each wheel, cast a ray from its mount point. The spring and damper force acts along the hit normal. Compression gives the **wheel load**, so weight transfer under braking, throttle and cornering comes out of this naturally. An "arcade load-shift" multiplier exaggerates it if needed.
3. **Tires.** Lateral force comes from the slip angle through a forgiving curve: linear up to a peak at about 8°, then sliding down to a **plateau at about 75% grip** instead of collapsing. That plateau is what makes a drift holdable. Grip scales with load^0.9. A friction circle means that throttle on the driven rear wheels takes away lateral grip, which gives power oversteer. The handbrake multiplies rear lateral grip by about 0.4 for initiation.
4. **Assists**, each tunable and each able to be turned off:
   - **Countersteer assist:** while sliding, steering drifts toward the direction of travel and blends with player input.
   - **Yaw damping** above roughly 50° drift angle, plus a soft cap of about 65° to prevent spins.
   - **Drift sustain:** lower longitudinal drag while sliding, so speed holds through a corner.
   - Speed-sensitive steering lock, and steering-rate smoothing for keyboard input.
5. **Camera.** A chase cam that follows a blend of the car's heading and its velocity direction, so the drift angle is visible. FOV widens with speed, and there's slight lag on yaw.
6. **Tuning workflow.** Every CarConfig value is mirrored as an **Attribute** on the car model. The controller reads the Attributes each frame, so values can be changed live in Studio during a Play test. Good values are copied back into `CarConfig`.
7. **Frame-rate robustness.** Everything is scaled by delta time, the time step is clamped, and the physics substeps when frames are long. The car's behavior is checked at 30 and 60 FPS.

---

## 5. Drift scoring

- **Drift angle** is the angle between the chassis forward vector and the velocity, both flattened to the horizontal plane. It only counts when speed is above about 25 studs/s, at least 3 wheels are on the ground, and the wheels are on surfaces tagged `Road`.
- **Valid drift:** between 15° and 90°. Above about 110° counts as a **spin**.
- **Points per second** = base × angleFactor (ramps from 15° to 45°, then flat) × speedFactor (clamped from speed / reference speed) × combo multiplier.
- **Combo:** points build up in a *pending* pool. The multiplier grows by +0.1 per second of continuous drift and +0.5 for each left-to-right transition, capped at ×5. After a drift ends there is a **1.5 s grace window** to start the next one and keep the chain. When the window expires, the pending points are **banked**.
- **Combo fails** (pending points lost) on a collision impulse above a threshold, going off-road for more than 0.5 s, a spin, or a reset.
- **Laps:** checkpoints every N centerline samples. The game tracks lap time, lap score and best score per seed.
- **Trust:** the client submits banked combos. The server rejects any that exceed the maximum points per second or that don't match the car's movement as the server sees it. That's enough for a prototype.

---

## 6. Procedural circuit pipeline (pure data until the build step)

1. **Control points.** 8–14 points at evenly spaced angles around a center, with angle and radius jitter. Because every point is visible from the center, the loop can't cross itself at the control level.
2. **Smoothing.** A closed **centripetal Catmull-Rom** spline, which avoids cusps and small loops, resampled at **even arc length** (about 4 studs).
3. **Elevation.** A *periodic* 1-D noise along the loop (a sum of seeded sine waves) so start and end meet. Then forward and backward **grade-limiting passes** cap the slope at 8–10% and limit vertical curvature so crests don't launch the car. No banking in the prototype.
4. **Validation.** Each check reports why it failed:
   - Minimum turn radius: at least 45 studs at the centerline, using the circumradius of each sample with its two neighbors.
   - Direction change per sample is within a limit.
   - **No overlap:** a spatial hash finds sample pairs closer than road width + 2 × shoulder + 20 studs whose arc-length separation is large. Any such pair fails.
   - Maximum grade, maximum vertical curvature, total length within range, the road stays above water level plus a margin, and at least 120 studs of straight for the start/finish.
5. **Repair, then reroll.** First, smooth out local violations up to K times. If it still fails, reroll with the derived seed `hash(seed, attempt)`. Because the retry sequence is deterministic, **the same seed always lands on the same final circuit.**
6. **Output.** A `CircuitData` table containing centerline samples (position, tangent, right vector, arc length), the width, checkpoints, the start pose, and a determinism hash.

### Terrain shaping around the road
- **Natural height:** fBm noise plus the forest-valley shape (a broad basin with ridges at the edges, so the circuit sits in a valley that's visible from inside it).
- **Road blend:** for each terrain column, find the distance to the nearest centerline point using a spatial hash.
  - Within half the road width plus a 10-stud shoulder, terrain height = road height − 0.5.
  - From there out to about 40 studs, smoothstep toward the natural height. This automatically creates cuts and embankments.
- **Slope clamp:** embankment slopes are capped so the edges stay plausible. Steep areas get painted Rock.
- **Write:** `WriteVoxels` in 64-stud chunks with fractional occupancy at the surface voxel, which gives a smooth surface. Yield between chunks behind a loading screen.
- **Materials:** Ground or gravel on the shoulder, Grass or LeafyGrass in the open, Rock on steep slopes, Sand and Mud near water. A lake or stream on the valley floor is filled with terrain Water.
- **Hiding gaps:** a *skirt* along each road edge (curb plus a mesh lip extending about 2 studs downward) hides the gap between the 4-stud voxels and the road edge.

### Scenery placement
- Poisson-disk sampling, with each setting defining density per material and altitude band.
- **No-plant zone:** half the road width plus 25 studs, widened to 40 studs on the outside of corners, so drifters have run-off.
- Trees have trunk-only collision. Small props have no collision. A few "hero" spots per circuit (a lone tree, a lake view, a rock outcrop) are picked by the seed.

### Destination identity (the creative twist)
The seed also picks a generated name (for example "Hollowpine Valley"), a time-of-day preset (golden hour, misty morning or overcast), and a fog and atmosphere mood. A **destination card** shows on load along with the seed, so players can share it.

---

## 7. Development phases and completion criteria

### Phase 0 — Setup and technical spikes
- Rojo project, linting and formatting, place file, an empty test map.
- **Spike A:** a curved 300-stud EditableMesh road ribbon in chunks, with a PBR or texture look. Confirm it works in a published test place and how much memory it uses.
- **Spike B:** a raycast suspension box resting on and driving over the overlapping collision boxes.

**Done when:** sync works; the ribbon shows no visible seams between chunks; the test body drives over the box seams without visible bumps; the road technique is chosen (EditableMesh or the wedge fallback).

### Phase 1 — Car feel on fixed test circuits
- Car asset imported, CarController, tire model, assists, camera, keyboard and gamepad input, skid marks, smoke and engine audio.
- Test areas: a flat **skidpad**, plus a **hand-authored loop** from `TestCircuits` run through the same spline, road and collision builders that the generator will use later.

**Done when:**
- A keyboard player can hold a 30–50° drift through a long sweeper for 5 s or more.
- Left-to-right transitions work.
- The car recovers from a near-spin with countersteer.
- The car sits still without jitter.
- Behavior is the same at 30 and 60 FPS.
- 3 playtesters rate it "fun to slide" without needing instructions.

### Phase 2 — Drift scoring and HUD (still on the fixed circuit)
- DriftScorer, HUD (angle, combo multiplier, pending and banked points), checkpoints and laps, ScoreService plausibility check.

**Done when:** tests with synthetic telemetry cover chain, grace window, transition bonus, each fail cause and banking; in-game numbers match these rules; lap timing is correct over 5 laps.

### Phase 3 — Circuit generator (data only)
- TrackGenerator, TrackValidator, repair and reroll, and a debug view that draws the centerline as Beams or adornments with the elevation profile.

**Done when:**
- A batch run over 1,000 seeds produces 100% valid final circuits, with at least 90% passing within 3 attempts.
- The same seed gives the same determinism hash on server and client, and across sessions.
- Generation takes under 200 ms per circuit.
- A golden list of about 10 seeds with expected hashes is stored as a regression test.

### Phase 4 — Terrain and road integration (forest valley)
- Heightfield, TerrainBuilder, road visuals and collision from CircuitData, curbs, lines, skirts, water, spawn and start line. The fixed test circuit is replaced by the generated one.

**Done when:**
- The car completes clean laps on 20 random seeds with no fall-through, floating or buried road, voxel bumps on the road or impossible slopes.
- Full generation finishes in under 10 s on a mid-range PC.
- No seams are visible at chunk boundaries.

### Phase 5 — Scenery and atmosphere
- Vegetation and rock assets, the Poisson placer, VegetationStreamer with quality tiers, terrain grass decoration, lighting and atmosphere presets, ambient audio.

**Done when:**
- The run-off zone has zero violations.
- PC reaches 60 FPS and a mid-range phone reaches 30 FPS or more at default quality.
- Client memory stays inside the budget (to be set in Phase 0; aim for under 1.5 GB on mobile).
- Screenshots from 5 seeds look clearly different and are never blocky.

### Phase 6 — Prototype loop and polish
- Destination card, seed entry and share, "new destination" button, best score per seed, reset to track, playtest pass.

**Done when:** a new player can join, see the destination, drive and score laps, enter a friend's seed and get the identical circuit, all without developer help.

**After the prototype:** coastal cliffs and mountain pass settings (guard rails, banking, longer circuits), mobile controls, ghosts, multiplayer lobbies, car tuning, bridges and tunnels.

---

## 8. Performance risks and mitigations

| Risk | Mitigation |
|---|---|
| **Vegetation density** (instance count, draw calls, shadows) | Reuse a small set of identical MeshIds and materials so the engine batches them. Use RenderFidelity Automatic. Small props get CastShadow off. Everything gets CanTouch and CanQuery off. Collision only on trunks, with Box fidelity. Detail is streamed in client chunks within about 300 studs; distant trees stay but small props unload. Density scales with the quality level. Terrain grass decoration replaces most grass meshes. Instance budget: about 3k on PC, about 1.2k on mobile. |
| **Terrain generation** (frame hitches, generation time, memory, join replication) | Chunked `WriteVoxels` with yields and a loading screen. Keep the map about 1.2k studs square and limit vertical range. StreamingEnabled stops new players from receiving all the terrain at once. Option: build the terrain on the client from the seed if replication becomes the bottleneck. |
| **Road seams, visual** | Chunks share edge vertices and normals. UVs are continuous along arc length. Collision boxes stay invisible. |
| **Road seams, physical** | Short segments that overlap and are oriented to the local pitch. Raycast suspension with a damped spring. The chassis collider never touches the road. |
| **Gaps where road meets terrain** | Terrain sits 0.5 studs below the road. A downward skirt lip hides the edges. Validation keeps grades gentle so 4-stud voxels can follow them. |
| **EditableMesh limits** (memory budget, device support) | Measured in Phase 0. Chunk sizes stay under the per-mesh limits. The wedge-part fallback is ready. |
| **Lighting cost** (Future lighting plus many shadow casters on mobile) | Few dynamic lights, shadows only on large casters, and post-processing kept light (Bloom, ColorCorrection, subtle SunRays). Test on low quality settings. |
| **Physics** (network ownership handoff, low-FPS instability) | Assign ownership once at spawn. Time step clamped and substepped. Test at 30 FPS. |
| **Determinism drift** (code changes silently altering seeds) | Separate Random streams per subsystem, `GENERATOR_VERSION` stamped into shared seeds, and the golden-seed regression test. |

---

## 9. Verification (how each phase is tested)

- **Pure-module tests** (generator, validator, scorer, spline) run from `tests/` in Studio Play Solo, using a minimal runner script or jest-lua if preferred.
- **Batch seed test:** a server test script generates 1,000 seeds and prints the pass rate, attempts, timings and failure-cause histogram.
- **Determinism test:** the golden-seed hashes are compared on the server and on a client.
- **Driving test:** manual playtest checklists from the phase criteria, using Studio's Device Emulator, plus a real phone for Phase 5 performance. The MicroProfiler and the Developer Console Memory tab are used for frame-time and memory budgets.
