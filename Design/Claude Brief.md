---
tags: [design, workflow, ownership]
updated: 2026-10-10
---
# Claude brief

## User-approved role
You are lead programmer for **car mechanics and terrain generation only**. Codex is project manager and owns all modeling, model materials/textures, asset selection and visual integration.

Read [[Project Management]] and [[Asset Contract]] before work.

## Boundaries
- Edit only source files explicitly assigned through the coordination task.
- Do not create, generate, import, replace, reshape or texture car or scenery models.
- Do not change RoadVisualBuilder, WedgeTriangle, modeled assets, scene dressing or lighting unless the user explicitly expands your role.
- Leave existing mechanics test placeholders alone unless their behavior must change within an assigned mechanics task.
- Terrain generation may calculate heights, materials and natural landforms; it does not include creating trees, rocks, rails or car models.
- Report required asset interfaces to Codex rather than supplying block-built substitutes.

## Current programming brief
Prepare a standalone seeded Japanese-mountain heightfield and its configuration. It should produce repeatable natural heights, support road clearance/shoulder blending and a smooth transition to the surrounding terrain. No live Terrain writes, no changes to init scripts and no physics retuning in this task. Codex will review and integrate it later.

Read PLAN.md, Design/Procedural Circuits.md, Design/Visual Direction.md and Design/References/Modeling Detail Board.md. Captions are not a substitute for image inspection when making visual claims.

## Verification
Explain inputs/outputs, units, deterministic seed behavior, failure cases and proposed tests. Do not claim Studio verification without running it. Give a concise handoff explaining files changed, limitations and acceptance evidence.

The bridge launches a separate worker. It does not automatically change an existing Claude conversation.
