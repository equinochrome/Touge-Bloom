---
tags: [project, ownership]
updated: 2026-10-10
---
# Project management

## User-approved responsibilities
**Codex:** project manager, model author, asset selection, materials, visual design and visual verification.
**Claude:** lead programmer for car mechanics and terrain generation only.

Claude must not model, generate meshes, select or replace visual assets, change textures or materials for models, dress scenery, or redesign cars. Existing visual code is outside Claude's edit scope unless the user explicitly changes these responsibilities.

Codex may use scripts to author geometry and manage model assets. This does not transfer modeling to Claude.

## Current work board
| ID | Owner | Deliverable | Acceptance / status |
|---|---|---|---|
| P0-QA | Codex | Existing prototype verification | Existing source present; runtime acceptance still pending |
| T1-HEIGHTFIELD | Claude | Standalone seeded mountain heightfield and terrain configuration | No live world mutation or integration; finite repeatable heights and road-clearance blending |
| M1-COUPE | Codex | Original coupe visual candidate | Mesh generation in Studio; inspect proportions and wheel segmentation before approval |
| M2-SUGI | Codex | Cedar visual candidate | Mesh generation in Studio; inspect silhouette and bark before approval |
| M3-RAIL | Codex | Modular folded-rail mesh | Original OBJ source with UVs/normals and preview |
| REF-DETAIL | Codex | More modeling references | [[References/Modeling Detail Board]] |

## Handoff process
1. Codex records a scoped programming task and acceptance requirements.
2. Claude edits only the assigned car/terrain source files and reports evidence.
3. Codex reviews the diff and performs appropriate Studio tests.
4. Failing results return to Claude as a bounded revision.
5. Model candidates remain isolated in the asset library until inspected.
6. Codex integrates approved visual assets; Claude does not touch their authoring.

The MCP source worker is a separate Claude process. It does not update the user's existing Claude conversation. Manual edits by that conversation are not protected by the queue; avoid editing the same assigned files concurrently.

## Build order
Stabilize road/car prototype; establish terrain data; approve model candidates; dress a short scene; then expand procedural circuits.
No garage store or purchases are currently authorized for implementation by this document.

## Decisions
- Place2 was confirmed by the user as Car Game on 2026-10-10.
- First setting: Japanese mountain roads.
- No visible primitive-built finished scenery.
- Invisible physics/collision parts remain acceptable.

## Updated modeling workflow
User requires Blender authoring, then transfer to Studio. Studio AI-generated car/tree candidates were archived. See [[Blender Asset Review 01]] for the measured wheel and guardrail. T1-heightfield is awaiting Codex tests; no terrain implementation is approved yet.
