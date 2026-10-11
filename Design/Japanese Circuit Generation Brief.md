# Japanese Circuit Generation Brief

User-authorized direction: Japanese procedural circuits inspired by Ebisu North/West, Meihan, Nikko, Minami Chiba, YZ and Gunsai. Read [[References/Japanese Circuit Reference Board]] and its linked photos/PDFs before implementation. These are fictional variations inspired by real venues; exact replicas are not requested.

Claude owns car mechanics and terrain-generation programming only. Codex owns all Blender modeling, model materials, scenery, visuals and asset integration. Do not create tree/rock/rail/car models or edit RoadVisualBuilder or initialization scripts.

First programming milestone: standalone deterministic Japanese profile configuration and circuit-data generator, isolated from the live scene. North and West are separate profiles; Meihan C is supported inspiration, E awaits verified references. Provide Nikko, Chiba, YZ and Gunsai profiles. Distinguish compact low-elevation circuits from mountain loops. Profile attributes and numerical budgets are game-design choices, not claimed real-world measurements.

Preserve existing game scale: road width 30 studs, minimum generated turn radius 45 studs, target loop length 1500–2500 studs, grade at most 8% for this milestone, and at least 70 studs between non-neighboring road stretches. These constraints take priority over tight real-world corner replicas. Randomize within profile character with reproducible seeds; do not randomize every venue into the same oval or impose mountains on flat circuit profiles.

Read RoadGeometry/RoadConfig and MountainHeightfield interfaces. Return a closed sampled circuit compatible with those modules and pure terrain configuration overrides per profile; no live Terrain writes. Validate the final sampled geometry, not just control points: finite coordinates, closure, width, length, horizontal radius, grade, crossings and separation. Bounded retries with explicit failure diagnostics. No silent invalid fallback. Preserve seam-safe T1 heightfield unchanged. Voxel clearance still needs independent integration QA.

Opt-in selfTest: all profiles over multiple seeds, exact same-seed repeatability, changed seeds, profile distinction, closure including wrap segment, invalid inputs, radius/grade/separation validation and MountainHeightfield compatibility. Report tests as NOT RUN unless executed. Return the exact test invocation and API through the coordination bridge; Codex tests before integration.
