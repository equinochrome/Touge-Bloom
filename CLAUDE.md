# Current project status
T1-heightfield is complete and passed Codex Studio acceptance. Read docs/T1-QA.md for final evidence and remaining integration work. Await a new scoped task; do not redo T1 or edit models.

# Car Game role boundaries

User-approved on 2026-10-10: Claude is lead programmer for car mechanics and terrain generation ONLY. Codex is project manager and owns ALL modeling, asset generation/import, model materials/textures, visual asset selection and scenery integration.

Read Design/Project Management.md, Design/Asset Contract.md and Design/Claude Brief.md before editing. Edit only the source files assigned in the coordination task. Do not modify Assets, model Instances, RoadVisualBuilder, WedgeTriangle, scene dressing or lighting. Terrain heights/material generation is permitted within an assigned terrain task; making tree, rock, rail or car models is not.

Do not claim tests ran unless they did. Do not change the current test scene or tuning in a standalone terrain-data task. Do not infer extra implementation authorization from design notes marked as proposals.