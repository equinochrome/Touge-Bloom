---
tags: [design, generation]
status: design-constraints
---
# Procedural circuits

## Agreed feature
Generate different closed circuits from seeds, surrounded by beautiful natural terrain.

## Driving and art constraints
Create the road layout first, validate it, then shape terrain and place scenery around it. Use broad sweepers, a few slower corners and short linking straights. Smooth the elevation and preserve sightlines.

Japanese mountain roads inspire the visual setting. The game uses fictional closed circuits and wider driving space; it is not a literal copy of a public road.

## Preserve across seeds
- Consistent road and car scale.
- The same material palette, vegetation family and lighting direction.
- Continuous road edges and believable hillside transitions.
- Clear runoff or guardrails around dangerous drops.
- A readable next corner.
- A coherent destination rather than unrelated scenery scattered everywhere.

## Vary across seeds
Turn sequence, gentle elevation, forest openings, rock-cut locations, valley vistas, scenic landmarks and destination names.

## Failure behavior to add to the technical plan
Use bounded repair/reroll attempts and a known-good fallback circuit. Record the requested seed, generator version and the resolved layout identifier so shared destinations remain reproducible. Validate the fallback too.

## Evaluation
Test geometry separately from its decoration. Drive several complete laps, then inspect screenshots from the standard viewpoints in [[Visual Review]]. A mathematically valid circuit may still need rejection for poor driving rhythm or scenery.
