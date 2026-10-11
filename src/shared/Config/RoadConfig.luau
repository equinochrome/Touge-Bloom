-- Road dimensions and build settings shared by the server (collision) and client (visuals).
return {
	Width = 30,
	SampleSpacing = 4, -- target studs between centerline samples
	ChunkSamples = 48, -- centerline samples per visual mesh chunk

	SkirtDepth = 1.5, -- edge lip that hides the gap between road and ground
	SkirtFlare = 0.3,

	CollisionThickness = 2,
	CollisionOverlap = 0.25, -- extra length per segment end, on top of the corner-gap fill

	TextureRepeatLength = 30, -- studs of road per UV tile along its length (rounded to fit the loop)
	SurfaceColor = Color3.fromRGB(64, 64, 68),
	SurfaceMaterial = Enum.Material.Asphalt,

	-- Set true to skip EditableMesh and build the visual road from WedgeParts.
	ForceWedgeFallback = false,
	WedgeThickness = 0.2,
}
