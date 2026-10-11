# Touge Bloom — Claude VS Code handoff

Open the project folder `C:\Users\super\OneDrive\Documents\Car Game` in VS Code. This document is the restart brief for Claude Code. User has requested visible extension work rather than background CLI workers.

## Roles and current state

Read CLAUDE.md, PLAN.md, Design/Project Management.md and Design/Asset Contract.md. Claude owns car mechanics and terrain generation programming ONLY. Codex owns all Blender modeling, asset imports/materials, model integration, scenery and Studio acceptance. Do not edit models, lighting, RoadVisualBuilder or WedgeTriangle.

T1-heightfield completed and passed 53 Studio checks plus independent seam, order and grid-boundary probes. See docs/T1-QA.md. MountainHeightfield and TerrainConfig are pure data, not live voxel terrain generation. Voxel clearance and full-map performance remain untested.

J1-japanese-circuits background worker was stopped at the user's explicit request after no completion report or assigned source output appeared. It is NOT completed or accepted. Queue ownership has been released for resumption; do not dispatch another CLI worker. Preserve partial files if any appeared after inspection and review before replacing them.

## Task order

1. Resume J1-japanese-circuits. Read Design/Japanese Circuit Generation Brief.md, Design/References/Japanese Circuit Reference Board.md and coordination/state/queue.json for exact scope. Only create src/shared/Config/JapaneseCircuitProfiles.luau and src/shared/Gen/JapaneseCircuitGenerator.luau. Profiles: Ebisu North/West, Meihan C, Nikko, historical Minami Chiba inspiration, YZ East and Gunsai. Meihan E is unverified. Use the 13 local photo/map/PDF references. Fictional seeded variation, not surveyed replicas. Width30 studs, radius>=45, length1500–2500, grade<=8%, nonlocal road separation>=70. Validate sampled segments including closing segment, crossings and segment distance, with bounded retries and explicit failure. Compatible with RoadGeometry and seam-safe MountainHeightfield. No init/controller edits or scene changes. Opt-in meaningful selfTest, report unrun tests honestly.
2. STOP and report J1 to Codex for isolated Studio testing/revisions. Do not begin drivetrain until Codex accepts the circuits. User has authorized first Git commit and private GitHub repository `touge-bloom` after acceptance; Codex handles that. Notify user when J1 is reported and before commit starts. No repository or commit exists yet.
3. After acceptance, C1-cedar-drivetrain: read Design/Cedar Coupe Mechanics Handoff.md and queued C1 scope. Only create src/shared/Config/DrivetrainConfig.luau and src/shared/Sim/Drivetrain.luau. Pure-state engine/gearbox, ignition, RPM/idle/redline, reverse/neutral/forward ratios, shift up/down with edge guards/timing, manual/auto hysteresis, assisted clutch plus explicit clutch, independent service brake, rear-only handbrake and reverse-speed guard. No model/controller integration yet. Return finite outputs and opt-in tests. STOP for Codex acceptance.
4. After accepted C1, Codex assigns a bounded driving-controller integration task: inputs, drive force, shifts, service brake, handbrake, reverse, clutch and lifecycle. Do not invent broader source authorization now. Codex wires visuals; Claude cannot modify assets or mount dimensions.

## Model interface

Blender source Assets/Blender/CedarCoupe/Cedar_Coupe_Prototype.blend. Native Studio snapshot CedarCoupePrototype.rbxm in that folder. Live template ReplicatedStorage.Assets.Cars.CedarCoupePrototype; Workspace.CedarCoupeReview is anchored display only. Front -Z, +X right, +Y up. Chassis6.4x1.6x14. Wheels radius1.4/width1.3. Mounts FL(-2.9,-.6,-4.7), FR(2.9,-.6,-4.7), RL(-2.9,-.6,4.5), RR(2.9,-.6,4.5). Wheel Models have axle pivots; use PivotTo. Controls have named Motor6Ds; Chassis has named suspension/audio/seat/camera Attachments. Full-extension template2.2 spring length; display0.6. Separate visual body meshes are noncolliding/massless. 84 sampled tire/body clearance poses passed. Model is prepared for code, not drivable yet. Native file saved, reload not verified. More gameplay/performance QA required.

## Coordination and Studio

Prefer the existing car_game_coordination tools if available in the extension. Claim J1 with Claude role before edits; complete_stage with token, report changed files/API/tests actually run and risks. Do not expose token in Git or user report. If MCP is unavailable, do not bypass ownership: stop and tell Codex to arrange the claim and report path. Do not independently mark tests accepted.

Rojo serves default.project.json on localhost34872 and is connected to Place2, the user-confirmed Car Game session. This is currently opened from Assets/Blender/Batch01/Model_Library.rbxl. Do not save that whole place while Rojo is connected. Source sync does not make the car gameplay integration complete and does not run the missing generator. Keep asset library separate from source sync. Do not publish or change the live test scene to hide failures.

No background automatic task should restart work. The prior heartbeat was found unavailable in the app when stopping the worker. Resume explicitly in VS Code.
