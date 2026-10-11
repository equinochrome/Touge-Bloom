---
tags: [design, home]
updated: 2026-10-10
---
# Scenic Drift — design vault

A Roblox drift game with believable handling, beautiful natural scenery, seeded circuits, and cars players can make their own.

## Direction agreed with the user
- Japanese mountain roads are the first setting.
- Smooth, natural scenery; avoid a blocky finished appearance.
- Randomly generated circuits that remain fun and drivable.
- A selection of car platforms with tuning and customization.
- More scenic destinations later, including a coastal setting.

## Read the design
1. [[Design/Visual Direction|Visual direction]]
2. [[Design/References/Japanese Mountain Reference Board|Photo reference board]]
3. [[Design/Driving Feel|Driving feel]]
4. [[Design/Cars and Upgrades|Cars and upgrades]]
5. [[Design/Procedural Circuits|Procedural circuits]]
6. [[Design/Monetization|Monetization proposal]]
7. [[Design/Visual Review|Screenshot review checklist]]
8. [[Design/Claude Brief|Instructions to give Claude]]

Existing technical plan: [[PLAN]]. Existing prototype setup: [[docs/PHASE0]].

## How to use this vault
Open this project folder as an existing vault in Obsidian. No community plugins are needed. Put your reference images and Studio screenshots in `Design/References/Attachments`; pasted attachments are configured to go there.

The reference board embeds external images, which need internet access. Each has a source link if the image stops loading. Linked photographs guide composition and materials; they are not game textures or licensed production assets.

Claude and Codex can read these Markdown files directly. For visual work, ask the agent to inspect the actual reference pictures and current Studio screenshots; reading captions alone is insufficient.

## Current scope
The repository already contains Phase 0 files. Their presence does not mean runtime tests have passed. Use the existing phase checklist before advancing.

Build and approve one beautiful road section before spreading the same art direction across the procedural world. Garage systems and monetization follow the driving prototype.

## Decision status
Notes distinguish **agreed direction**, **proposed defaults**, and **later features**. Proposals remain adjustable. Do not silently treat every note as approved implementation scope.

## Project ownership
Codex manages the project and owns modeling. Claude programs car mechanics and terrain generation only.
See [[Design/Project Management]], [[Design/Asset Contract]] and [[Design/References/Modeling Detail Board]].

## Real circuit research

[[Japanese Circuit Reference Board]] — local photos, course diagrams and source notes.
[[Japanese Circuit Generation Brief]] — assigned to Claude as J1-japanese-circuits; implementation pending Codex tests.

[[Cedar Coupe Mechanics Handoff]] — Blender prototype, verified model interface and Claude drivetrain backlog.
