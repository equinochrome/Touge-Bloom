-- Profiles for Gen/JapaneseCircuitGenerator: fictional seeded circuits INSPIRED by real Japanese
-- drift venues. They are not replicas or surveys. Every number below is a proposed game-design
-- budget in studs or degrees, chosen to fit the game's constraints; none is a real venue dimension.
-- The `Reference` block of each profile separates what the local reference files show (Verified)
-- from what this game chose (GameDesign). Sources: Design/References/Japanese Circuit Reference Board.md
-- and Design/References/Attachments/Circuits/sources.json.
--
-- Layout is an ordered "turtle" template driven from the start line:
--   { Kind = "Straight", Length = { min, max }, Closure = true? }
--   { Kind = "Arc", Radius = { min, max }, Angle = { min, max } }
-- Angle is in degrees; POSITIVE TURNS RIGHT (toward RoadGeometry's sample.right), negative turns left.
-- Each attempt draws every range from the seed, corrects arc angles so the loop turns exactly 360
-- degrees, then solves the Closure straights' lengths so the loop closes. Every arc gets linear
-- curvature-transition ramps at both ends (Generation.Transition*); its peak curvature stays 1 / Radius.
-- The first feature must be a straight: it holds the start line.
--
-- Elevation: periodic harmonics along the loop, scaled to a seeded Relief (peak-to-peak studs)
-- and reduced if needed until the final samples respect Constraints.MaxGrade. Plateau (0 to 1)
-- softly flattens heights above that fraction of the relief.
--
-- TerrainOverrides: a partial TerrainConfig merged over the T1 defaults (keys must already exist
-- there). TerrainShaping: the generator's basin placement around each generated circuit.
return {
	-- Mixed into every derived seed. Bump when output changes on purpose.
	Version = 1,

	-- Game constraints. These take priority over real-world corner tightness.
	Constraints = {
		Width = 30, -- road width, studs; must equal RoadConfig.Width
		MinRadius = 45, -- smallest horizontal turn radius on the final samples, studs
		MinLength = 1500, -- loop length bounds, studs (sum of all sample segments, including the closing one)
		MaxLength = 2500,
		MaxGrade = 0.08, -- rise over run between consecutive samples
		MinSeparation = 70, -- horizontal distance between nonlocal road stretches, centerline to centerline
	},

	Generation = {
		MaxAttempts = 24, -- default retry budget per generate() call
		MaxAttemptsLimit = 64, -- largest budget options.maxAttempts may request
		DesignMinRadius = 50, -- template radii must be at least this (margin above Constraints.MinRadius)
		MaxTurnCorrection = 30, -- degrees an attempt may add or remove to make the loop turn exactly 360
		MinStartStraight = 120, -- the first (start) straight after closure, studs
		StartFraction = 0.35, -- start line position along the start straight
		ControlSpacing = 12, -- target spacing of emitted control points, studs (uniform around the loop)
		TraceStep = 1, -- integration step for the turtle path, studs
		TransitionMax = 24, -- curvature ramp length at each end of an arc, studs, at most...
		TransitionFraction = 0.25, -- ...this fraction of the arc's constant-radius length
		GradeTrigger = 0.97, -- reduce elevation when final max grade exceeds this fraction of MaxGrade...
		GradeTarget = 0.95, -- ...aiming for this fraction
		MaxGradePasses = 6, -- elevation reductions per attempt
		ElevationProbeCount = 512, -- samples used to normalize the harmonic profile to its relief
		MaxPairChecks = 2000000, -- segment pairs examined by validation's spatial grid
	},

	-- Stable iteration order (generation never relies on pairs() order).
	Order = { "ebisu_north", "ebisu_west", "meihan_c", "nikko", "minami_chiba", "yz_east", "gunsai" },

	Profiles = {
		ebisu_north = {
			DisplayName = "Ebisu North-inspired plateau",
			Salt = 1,
			Category = "Mountain",
			Character = "Plateau sweepers into a far hairpin, an inner return leg, a switchback cluster and a looping finish.",
			Reference = {
				Venue = "Ebisu Circuit, North course (Fukushima)",
				Files = { "Ebisu North layout.pdf", "Ebisu North photo.jpg" },
				Verified = {
					"Official course diagram: total 1155 m, width 8-15 m, longest straight 169 m, minimum radius 7 m",
					"Diagram shows long R70-R125 sweepers, a tight far hairpin (R7), an inner return sweeper (R90) and a cluster of R7-R15 switchbacks",
					"Aerial photo shows the venue on a forested hillside complex",
				},
				GameDesign = {
					"Boomerang loop with a left-hand overall direction; corners opened to game radii of at least 52 studs",
					"Switchbacks spaced to keep 70-stud separation; real gaps are much tighter",
					"Moderate relief with a softened plateau; no surveyed heights exist",
				},
			},
			MinStraight = 40,
			Layout = {
				{ Kind = "Straight", Name = "main", Length = { 172, 218 }, Closure = true },
				{ Kind = "Arc", Name = "plateau1", Radius = { 135, 165 }, Angle = { -39.2, -30.8 } },
				{ Kind = "Straight", Length = { 48, 72 } },
				{ Kind = "Arc", Name = "plateau2", Radius = { 153, 187 }, Angle = { -33.6, -26.4 } },
				{ Kind = "Straight", Length = { 56, 84 } },
				{ Kind = "Arc", Name = "plateau3", Radius = { 162, 198 }, Angle = { -44.8, -35.2 } },
				{ Kind = "Straight", Name = "descent", Length = { 314, 384 }, Closure = true },
				{ Kind = "Arc", Name = "farHairpin", Radius = { 53.2, 58.8 }, Angle = { -178.5, -171.5 } },
				{ Kind = "Straight", Name = "return", Length = { 64, 96 } },
				{ Kind = "Arc", Name = "returnSweep", Radius = { 180, 220 }, Angle = { 21.25, 28.75 } },
				{ Kind = "Straight", Length = { 48, 72 } },
				{ Kind = "Arc", Name = "switchback1", Radius = { 52.25, 57.75 }, Angle = { 64.4, 75.6 } },
				{ Kind = "Arc", Name = "switchback2", Radius = { 52.25, 57.75 }, Angle = { -156, -144 } },
				{ Kind = "Straight", Length = { 32, 48 } },
				{ Kind = "Arc", Name = "switchback3", Radius = { 52.25, 57.75 }, Angle = { 144, 156 } },
				{ Kind = "Straight", Length = { 170, 230 } },
				{ Kind = "Arc", Name = "finishLoop", Radius = { 56.4, 63.6 }, Angle = { -182, -168 } },
			},
			Elevation = { Relief = { 14, 24 }, Harmonics = { 1, 0.35 }, Plateau = 0.6 },
			TerrainOverrides = {
				Basin = { RidgeHeight = 130 },
				Noise = { Ridges = { Amplitude = 100 }, Hills = { Amplitude = 12 } },
			},
			TerrainShaping = { FloorDrop = 6, FloorMargin = 80, RidgeWidth = 300 },
		},

		ebisu_west = {
			DisplayName = "Ebisu West-inspired ridge loop",
			Salt = 2,
			Category = "Mountain",
			Character = "Long flowing loop: fast sweepers on long legs between two braking hairpins, with an outward kink.",
			Reference = {
				Venue = "Ebisu Circuit, West (Nishi) road course",
				Files = { "Ebisu West layout.pdf", "Ebisu West photo.jpg" },
				Verified = {
					"Official diagram: total 2103 m, width 10-15 m, longest straight 275.92 m",
					"Diagram table: radii 20-100 m (sweepers listed up to R300/R1000), maximum grade 9.8%, maximum elevation difference 38.18 m",
					"Elongated layout with hairpins at both ends; aerial photo shows it laid along a forested slope",
				},
				GameDesign = {
					"Grade capped at 8% (game rule) instead of the listed 9.8%; relief budget 26-40 studs before grade reduction",
					"Hairpins opened to at least 53 studs; the infield complex is simplified to one kink pair",
				},
			},
			MinStraight = 30,
			Layout = {
				{ Kind = "Straight", Name = "main", Length = { 600, 676 }, Closure = true },
				{ Kind = "Arc", Radius = { 270, 330 }, Angle = { 9.6, 14.4 } },
				{ Kind = "Straight", Length = { 127.5, 172.5 } },
				{ Kind = "Arc", Name = "hairpinAEntry", Radius = { 55.1, 60.9 }, Angle = { 82.45, 87.55 } },
				{ Kind = "Straight", Name = "hairpinMid", Length = { 33.75, 56.25 }, Closure = true },
				{ Kind = "Arc", Name = "hairpinAExit", Radius = { 55.1, 60.9 }, Angle = { 82.45, 87.55 } },
				{ Kind = "Straight", Name = "back", Length = { 176, 224 } },
				{ Kind = "Arc", Radius = { 216, 264 }, Angle = { -19.2, -12.8 } },
				{ Kind = "Arc", Radius = { 198, 242 }, Angle = { 14.4, 21.6 } },
				{ Kind = "Straight", Length = { 211, 269 } },
				{ Kind = "Arc", Name = "kink1", Radius = { 59.8, 70.2 }, Angle = { 49.5, 60.5 } },
				{ Kind = "Arc", Name = "kink2", Radius = { 59.8, 70.2 }, Angle = { -60.5, -49.5 } },
				{ Kind = "Straight", Name = "approach", Length = { 128, 192 } },
				{ Kind = "Arc", Name = "hairpinB", Radius = { 53.2, 58.8 }, Angle = { 160.05, 169.95 } },
				{ Kind = "Arc", Radius = { 225, 275 }, Angle = { 8.8, 13.2 } },
			},
			Elevation = { Relief = { 26, 40 }, Harmonics = { 1, 0.3, 0.15 } },
			TerrainOverrides = {
				Basin = { RidgeHeight = 150 },
				Noise = { Ridges = { Amplitude = 110 }, Hills = { Amplitude = 14 } },
			},
			TerrainShaping = { FloorDrop = 8, FloorMargin = 80, RidgeWidth = 300 },
		},

		meihan_c = {
			DisplayName = "Meihan C-inspired technical",
			Salt = 3,
			Category = "Compact",
			Character = "Compact, nearly level technical loop: a strong entry corner then linked transitions and a long hairpin.",
			Reference = {
				Venue = "Meihan Sportsland, C course (Nara)",
				Files = { "Meihan C 2025 event map.jpg", "Meihan C 2025 photo.jpg" },
				Verified = {
					"2025-04-20 gymkhana event diagram: compact layout with linked infield sections and a long loop at one end",
					"The cone route on that diagram is event-specific, not a permanent drift line",
					"Onsite photo shows open, essentially level asphalt with tree-lined low hills behind",
				},
				GameDesign = {
					"Relief 2-5 studs; tight-but-legal radii (52-64 studs) to read as technical",
					"Meihan E is NOT represented: no verified E references exist",
				},
			},
			MinStraight = 30,
			Layout = {
				{ Kind = "Straight", Name = "main", Length = { 270, 330 }, Closure = true },
				{ Kind = "Arc", Name = "entry", Radius = { 56.4, 63.6 }, Angle = { 114, 126 } },
				{ Kind = "Straight", Length = { 37.5, 62.5 } },
				{ Kind = "Arc", Radius = { 52.25, 57.75 }, Angle = { -97.2, -82.8 } },
				{ Kind = "Arc", Radius = { 52.25, 57.75 }, Angle = { 103.4, 116.6 } },
				{ Kind = "Straight", Length = { 88, 132 } },
				{ Kind = "Arc", Radius = { 54.5, 61.5 }, Angle = { 73.6, 86.4 } },
				{ Kind = "Arc", Radius = { 52.25, 57.75 }, Angle = { -106, -94 } },
				{ Kind = "Arc", Name = "longHairpin", Radius = { 52.25, 57.75 }, Angle = { 134.4, 145.6 } },
				{ Kind = "Straight", Name = "back", Length = { 297, 363 }, Closure = true },
				{ Kind = "Arc", Name = "last", Radius = { 56.4, 63.6 }, Angle = { 94, 106 } },
			},
			Elevation = { Relief = { 2, 5 }, Harmonics = { 1, 0.5 } },
			TerrainOverrides = {
				Basin = { RidgeHeight = 30 },
				Noise = { Ridges = { Amplitude = 25, BasinScale = 0.05 }, Hills = { Amplitude = 4 }, Detail = { Amplitude = 0.6 } },
			},
			TerrainShaping = { FloorDrop = 1.5, FloorMargin = 120, RidgeWidth = 400 },
		},

		nikko = {
			DisplayName = "Nikko-inspired flow circuit",
			Salt = 4,
			Category = "Circuit",
			Character = "Linked flowing corners, a fast wide sweeper and a long recovery straight, with modest elevation.",
			Reference = {
				Venue = "Nikko Circuit (Tochigi), post-February-2018 layout",
				Files = { "Nikko organizer layout.webp", "Nikko corner photo.webp" },
				Verified = {
					"Organizer aerial layout (challenge-road.net; official download failed) numbers 12 corners: a wide outer loop with long straights and an infield S and hairpin section",
					"Corner-1 photo shows guardrail-lined asphalt with wooded hills beside the track",
					"Official guide distinguishes pre/post February 2018 layouts; the revised layout is the inspiration",
				},
				GameDesign = {
					"Relief 6-12 studs; no surveyed heights",
					"Fast sweeper radius 189-231 studs; infield corners opened to at least 55 studs",
				},
			},
			MinStraight = 40,
			Layout = {
				{ Kind = "Straight", Name = "recovery", Length = { 457, 537 }, Closure = true },
				{ Kind = "Arc", Name = "fastSweep", Radius = { 189, 231 }, Angle = { 69, 81 } },
				{ Kind = "Arc", Name = "linked", Radius = { 73.6, 86.4 }, Angle = { 78.2, 91.8 } },
				{ Kind = "Straight", Name = "top", Length = { 104, 156 } },
				{ Kind = "Arc", Name = "infield1", Radius = { 59.8, 70.2 }, Angle = { -77, -63 } },
				{ Kind = "Arc", Name = "infield2", Radius = { 57, 67 }, Angle = { 87.4, 102.6 } },
				{ Kind = "Straight", Length = { 56, 84 } },
				{ Kind = "Arc", Radius = { 55.2, 64.8 }, Angle = { 73.6, 86.4 } },
				{ Kind = "Arc", Radius = { 59.8, 70.2 }, Angle = { -50.4, -39.6 } },
				{ Kind = "Straight", Name = "exit", Length = { 328, 400 }, Closure = true },
				{ Kind = "Arc", Name = "hairpin", Radius = { 54.5, 61.5 }, Angle = { 134.4, 145.6 } },
			},
			Elevation = { Relief = { 6, 12 }, Harmonics = { 1, 0.4 } },
			TerrainOverrides = {
				Basin = { RidgeHeight = 70 },
				Noise = { Ridges = { Amplitude = 60 }, Hills = { Amplitude = 8 } },
			},
			TerrainShaping = { FloorDrop = 3, FloorMargin = 100, RidgeWidth = 320 },
		},

		minami_chiba = {
			DisplayName = "Minami Chiba-inspired practice loop",
			Salt = 5,
			Category = "Compact",
			Character = "Accessible practice loop: long straights, a big open loop, one gentle esse and generous radii.",
			Reference = {
				Venue = "Minami Chiba Circuit (Chiba)",
				Files = { "Minami Chiba 2018 layout.jpg" },
				Verified = {
					"Diagram is historical (labelled 2017.11 new, served from a 2018 path); current configuration unverified",
					"It shows a long diagonal straight, a large loop around an infield and a twisty upper section",
				},
				GameDesign = {
					"Easiest profile: radii 64-105 studs, relief 2-5 studs, wide clear runoff implied by low terrain",
					"Tight historical corners scaled up to the game's radius minimum",
				},
			},
			MinStraight = 40,
			Layout = {
				{ Kind = "Straight", Name = "main", Length = { 427.5, 522.5 }, Closure = true },
				{ Kind = "Arc", Name = "loop", Radius = { 85.5, 104.5 }, Angle = { 92, 108 } },
				{ Kind = "Straight", Length = { 64, 96 } },
				{ Kind = "Arc", Radius = { 81, 99 }, Angle = { 73.6, 86.4 } },
				{ Kind = "Straight", Name = "mid", Length = { 64, 96 } },
				{ Kind = "Arc", Name = "esse1", Radius = { 64.4, 75.6 }, Angle = { -77, -63 } },
				{ Kind = "Arc", Name = "esse2", Radius = { 64.4, 75.6 }, Angle = { 103.4, 116.6 } },
				{ Kind = "Straight", Name = "diagonal", Length = { 268, 362 }, Closure = true },
				{ Kind = "Arc", Name = "last", Radius = { 87.4, 102.6 }, Angle = { 134.4, 145.6 } },
			},
			Elevation = { Relief = { 2, 5 }, Harmonics = { 1 } },
			TerrainOverrides = {
				Basin = { RidgeHeight = 30 },
				Noise = { Ridges = { Amplitude = 25, BasinScale = 0.05 }, Hills = { Amplitude = 4 }, Detail = { Amplitude = 0.6 } },
			},
			TerrainShaping = { FloorDrop = 1.5, FloorMargin = 120, RidgeWidth = 400 },
		},

		yz_east = {
			DisplayName = "YZ East-inspired tandem course",
			Salt = 7,
			Category = "Compact",
			Character = "Short technical course: a long main straight, a big first corner, S-bends, a crank and a final corner.",
			Reference = {
				Venue = "YZ Circuit, East course (Gifu), single configuration",
				Files = { "YZ East layout.pdf", "YZ East overview.jpg" },
				Verified = {
					"Official East guide: about 1000 m long, width 11-13 m, longest straight 240 m",
					"Named sections: 1st corner after the long straight, S-curve, lakeside, right-angle corner, crank, final corner",
					"Labelled radii on the diagram range R10-R80",
				},
				GameDesign = {
					"Main straight about a third of the loop to keep its signature; corners opened to at least 51 studs",
					"Crank represented by an opposite 85/100-degree pair; relief 6-11 studs",
				},
			},
			MinStraight = 40,
			Layout = {
				{ Kind = "Straight", Name = "main", Length = { 611, 689 }, Closure = true },
				{ Kind = "Arc", Name = "first", Radius = { 57, 67 }, Angle = { 169.75, 180.25 } },
				{ Kind = "Straight", Length = { 40, 60 } },
				{ Kind = "Arc", Name = "s1", Radius = { 72, 88 }, Angle = { -36.8, -27.2 } },
				{ Kind = "Arc", Name = "s2", Radius = { 67.5, 82.5 }, Angle = { 30.6, 41.4 } },
				{ Kind = "Straight", Name = "back", Length = { 32, 48 } },
				{ Kind = "Arc", Name = "lakeside1", Radius = { 63, 77 }, Angle = { -41.4, -30.6 } },
				{ Kind = "Arc", Name = "lakeside2", Radius = { 72, 88 }, Angle = { 27.2, 36.8 } },
				{ Kind = "Straight", Length = { 40, 60 } },
				{ Kind = "Arc", Name = "rightAngle", Radius = { 63, 77 }, Angle = { 49.5, 60.5 } },
				{ Kind = "Straight", Length = { 32, 48 } },
				{ Kind = "Arc", Name = "crankIn", Radius = { 51.7, 58.3 }, Angle = { -90.1, -79.9 } },
				{ Kind = "Straight", Length = { 64, 96 } },
				{ Kind = "Arc", Name = "crankOut", Radius = { 51.7, 58.3 }, Angle = { 94, 106 } },
				{ Kind = "Straight", Name = "approach", Length = { 56, 84 }, Closure = true },
				{ Kind = "Arc", Name = "final", Radius = { 59.8, 70.2 }, Angle = { 109.25, 120.75 } },
			},
			Elevation = { Relief = { 6, 11 }, Harmonics = { 1, 0.5 } },
			TerrainOverrides = {
				Basin = { RidgeHeight = 60 },
				Noise = { Ridges = { Amplitude = 50 }, Hills = { Amplitude = 8 } },
			},
			TerrainShaping = { FloorDrop = 3, FloorMargin = 100, RidgeWidth = 320 },
		},

		gunsai = {
			DisplayName = "Gunsai-inspired forest mountain loop",
			Salt = 6,
			Category = "Mountain",
			Character = "Forested mountain loop: continuous grades, linked bends, a restrained switchback pair and ridge sweepers.",
			Reference = {
				Venue = "Gunma Cycle Sports Center (Gunsai)",
				Files = { "Gunsai facility map.jpg", "Gunsai cycling course.jpg" },
				Verified = {
					"Facility guide names a 6 km circuit course used as a cycling route",
					"Illustrated course map (not a survey) marks uphill (上り) sections, linked bends and hairpin-like turns",
					"Facility map shows the course running through forest",
				},
				GameDesign = {
					"Compressed to the game's 1500-2500 stud loop; primary mountain-road profile",
					"Relief 34-55 studs before grade reduction to 8%; switchback radius 55-61 studs",
				},
			},
			MinStraight = 30,
			Layout = {
				{ Kind = "Straight", Name = "main", Length = { 378, 444 }, Closure = true },
				{ Kind = "Arc", Radius = { 90, 110 }, Angle = { 29.75, 40.25 } },
				{ Kind = "Arc", Radius = { 90, 110 }, Angle = { -40.25, -29.75 } },
				{ Kind = "Straight", Length = { 64, 96 } },
				{ Kind = "Arc", Name = "corner1", Radius = { 73.6, 86.4 }, Angle = { 84.6, 95.4 } },
				{ Kind = "Straight", Length = { 102, 138 } },
				{ Kind = "Arc", Name = "switchback1", Radius = { 55.7, 60.3 }, Angle = { 145.5, 154.5 } },
				{ Kind = "Straight", Name = "switchLeg", Length = { 85, 115 } },
				{ Kind = "Arc", Name = "switchback2", Radius = { 55.7, 60.3 }, Angle = { -154.5, -145.5 } },
				{ Kind = "Arc", Radius = { 81, 99 }, Angle = { 39.6, 50.4 } },
				{ Kind = "Arc", Radius = { 76.5, 93.5 }, Angle = { -34.5, -25.5 } },
				{ Kind = "Arc", Name = "topCorner", Radius = { 81, 99 }, Angle = { 69, 81 } },
				{ Kind = "Straight", Name = "ridge", Length = { 102, 138 } },
				{ Kind = "Arc", Radius = { 99, 121 }, Angle = { 21.25, 28.75 } },
				{ Kind = "Arc", Radius = { 90, 110 }, Angle = { -28.75, -21.25 } },
				{ Kind = "Arc", Name = "corner3", Radius = { 69, 81 }, Angle = { 84.6, 95.4 } },
				{ Kind = "Straight", Name = "descent", Length = { 127.5, 172.5 }, Closure = true },
				{ Kind = "Arc", Radius = { 64.4, 75.6 }, Angle = { -44.8, -35.2 } },
				{ Kind = "Arc", Name = "last", Radius = { 61.1, 68.9 }, Angle = { 124.8, 135.2 } },
			},
			Elevation = { Relief = { 34, 55 }, Harmonics = { 1, 0.45, 0.2 } },
			TerrainOverrides = {
				Basin = { RidgeHeight = 180 },
				Noise = { Ridges = { Amplitude = 130 }, Hills = { Amplitude = 16 } },
			},
			TerrainShaping = { FloorDrop = 10, FloorMargin = 60, RidgeWidth = 260 },
		},
	},
}
