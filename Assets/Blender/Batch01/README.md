# Blender Batch 01

Original measured wheel and folded guardrail, authored/finished in Blender by Codex.

- Scene: Scenic_Drift_Assets.blend. It contains review staging positions, a camera and lights.
- Canonical exports: Cedar_Wheel.fbx (preserves separate tire, rim and brake meshes), Mountain_Guardrail_12.obj.
- Alternate OBJ/FBX exports are included; Studio OBJ import combined the wheel into a single mesh, so use FBX for the wheel.
- One Blender unit = one stud. Studio Import Preview: Scale Unit Stud, scale factor 1.
- The native source is an editable review scene. Before manually exporting selected assets again, reset their review-stage locations to the world origin and exclude REVIEW_ONLY objects; the authoring script does this correctly before exporting.

## Verified

Wheel tire 1.3 x 2.8 x 2.8 studs; guardrail 12 x 3.2 x 0.76 studs. All four authored meshes passed manifold-edge, zero-area-face, loose-vertex, UV, scale and OBJ dimension round-trip checks. See validation.json.

Studio import preserved dimensions. Wheel front-face orientation required a 180-degree Y correction. The saved library model has identity Model.WorldPivot at the axle, no PrimaryPart, and spokes/front face toward +X. Preserve that model pivot for animation. Use the saved library template, not raw FBX insertion transforms. The negative-X side of the car needs the corresponding mirrored/rotated visual placement during integration.

Model_Library.rbxl is a LOCAL MODEL LIBRARY SNAPSHOT, not the complete game. Import assets from ReplicatedStorage.Assets.BlenderBatch01 into the actual game place. Preview copies are in Workspace.CodexBlenderReview. Old Studio-generated car/tree candidates are preserved in ServerStorage.UnusedGeneratedCandidates and are not approved assets.

Models are anchored/non-colliding for library review. Car visual integration must unanchor the visual meshes appropriately, preserve massless/non-colliding flags, and attach them to the existing mechanics. The physics controller has not been changed.

The rim uses a simple metal finish in Studio. These are first asset candidates; detailed texture wear, rear rim styling, calipers and lower-detail versions remain future art work. The first wheel is 6,884 triangles total; evaluate lower-detail versions before shipping many cars.