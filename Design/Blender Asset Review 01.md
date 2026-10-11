---
tags: [assets, blender, verified]
updated: 2026-10-10
---
# Blender asset review 01

Codex owns modeling in Blender. Claude remains responsible only for car mechanics and terrain generation.

![[Assets/Blender/Batch01/blender-review.png]]
![[Assets/Blender/Batch01/wheel-closeup.png]]

| Asset | Measured Roblox dimensions | Status |
|---|---|---|
| Cedar wheel | 1.3 wide x 2.8 diameter | Blender and Studio scale/pivot verified; controller integration pending |
| Guardrail | 12 long x 3.2 high x 0.76 deep | Blender and Studio scale verified; scenery integration pending |

Editable source: Assets/Blender/Batch01/Scenic_Drift_Assets.blend.
Read Assets/Blender/Batch01/README.md before exporting or integrating. It records importer orientation correction and review staging transforms.

The wheel matches CarConfig.WheelRadius=1.4 and WheelWidth=1.3. Rotate about X. Its template pivot is the axle, and its visible front faces +X. No suspension or physics values were altered.

Model_Library.rbxl is a saved asset-library place snapshot, not the complete playable game. The car body and cedar tree still need Blender modeling. Previous Studio mesh-generation candidates are archived and are not accepted art.

Terrain task T1-heightfield has been returned by Claude and is awaiting Codex testing. It is not approved or integrated yet.