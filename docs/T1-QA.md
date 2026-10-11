# T1 final acceptance: PASSED

Codex ran the revised modules in Studio on 2026-10-10. All 53 built-in checks passed. Independent testing reduced the original4.000574-stud seam to0.0000742069studs, found zero reversed-order difference on the tested grid, and maximum grid-edge step0.00089060995studs. Exact disk/live-source match was confirmed. Queue task T1-heightfield is done.

This approves the pure-data heightfield only. Voxel-clearance, full-map performance and gameplay integration remain pending. No live Terrain writes or place saves occurred during QA.

Claude worker reports are stored in coordination/state/T1-heightfield/claude-output.json and dispatch.log. Workers are background CLI processes, not the user's existing Claude chat.

## Earlier failed acceptance and reproduction (historical)
# T1 terrain QA: revision required

The exact synced TerrainConfig and MountainHeightfield sources passed the built-in Studio selfTest (zero failures), but independent acceptance failed.

Reproduce with seed7, open road width30, samples(-200,0,0),(200,0,0),(200,8,80),(-200,8,80). At x0,z39.999 height0.44485825095; at z40.001 height4.44543245780. The nearest segment changes1->3 and causes a4.00057420685-stud discontinuity across0.002studs.

Fix only TerrainConfig and MountainHeightfield. Outside protected road/shoulder corridors, combine all influencing road segments continuously and deterministically instead of selecting one height with nearest-segment switching. Preserve road clearance, bounded cost and consistent spatial-grid transitions. Add the exact unequal-height parallel-road regression, closed/open and reversed-order tests, and grid-boundary tests. Do not reduce influence radius merely to hide the defect. No scene integration, voxel writes, model edits or mechanics retuning.

The separate voxel-clearance issue is NOT tested or solved by this pure-data task. Phase0 turn radius24.6 is also not a generator validation result. Keep the fixed test circuit until its deliberate tight-corner use is assessed.

Model_Library.rbxl must not be saved from a Rojo-synced session during this QA. Isolated tests create and destroy only temporary modules and do not write Terrain.