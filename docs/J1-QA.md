# J1 Japanese circuits — accepted pure-data milestone

Codex ran the actual Luau in Studio Place2, Edit mode, on October 10, 2026 (America/Chicago). The source modules were cloned into an unparented isolated hierarchy and destroyed after each run. No live Terrain writes, scene changes or place saves occurred.

## Exact source verification

Normalized disk/live source hashes and UTF-8 lengths matched for all nine shared modules. J1 source fingerprints (djb2 modulo 2^32, CRLF normalized to LF):

| Module | Hash | Bytes |
|---|---:|---:|
| JapaneseCircuitProfiles | 3067621432 | 19831 |
| JapaneseCircuitGenerator | 1566339895 | 54111 |

T1 TerrainConfig and MountainHeightfield also matched their accepted disk/live source, hashes 776271447 and 4233433089 respectively.

## Tests actually run

- Actual Luau opt-in selfTest passed with zero failures in approximately 1.12 seconds. It covered every profile over five seeds, repeatability, variation, profile character, rejected invalid inputs/layouts, explicit retry exhaustion and MountainHeightfield compatibility.
- Actual Roblox Random generation sweep: 100 seeds per profile, 700/700 successes. Maximum seven attempts, below the default budget of 24. Sampled loop lengths were 1573.224–2498.551 studs and maximum independently measured grade was 7.73794%.
- Independently measured adjacent-three-sample horizontal radius over all 700 results: minimum 45.60953 studs. This additionally checks a smaller sampling window than the generator's built-in two-neighbor estimator.
- Independent exhaustive segment-pair checks on seed 1 for all seven profiles, including wraparound closure: no crossings, minimum nonlocal separation 75.55551 studs. These checks used separate point-to-segment/intersection calculations without the generator's spatial grid. They used the documented approximately 80.2-stud along-road exclusion for local neighbors. The exhaustive independent check was seven layouts, not all 700.
- Independent heightfield probes at 24 positions per seed-1 profile, at centerline and both road edges (504 queries): maximum deviation from road height minus Clearance was 0.000313291 studs.
- The extended Studio sweep and probes took approximately 11.16 seconds with batch yields; this is QA time, not full-map generation performance.
- Rojo build of the actual default.project.json passed. The disposable build output was kept outside the game project and is not part of the commit.
- Inspected top-view plots exported from actual Studio seed-1 samples. All seven were closed and visually distinct: North's switchback return, West's elongated loop, Meihan's compact transitions, Nikko's wide sweeper, Chiba's open practice layout, YZ's long straight/crank and Gunsai's linked mountain bends. This is a centerline review, not a rendered scenery/driving review or a surveyed venue comparison.

## Acceptance and limits

Accepted only the standalone profile/generator data scope. J1 is ready for later scoped integration. C1 drivetrain may proceed in Claude's visible VS Code extension after the Git milestone, with separate Codex acceptance before controller integration.

No approval is implied for live terrain voxels, full-map performance, drivable gameplay, scenery, crest comfort, LOD/mobile performance or accurate real-world replicas. Grade is bounded per segment; crest acceleration is not separately constrained. West/YZ retries remain expected; generation may explicitly fail for other seeds or custom configurations. The generated layouts remain fictional inspirations.

Machine-readable extended evidence and the seed-1 plan-view board are saved alongside this QA record. Claude's earlier Node mirror is supplementary and is not counted as Studio evidence.
