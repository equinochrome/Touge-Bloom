# Touge Bloom — next Codex conversation

## Project and paths

User is building a Roblox drift game with realistic smooth nature, fictional seeded circuits inspired by real Japanese venues, and eventually multiple chassis and car modifications. Working title: **Touge Bloom**. Touge means mountain pass.

Actual project and Obsidian vault: `C:\Users\super\OneDrive\Documents\Car Game`.
Previous Codex chat workspace: `C:\Users\super\OneDrive\Documents\ChatGPT\Car Game`.
Read the actual project files before acting; this document records last-known state, not a fresh verification.

Phrase the user explicitly requested remembering: **The Brown Fox Jumped over the big dog**.

## Roles and user preferences

- Codex is project manager and owns ALL modeling, model materials/textures, Blender authoring, imports, scenery/visual integration and Studio acceptance.
- Claude is lead programmer for car mechanics and terrain/circuit generation ONLY. Preserve CLAUDE.md role boundaries. Claude must not edit models, lighting, RoadVisualBuilder or WedgeTriangle.
- Model in Blender, then transfer to Roblox. Use existing game measurements and check geometry, pivots, orientation and export scale.
- User wants Claude visibly running in the VS Code extension rather than an opaque background CLI worker. Do not restart CLI workers.
- User favors autonomous work, but expects honest status and notifications at meaningful milestones.

## Last verified state

T1-heightfield completed and passed Codex Studio acceptance: 53 built-in checks plus independent continuity, reversed-order and grid-boundary checks. See docs/T1-QA.md. TerrainConfig and MountainHeightfield remain pure-data modules; live voxel terrain rendering, clearance and full-map performance remain future integration work.

J1-japanese-circuits was dispatched as a background Claude worker, stayed alive without a report or assigned source files, and was explicitly stopped by the user. Verified launcher11780 and Claude32432 were terminated. Queue ownership was released through the coordination API; J1 returned to queued, C1-cedar-drivetrain remains queued. Do not reuse old process IDs without re-verifying identity. J1 is unfinished and has NOT passed acceptance.

User was given a prompt to paste into Claude's VS Code extension. It instructed Claude to read CLAUDE_HANDOFF.md, resume J1 only, use coordination MCP ownership, and stop for Codex acceptance. There is no verified evidence yet that the user submitted that prompt or that Claude resumed.

Latest Studio verification after stopping Play: all16 source files matched on-disk normalized-source hashes, Rojo build passed, and car template existed. Studio was in Edit mode. Connected Studio previously identified as Place2, user-confirmed Car Game, id026c4683-41ef-4021-b99c-d16067912798. List studios/state afresh before acting.

## Circuit references and J1 scope

Read Design/Japanese Circuit Generation Brief.md and Design/References/Japanese Circuit Reference Board.md. Thirteen local reference photos/maps/PDFs are in Design/References/Attachments/Circuits with provenance sources.json. Official/event-organizer references cover Ebisu North/West, Meihan C, Nikko, Minami Chiba, YZ East and Gunsai (correct name Gunma Cycle Sports Center).

Meihan E still needs verified references. Minami Chiba's downloaded diagram is historical2018. Course maps are not surveyed construction blueprints. Generate fictional seeded variations with distinct profile structures; do not describe guesses as actual surveyed elevations. Separate compact low-elevation circuit profiles from mountain routes.

J1 may create ONLY src/shared/Config/JapaneseCircuitProfiles.luau and src/shared/Gen/JapaneseCircuitGenerator.luau. Constraints: road width30studs, minimum horizontal radius45studs, loop length1500–2500studs, grade<=8%, separation>=70studs between nonlocal road stretches. Validate final sampled segments including closure, crossings and segment-to-segment distances. Bounded retries, explicit failure, deterministic seeds, opt-in meaningful selfTest, compatibility with existing RoadGeometry and MountainHeightfield. No live scene/init/model changes. Codex tests exact finished source in isolation before accepting.

## Prototype coupe

Original Japanese-inspired right-hand-drive Cedar coupe authored in Blender. Source/export folder: Assets/Blender/CedarCoupe. Files include Cedar_Coupe_Prototype.blend, FBX/OBJ exports, native Studio-saved CedarCoupePrototype.rbxm, manifest.json, wheel-clearance.json, renders, authoring/check scripts and studio-assembly.json. Reconstructed rbxmx is a secondary backup; native rbxm is preferred. Native reload verification remains pending (game:GetObjects local-file attempt failed).

Live template: ReplicatedStorage.Assets.Cars.CedarCoupePrototype. Workspace.CedarCoupeReview is an anchored display copy. Geometry65meshes/~43964triangles; per-mesh manifold/zero-area/UV/unit-scale checks and OBJ roundtrip bounds passed. An84-pose sampled tire/body-shell intersection sweep passed after widening cavities. This excludes containment and other panels; gameplay/performance/LOD QA remains. Model is prepared for programming, NOT drivable or production-ready.

Front-Z, up+Y, right+X. Chassis6.4x1.6x14. Tire radius1.4, width1.3. FL(-2.9,-.6,-4.7), FR(2.9,-.6,-4.7), RL(-2.9,-.6,4.5), RR(2.9,-.6,4.5). Wheel center=mount-Up*springLength. Wheel Models have axle pivots; individual imported mesh origins are bounding centers, so use Model:PivotTo. Template spring length2.2/full droop; display0.6. Imported FBX required180-degree Y orientation correction, verified nose-Z and mounts. Static body welded/noncolliding/massless. Controls have Motor6D pivots for steering wheel, gear lever, handbrake and pedals. Chassis has suspension/driver-seat/camera/audio Attachments. DriverSeat is not a VehicleSeat. See Design/Cedar Coupe Mechanics Handoff.md for full contract.

Existing Phase0 controller has raycast suspension, steering, simplified rear drive, braking, reverse and rear handbrake. It lacks an explicit engine/gearbox/clutch. C1 queued files: src/shared/Config/DrivetrainConfig.luau and src/shared/Sim/Drivetrain.luau, pure-state drivetrain first, then Codex acceptance. Next task is bounded driving-controller/input integration after C1 acceptance. Codex handles model visuals. Doors/hood opening, detailed engine bay, final textures and LODs are future assets.

## Studio and Rojo precautions

Rojo default.project.json serves localhost34872. Studio currently opened the model-library snapshot Assets/Blender/Batch01/Model_Library.rbxl. User previously warned not to save that entire place while Rojo is connected because source sync changes the library session. Car was saved separately as native rbxm. Do not overwrite the library snapshot accidentally. Source synchronization does not mean missing generator/drivetrain or model gameplay integration exists.

Claude's earlier art-slice changes were reverted to Phase0; patch/backup saved externally in scratchpad. T1 preserved. Phase0 loop measured minradius24.6studs while generated circuit target is45; resolve in later appropriate scope. Full Phase0 driving checklist remains incomplete.

## GitHub authorization and notifications

User explicitly authorized first Git commit/push after Japanese circuits complete and pass review. They approved a PRIVATE GitHub repository and accepted repository name touge-bloom on their authenticated personal account. Last Git inspection: actual project master branch, all project files untracked, no remote, no commit or GitHub repository created. Verify again. Create repository only through available authenticated tools/gh; never invent account identity, overwrite an existing repo or force push.

Notify user when Claude reports Japanese circuits completed (distinguish report from acceptance), and separately BEFORE starting the first commit. Stage intentional reviewed project code/config/docs, not everything. Exclude credentials, .obsidian session state, Studio locks, coordination tokens/runtime logs/backups, scratch files and unlicensed reference media; assess large Blender/model binaries deliberately. Run meaningful checks and report commit hash/repository URL/push result. After git milestone, next two tasks belong in Claude VS Code extension: C1 drivetrain then controller integration, with Codex acceptance between them.

Previous heartbeat automation id move-car-tasks-to-claude-vs-code-after-circuits was created and updated, but when stopping the worker the app reported it no longer existed. No active automatic follow-up is verified. Do not claim monitoring is active without checking; do not recreate background work merely from this handoff.

## Suggested first actions

1. Read CLAUDE_HANDOFF.md, CLAUDE.md and project coordination queue/status.
2. Determine whether Claude resumed J1 in VS Code and whether it has reported. Preserve user-visible ongoing sessions; do not start duplicate editors.
3. Review/test reported J1 or help restore the extension/MCP ownership workflow if requested.
4. After acceptance, follow authorized GitHub milestone and progress notifications, then C1/controller tasks.
