# Touge Bloom — current milestones

Updated October 10, 2026 (America/Chicago). This record supersedes older handoff statements that J1 has no files or is awaiting implementation.

- [x] T1 pure-data heightfield accepted; see T1-QA.md.
- [x] J1 pure-data Japanese circuits accepted in actual Studio Luau; see J1-QA.md. Both assigned modules exist. 700/700 seeded runs succeeded; selfTest and independent probes passed.
- [x] J1 Rojo build passed.
- [ ] C1 pure-state drivetrain: queued for Claude's visible VS Code extension.
- [ ] Codex Studio acceptance of C1.
- [ ] Bounded driving-controller/input/lifecycle integration after C1 acceptance.
- [ ] Model gameplay integration, voxel terrain clearance, full-map performance and complete Phase 0 driving QA.

The existing GitHub repository is equinochrome/Touge-Bloom. The user explicitly chose to keep it public and authorized committing/pushing accepted J1 changes. Earlier handoff instructions about creating a first private repository are superseded by that decision.

## Claude restart instruction

Continue Touge Bloom in C:\Users\super\OneDrive\Documents\Car Game. J1 is accepted and done; do not redo it. Read docs/CURRENT-STATUS.md, docs/J1-QA.md, CLAUDE.md, Design/Cedar Coupe Mechanics Handoff.md, Design/Asset Contract.md and the exact queued C1 scope. Through car_game_coordination, confirm the correct project queue and claim C1-cedar-drivetrain with the Claude role. If the extension has not loaded the server, the previously successful direct stdio MCP client may use the same server and ownership API; do not bypass ownership or use the RBLX Pt 2 server.

Create only src/shared/Config/DrivetrainConfig.luau and src/shared/Sim/Drivetrain.luau. Implement standalone deterministic engine/gearbox state: ignition, bounded RPM, reverse/neutral/forward gears, timed guarded shifts with held-input edge protection, manual/automatic hysteresis, assisted and explicit clutch, independent service braking, rear-only handbrake, reverse-speed lockout and finite dt/input handling. Expose telemetry and drive/brake intents for later integration. Preserve T1/J1, models, mounting dimensions, visual builders, scene and existing controllers. Include meaningful opt-in selfTest; report unrun tests honestly. Submit API, changed files, tests actually run and risks through complete_stage, then STOP for Codex Studio acceptance. Do not begin controller integration, commit, push or launch a background Claude worker.

Model remains prepared for mechanics, not a drivable car. Keep the library place unsaved while Rojo is connected. Controller integration requires a later bounded assignment after C1 acceptance.
