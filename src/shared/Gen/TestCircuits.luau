-- Hand-authored control points for fixed test circuits. They run through the same spline,
-- road and collision builders the procedural generator will use later.
return {
	-- About 1,300 studs long: start straight heading -Z, a long sweeper, an S-bend,
	-- a tight right-hander near (260, 170) and gentle elevation (0 to 8 studs).
	Phase0Loop = {
		Vector3.new(0, 0, 150),
		Vector3.new(0, 0, -50),
		Vector3.new(30, 2, -170),
		Vector3.new(130, 6, -210),
		Vector3.new(240, 8, -160),
		Vector3.new(260, 6, -60),
		Vector3.new(200, 4, 10),
		Vector3.new(190, 3, 90),
		Vector3.new(260, 2, 170),
		Vector3.new(200, 0, 250),
		Vector3.new(80, 0, 240),
	},
}
