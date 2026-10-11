---
tags: [assets, handoff]
updated: 2026-10-10
---
# Asset contract

## Ownership
Codex owns all model files, textures, mesh generation, asset naming, pivots and visual integration. Claude may read this document to understand the mechanics interface but must not author or alter the assets.

## Coordinates
Y is up; a car's front is negative Z; positive X is right. Mesh candidates must be checked and rotated to match rather than trusting generation orientation.

All dimensions below are game art targets, not measurements of real road engineering.

## Coupe
Target envelope: about 7 wide x 4.2 high x 15 long studs. Original fictional styling, no real branding.
Before integration, verify that body and four wheel visuals can be separated. A generated car is not a working physics chassis.
The existing chassis remains the mechanics root; body visuals must be non-colliding, massless and welded. Wheel visuals must follow existing suspension mount and steering transforms.
Do not change suspension layout merely to fit a generated model without recording the mechanics implications.

Current mechanics layout is in src/shared/Config/CarConfig.luau:
- chassis 6.4 x 1.6 x 14;
- wheel mounts FL/FR x +/-2.9, y -0.6, z -4.7;
- rear mounts x +/-2.9, y -0.6, z 4.5;
- wheel radius 1.4 and width 1.3.

## Roadside assets
- Guardrail module: 12-stud length along X, origin at module ground center, approx. 3-stud height.
- Cedar: base pivot, approx. 28-stud height, variable silhouette.
- Rock: base pivot, asymmetrical silhouette, partially buried during placement.
Visual meshes do not establish safe collision automatically. Codex configures simple hidden collision separately.

## Storage
Local mesh source / textures / previews: Assets/Models.
Studio library: ReplicatedStorage.Assets, with candidates isolated from the active circuit until review.
Store source, revision, dimensions, triangle count, status and Roblox asset references in Assets/manifest.json.

## Readiness labels
candidate = generated or authored, pending visual/Studio review.
reviewed = inspected visually and measured, pending gameplay integration.
integrated = on the scene and checked for collision/performance.
Never claim a candidate is production-ready from successful generation alone.
