# Phase 0: Setup and Technical Spikes

Phase 0 checks two technical questions before any game work starts:

- **Spike A:** can we build a smooth, seamless curved road from EditableMesh, or do we need the WedgePart fallback?
- **Spike B:** does a raycast-suspension box drive cleanly over the road's invisible collision boxes?

There is no terrain, scenery, scoring or procedural generation yet. The track is the hand-authored loop `TestCircuits.Phase0Loop`.

## What runs where

| Piece | Runs on | File |
|---|---|---|
| Centerline (spline, resample, stats, hash) | both | `src/shared/Gen/Spline.luau`, `RoadGeometry.luau`, `TestCircuits.luau` |
| Road collision boxes (invisible, tagged `Road`) | server | `src/server/RoadCollisionBuilder.luau` |
| Car spawn and network ownership | server | `src/server/CarSpawner.luau` |
| Visible road (EditableMesh or wedge fallback) | client | `src/client/RoadVisualBuilder.luau`, `WedgeTriangle.luau` |
| Suspension, tires and input | client (car owner) | `src/client/CarController.luau` |
| Chase camera | client | `src/client/CameraController.luau` |
| Debug readout | client | `src/client/DebugOverlay.luau` |
| Tuning values | shared | `src/shared/Config/CarConfig.luau`, `RoadConfig.luau` |

## One-time setup

1. **Tooling.** Rokit and Rojo 7.7.1 are already installed. To confirm, run `rojo --version` in this folder. It should print `Rojo 7.7.1`.
2. **Studio plugin.** Run `rojo plugin install` once. This installs the plugin version that matches the CLI. Restart Studio if it was open.
3. **Build the place file:**
   ```
   rojo build -o "Car Game.rbxlx"
   ```
   Open `Car Game.rbxlx` in Roblox Studio with **File > Open from File**. Git ignores this file. Save and reopen this same file from now on; don't rebuild it, or you'll lose anything you added in Studio.
4. **Live sync.** In a terminal in this folder, run `rojo serve`. In Studio, open the **Plugins** tab, click **Rojo**, then **Connect**. The default address is `localhost:34872`. Saved `.luau` edits now appear in Studio immediately.
5. **Script Analysis.** Open **View > Script Analysis** and confirm there are no errors under `ServerScriptService.Server` or `StarterPlayer.StarterPlayerScripts.Client`.
6. **EditableMesh permission.** This applies to published places only. Unpublished Studio sessions should work without it.
   - Live games block EditableMesh by default.
   - To enable it, the creator account must be 13+ and ID-verified.
   - Publish with **File > Publish to Roblox**.
   - Then turn on **Allow Mesh & Image APIs** in **Home > Game Settings > Security**, or in the experience's Creator Dashboard settings.

The project file already sets:
- `Players.CharacterAutoLoads = false`, since there's no avatar and you only drive the car.
- `Workspace.StreamingEnabled = false`, which keeps the Phase 0 test simple.
- A 2048-stud grass `Ground` part under the track.

## Running the test

1. In Studio, click **Test > Play** (F5).
2. The **Output** window should show:
   - `[Phase0] Circuit built: ... samples, ... studs, ... hash xxxxxxxx` (server)
   - `[Phase0] Road visuals: EditableMesh, N chunks, ...` (client), or `WedgeFallback` with a warning that explains why
3. The debug readout in the top-left shows:
   - Road mode, build time, and the fallback reason if any
   - Circuit length, minimum turn radius and maximum grade
   - Client hash vs. server hash. It must say **MATCH**.
   - FPS, speed, drift angle and steering input
   - Compression for each wheel, plus whether that wheel is on the road (`R`), on other ground (`G`) or in the air (`-`)

**Controls:**
- **W / S:** throttle, and brake then reverse
- **A / D:** steer
- **Space:** handbrake
- **R:** reset to the nearest point on the road
- **C:** show the collision boxes in alternating orange and blue
- **Shift+P:** Studio free camera, useful for inspecting seams
- **Gamepad:** R2/L2 throttle and brake, left stick to steer, A for handbrake, Y to reset

**Live tuning while playing:**
- Make sure the Explorer shows the client view. Use **Test > Current: Client/Server** to switch.
- Select `Workspace.Cars.Car_<UserId>` and edit its Attributes, such as `SuspensionFrequency`, `Grip` or `EngineAccel`. Changes take effect on the next frame.
- When a value feels right, copy it back into `CarConfig.Tuning`.

## Phase 0 checklist

Record the result of each step.

| # | Check | How | Pass when |
|---|---|---|---|
| 1 | Rojo sync | Edit a value in `RoadConfig.luau` while connected | Studio updates without errors |
| 2 | Road mode | Read the overlay or the Output window | `EditableMesh` appears. If it says `WedgeFallback`, write down the reason |
| 3 | No visible seams | Press Shift+P to fly along the road, especially where chunks meet (every 48 samples, about 190 studs) and at the start line | No cracks, gaps, flickering or lighting steps on the surface or the edge skirts |
| 4 | Texture scale | Look at the asphalt up close | The texture isn't stretched or tiny. If it is, adjust `RoadConfig.TextureRepeatLength` |
| 5 | Faces point the right way | Look from above and from the side | The surface is visible from above and the skirts from outside. If they're invisible, the triangle winding needs flipping |
| 6 | Collision matches visuals | Press C | The boxes sit flush under the visible road with no gaps on the outside of corners |
| 7 | Car at rest | Spawn and touch nothing for 10 seconds | The car settles within about 1 s, with no jitter, creeping or bouncing. Wheel compression is about 1.0 |
| 8 | Box seams while driving | Drive the full loop at about 60 and 120 studs/s | No visible bumps and no sudden jumps in wheel compression from box to box |
| 9 | Corners and elevation | Drive the tight right-hander and the crest near (240, 8, -160) | All wheels stay on the road (`R`) and the car doesn't take off |
| 10 | Handbrake slide | Turn in at about 70 studs/s, tap Space, then countersteer | The rear slides and can be caught. Fine tuning is Phase 1 |
| 11 | Frame-rate independence | Cap the frame rate at 30 using the in-experience Settings menu (Esc > Settings > Maximum Frame Rate) and compare with 60. Watch the overlay's FPS readout | Ride height and handling are about the same as at 60 FPS |
| 12 | Network ownership | Use **Test > Clients and Servers** with 1 player, then click **Start** | The car responds without rubber-banding, and the overlay hash says MATCH |
| 13 | Wedge fallback | Set `RoadConfig.ForceWedgeFallback = true`, then Play | The road renders from wedges and the car drives the same, since collision is identical |
| 14 | Published place | Publish, enable Allow Mesh & Image APIs, then join from the Roblox app on PC and, if possible, a phone | `EditableMesh` mode on the live server, the hash says MATCH, and the client memory in the Developer Console (F9 > Memory) is reasonable |

**Phase 0 is done when** checks 1–13 pass, and the road technique is chosen from checks 2, 3 and 14: EditableMesh, or the wedge fallback if 14 fails.

## Known limitations

These are intentional for Phase 0:

- The car is a placeholder box. The other players' cars don't show wheels.
- The tire model is basic. Drift tuning and assists such as countersteer help, yaw damping and drift sustain belong to Phase 1.
- There's no terrain. You can drive off the road onto the flat ground part, and press R to get back.
- The road has no curbs, painted lines or banking.
