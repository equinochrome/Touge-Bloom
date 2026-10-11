-- Settings for Gen/MountainHeightfield: a seeded Japanese-mountain basin around the circuit.
-- Units: lengths, heights, widths and radii are studs; Frequency is noise cycles per stud
-- (1 / feature size); slopes are rise over run (1.0 = 45 degrees). Every value here is a proposed
-- default pending Studio review, not an approved art or tuning decision.
return {
	-- Mixed into every derived noise seed. Bump when output changes on purpose so old seeds are not
	-- silently reinterpreted.
	GeneratorVersion = 1,

	-- A broad valley floor around the circuit, rising to a ring of forested ridges.
	-- CenterX / CenterZ (studs) may be added here; when absent the road's sample centroid is used,
	-- or the origin when there is no road.
	Basin = {
		FloorHeight = -8, -- natural floor height, a little below the Phase 0 test road (Y 0 to 8)
		FloorRadius = 320, -- horizontal distance from the center where the floor starts rising
		RidgeRadius = 620, -- distance where the ridge ring reaches full height
		RidgeHeight = 150, -- ring height above the floor
	},

	-- Independent noise domains. Each gets its own seed-derived offset and rotation, so changing one
	-- never shifts another. Amplitude is the largest possible contribution in studs (Warp: largest
	-- horizontal displacement; Material: largest change to Materials.RockSlope, rise over run).
	-- Octaves are capped at 8.
	Noise = {
		Warp = { Frequency = 1 / 700, Amplitude = 90, Octaves = 2, Lacunarity = 2, Gain = 0.5 },
		Ridges = {
			Frequency = 1 / 450,
			Amplitude = 110,
			Octaves = 4,
			Lacunarity = 2.1,
			Gain = 0.5,
			Sharpness = 2, -- integer crease exponent, 1 to 4; higher gives narrower crests
			BasinScale = 0.12, -- fraction of Amplitude kept on the valley floor (0 to 1)
		},
		Hills = { Frequency = 1 / 260, Amplitude = 14, Octaves = 4, Lacunarity = 2, Gain = 0.5 },
		Detail = { Frequency = 1 / 40, Amplitude = 1.2, Octaves = 2, Lacunarity = 2, Gain = 0.5 },
		Material = { Frequency = 1 / 80, Amplitude = 0.25, Octaves = 2, Lacunarity = 2, Gain = 0.5 },
	},

	-- Road shaping. Widths are measured outward from the road edge (half the road width).
	Road = {
		Clearance = 0.5, -- terrain under the asphalt and shoulder sits this far below the road surface
		ShoulderWidth = 10, -- flat corridor beyond each road edge
		TransitionWidth = 30, -- minimum blend width from the shoulder edge to natural terrain
		MaxTransitionWidth = 90, -- the blend widens up to this to respect EmbankmentSlope
		EmbankmentSlope = 1.0, -- target peak cut/fill slope; capped blends end up steeper
		-- Where several centerline segments are nearly equally close, their road heights are mixed.
		-- A segment counts while it is less than this much farther away than the nearest one.
		-- Small inside the corridor, which keeps clearance exact; also the fade-out distance for
		-- a segment end that a neighboring segment already covers.
		BlendBand = 0.5,
		-- Extra mixing distance per stud beyond the corridor edge, so the ground between two
		-- road passes at different heights changes over an embankment-like width instead of a step.
		BlendBandGrowth = 1.0,
	},

	Materials = {
		SlopeStep = 2, -- half step of the finite-difference slope estimate
		RockSlope = 1.1, -- slope at or above this (plus Material noise) is Rock
		MeadowSlope = 0.25, -- gentler ground low in the basin is Meadow rather than Forest
		MeadowMaxAboveFloor = 6, -- Meadow only up to Basin.FloorHeight + this
		-- Terrain material per class. Terrain painting only; model materials belong to Codex.
		Terrain = {
			RoadBed = Enum.Material.Ground,
			Shoulder = Enum.Material.Ground,
			Embankment = Enum.Material.Grass,
			Rock = Enum.Material.Rock,
			Meadow = Enum.Material.Grass,
			Forest = Enum.Material.LeafyGrass,
		},
	},

	-- Input bounds that keep construction and queries finite and bounded.
	Limits = {
		MaxRoadSamples = 20000,
		MaxCoordinate = 100000, -- largest |X| or |Z| accepted for road samples and queries
		MaxGridEntries = 500000, -- segment-to-cell registrations in the road lookup grid
		GridCellSize = 32, -- road lookup grid cell, studs
		MaxPairChecks = 4000000, -- segment pairs examined by the corridor-conflict check in new()
	},
}
