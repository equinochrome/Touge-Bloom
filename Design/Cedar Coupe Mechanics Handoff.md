# Cedar Coupe — mechanics handoff

Original Japanese-inspired right-hand-drive coupe, authored in Blender. Reference: [Nissan official heritage coupe proportions](https://www.nissan-global.com/EN/HERITAGE_COLLECTION/silvia_qs.html); original body design and existing game chassis dimensions take priority. [Roblox mesh specifications](https://create.roblox.com/docs/art/modeling/specifications) guided per-mesh geometry checks.

## Saved assets and readiness

Assets/Blender/CedarCoupe/Cedar_Coupe_Prototype.blend and .fbx/.obj are the revised source/export. CedarCoupePrototype.rbxmx is an XML snapshot reconstructed from the Studio assembly; reload verification is still pending. studio-assembly.json preserves IDs/transforms. Model library place on disk has NOT been saved while Rojo is connected.

Live template: ReplicatedStorage.Assets.Cars.CedarCoupePrototype. Workspace.CedarCoupeReview is an anchored display copy only. Readiness: model prepared for mechanics integration, NOT a working driveable car. Styling is a prototype; door/hood opening, engine bay and final texture/LOD work remain future assets.

## Exact interface

- Chassis PrimaryPart at origin; +X right, +Y up, -Z forward; size6.4 x1.6 x14. It is the only collision proxy in the template. Keep existing ballast mechanics; visual meshes are massless, non-colliding, non-queryable and non-touchable.
- Mounts: FL(-2.9,-0.6,-4.7), FR(2.9,-0.6,-4.7), RL(-2.9,-0.6,4.5), RR(2.9,-0.6,4.5). Suspension_* Attachments on Chassis. Tire radius1.4, width1.3. Wheel center = mount - Up * springLength. Template is exported at full extension2.2; review pose uses0.6. Full-extension overall height6.74 includes drooping wheels and must not be treated as normal ride height.
- Wheels.FL/FR/RL/RR are independent Models with AXLE-centered WorldPivot and three meshes each (Tire, Rim, BrakeDisc). Importer shifted mesh origins to bounding centers; ALWAYS use wheel Model:PivotTo, not individual tire/rim Position. Preserve the base orientation/offsets, including the left wheels' outward rim face. Wheel visuals are anchored transform-driven raycast visuals; do not weld all four wheels to the chassis.
- BodyVisuals static meshes have WeldConstraints to Chassis. Controls has SteeringWheelMotor, GearLeverMotor, HandbrakeLeverMotor, Pedal_ClutchMotor, Pedal_BrakeMotor, Pedal_ThrottleMotor; pivot C0/C1 are already set. Codex owns visual animation/integration. Runtime body/control meshes must be unanchored when attached to an unanchored chassis; the library stays anchored.
- Chassis attachments: DriverSeat(1.45,.65,.8), CameraTarget(0,1.3,0), EngineAudio(0,.4,-4), ExhaustAudio(0,-.5,7.3), SteeringPivot, GearLeverPivot, HandbrakePivot and pedal pivots. DriverSeat is an attachment, NOT a VehicleSeat. Player seating/control assignment still needs implementation.
- Individually named Headlight_L/R, BrakeLight_L/R, ReverseLight_L/R, FrontIndicator_L/R; geometry is present, signal behavior is pending. No unlicensed sound IDs are assigned. rbxmx snapshot preserves geometry/welds/motors/attachments; asset attributes are additionally documented in manifest and JSON.

## Verified

All65 visual meshes: watertight manifold surfaces, no zero-area faces, UV layer, applied unit scale, per-mesh triangle limit checked. Combined roughly44k triangles includes four existing detailed wheels; mobile performance/LOD remain untested. OBJ roundtrip bounds passed. Body-shell/tire triangle-intersection sweep84 poses (front steering±32/±16/0 degrees and suspension0/.3/.6/.9/1.2/1.6/2.2) passed after widening wheel cavities. This sampled audit excludes containment and other panels; gameplay collision/ride-height testing is still required. Studio verified wheel sizes/mount positions and nose -Z after correcting importer rotation180 degrees aroundY. No source scripts or current driving scene changed by modeling.

## Claude programming backlog

Existing Phase0 code supports raycast suspension, speed-based steering, simplified rear drive, service braking, reverse and rear handbrake. Explicit engine/gearbox is absent. First implement a pure drivetrain module and config: ignition, RPM/idle/redline, neutral/reverse/forward ratios, shift up/down, shift timing, optional automatic shifts and assisted clutch, clutch input, rear axle drive output, braking independent of throttle, low-speed reverse safety and rear-only handbrake. Separate input actions from simulation. Expose state for Codex visuals/HUD: rpm, gear, clutch, throttle, brake, handbrake, steering, engineRunning, shift state, speed, wheel loads/slip.

Subsequent scoped integration: controller/input configuration, seat/ownership lifecycle, keyboard/gamepad/touch, lights/indicators/hazards/horn state, reset/respawn, stop cleanup and meaningful driving tests. Sounds need owned/licensed assets. ABS/traction assistance are optional tuning features; fuel, damage and opening panels are later milestones. Claude must not edit assets, model instances/materials, motor pivots or visual builders. Codex wires model visuals after drivetrain acceptance. Do not change chassis/wheel layout to accommodate programming without reviewing the contract.

Tests: engine-off/no drive, neutral/no drive, positive forward/reverse signs, clutch disengagement, bounded RPM, up/down shift guards and held-input debounce, auto/manual behavior, finite outputs across dt bounds, braking/handbrake separation. Runtime acceptance later: accelerate, shift, brake, reverse, full-lock steer, suspension, tandem drift and respawn with no errors or visual clipping.

## Native Studio snapshot

CedarCoupePrototype.rbxm was saved directly through Studio Save / Export > Save to File (214583 bytes). Use this native snapshot for import; it preserves attributes and physical properties as well as geometry, attachments, motors and welds. The XML snapshot is only an additional reconstruction backup.

Coordination task C1-cedar-drivetrain is queued behind J1-japanese-circuits. It implements standalone engine/gearbox logic first; controller/model integration follows acceptance.
