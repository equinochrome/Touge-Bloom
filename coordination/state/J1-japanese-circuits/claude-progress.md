# J1-japanese-circuits: Claude progress note

Status: **Claude's implementation is finished and submitted for Codex review. It is not accepted yet.** Updated 2026-10-10.

## Ownership
- J1 was claimed through the Car Game coordination server (`coordination/mcp.mjs`, role `claude`). This VS Code session did not load that server from `.mcp.json`, and its `project_coordination` tool points at the RBLX Pt 2 queue. So the claim and completion went to the real Car Game server over a stdio MCP client kept in Claude's scratchpad. That path runs the same `claim()`/`complete()` ownership logic, and the token is not stored in the repo.

## Delivered files (the only source edits)
- `src/shared/Config/JapaneseCircuitProfiles.luau` (new): constraints, generation settings, an ordered list of 7 profiles, and per-profile references split into Verified / GameDesign.
- `src/shared/Gen/JapaneseCircuitGenerator.luau` (new): `generate`, `validate`, `createHeightfield`, `listProfiles`, `getProfile`, and an opt-in `selfTest`.

The T1 modules (MountainHeightfield, TerrainConfig), RoadGeometry, init scripts, controllers, visuals, models and the scene are unchanged.

## Design summary
- Each profile is a turtle template of straights and arcs with seeded ranges. Arcs have linear curvature ramps at both ends.
- Each attempt corrects the arc angles to exactly ±360°. It then solves the closure straights by least-norm, rejecting any that fall below the profile's MinStraight.
- Control points are emitted uniformly at about 12 studs, which avoids Catmull-Rom kinks. Uneven spacing was found to drop a 60-stud circle to 41 studs. The control points then go through `RoadGeometry.build`.
- Elevation uses periodic harmonics scaled to a relief per venue type. If grade is too steep, elevation is reduced in up to 6 bounded passes.
- `validate` checks the final samples: finite values, width, spacing, the closing segment, length, radius (RoadGeometry's estimator), grade, crossings and touches, and nonlocal separation. Two stretches count as nonlocal when the gap along the road is at least 2R·asin(S/2R) = 80.2 studs.
- Budget: 24 attempts by default, at most 64. When the budget runs out, the result is ok=false with every attempt's reasons and no circuit.

## Testing actually performed
- **Luau selfTest: NOT RUN.** There is no Luau runner on this machine, and Studio was not used.
- **Node mirror (run):** a line-by-line JavaScript mirror of the generator algorithm reads the real Luau profile file. It replaces Roblox `Random` with mulberry32, so actual Luau shapes will differ.
  - 100 seeds per profile: 700/700 generated. Worst case was 5 attempts.
  - All results met length 1500–2500, radius ≥ 49.7, grade ≤ 7.69% and separation ≥ 75.2.
  - The selfTest fixtures behaved as expected in the mirror: tight stadium → radius and separation; pinched stadium → separation only; steep circle → grade only; short circle → length; figure-eight → crossing; truncated loop → closure.
- These mirror results do not replace running the Luau code. The heightfield checks were not mirrored.

## Studio test for Codex
```lua
local G = require(game.ReplicatedStorage.Shared.Gen.JapaneseCircuitGenerator)
local passed, lines = G.selfTest() print(passed) for _, l in lines do print(l) end
```
