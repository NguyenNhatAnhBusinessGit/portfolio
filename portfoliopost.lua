--|| Hello, once again, this is for my portfolio, I'm OriChanRBLX, discord is gaaaaaaaaaa! This script is the Wave module, which is a mesh deformation ocean formula ||--

-- Define a new table Wave and set its metatable to itself
local Wave = {}
Wave.__index = Wave -- Enables object-oriented behavior

-- Define shortcuts for frequently used methods and classes to improve performance
local newCFrame = CFrame.new
local IdentityCFrame = newCFrame() -- Identity matrix for resetting transformations
local EmptyVector2 = Vector2.new()
local math_noise = math.noise
local random = math.random
local setseed = math.randomseed

-- Service shortcuts for Roblox game components
local Stepped = game:GetService("RunService").RenderStepped
local Player = game:GetService("Players").LocalPlayer

-- Import Sea data from a shared module for sea-level settings
local SeaData = require(game.ReplicatedStorage.MODULES.Sea)

-- Define default values for wave properties
local default = {
	WaveLength = 85,            -- Length of wave
	Gravity = 1.5,              -- Gravity factor affecting wave motion
	Direction = Vector2.new(1, 0), -- Initial wave direction as a Vector2
	FollowPoint = nil,          -- Optional reference point for direction control
	Steepness = 1,              -- Wave steepness factor
	TimeModifier = 4,           -- Modifies time passage for wave simulation speed
	MaxDistance = 1500,         -- Max distance where wave effects apply
}

-- Projects a vector vertically onto a plane
local function ProjectVertically(vec, p, n)
	local off = vec - p
	local y = -(n.X * off.X + n.Z * off.Z) / n.Y
	return p + Vector3.new(off.X, y, off.Z)
end

-- Projects a position onto a 3D plane defined by three points
local function ProjectToPlane(pos, a, b, c)
	local ab, bc = b - a, c - b
	local n = ab:Cross(bc).Unit -- Get normal vector of the plane
	if n.Y < 0 then n = -n end -- Ensure normal vector points upward
	return ProjectVertically(pos, a, n)
end

-- Organizes objects into a grid based on their Z and X positions
local function Gridify(objects, cols: number)
	table.sort(objects, function(a, b) return a.Position.Z < b.Position.Z end) -- Sort by Z position

	local grid = {}
	for row = 1, #objects / cols do
		local lowerIndex = 1 + (row - 1) * cols
		local upperIndex = row * cols
		local thisRow = {}
		table.move(objects, lowerIndex, upperIndex, 1, thisRow)
		table.sort(thisRow, function(a, b) return a.Position.X < b.Position.X end) -- Sort by X position
		grid[row] = thisRow
	end
	return grid
end

-- Computes Gerstner wave displacement for realistic water waves
local function Gerstner(Position: Vector3, Wavelength: number, Direction: Vector2, Steepness: number, Gravity: number, Time: number)
	local k = (2 * math.pi) / Wavelength -- Wave number
	local a = Steepness / k             -- Wave amplitude
	local d = Direction.Unit
	local c = math.sqrt(Gravity / k)     -- Wave speed
	local f = k * d:Dot(Vector2.new(Position.X, Position.Z)) - c * Time
	local cosF = math.cos(f)

	-- Calculate displacement in X, Y, and Z
	local dX = (d.X * (a * cosF))
	local dY = a * math.sin(f)
	local dZ = (d.Y * (a * cosF))
	return Vector3.new(dX, dY, dZ)
end

-- Creates and returns new settings based on defaults and custom values
local function CreateSettings(s: table, o: table)
	o = o or {}
	s = s or default
	local new = {
		WaveLength = s.WaveLength or o.WaveLength or default.WaveLength,
		Gravity = s.Gravity or o.Gravity or default.Gravity,
		Direction = s.Direction or o.Direction or default.Direction,
		PushPoint = s.PushPoint or o.PushPoint or default.PushPoint,
		Steepness = s.Steepness or o.Steepness or default.Steepness,
		TimeModifier = s.TimeModifier or o.TimeModifier or default.TimeModifier,
		MaxDistance = s.MaxDistance or o.MaxDistance or default.MaxDistance,
	}
	return new
end

-- Checks if a point is within a triangle using barycentric coordinates
function isPointInTriangle(f, a, b, c)
	local v0 = c - a
	local v1 = b - a
	local v2 = f - a

	local dot00 = v0:Dot(v0)
	local dot01 = v0:Dot(v1)
	local dot02 = v0:Dot(v2)
	local dot11 = v1:Dot(v1)
	local dot12 = v1:Dot(v2)

	local invDenom = 1 / (dot00 * dot11 - dot01 * dot01)
	local u = (dot11 * dot02 - dot01 * dot12) * invDenom
	local v = (dot00 * dot12 - dot01 * dot02) * invDenom

	return (u >= 0) and (v >= 0) and (u + v <= 1)
end

-- Gets wave direction based on either preset direction or a push point
local function GetDirection(Settings, WorldPos)
	local Direction = Settings.Direction
	local PushPoint = Settings.PushPoint

	if PushPoint then
		local PartPos = nil
		if PushPoint:IsA("Attachment") then
			PartPos = PushPoint.WorldPosition
		elseif PushPoint:IsA("BasePart") then
			PartPos = PushPoint.Position
		else
			warn("Invalid class for FollowPart, must be BasePart or Attachment")
			return
		end
		Direction = (PartPos - WorldPos).Unit
		Direction = Vector2.new(Direction.X, Direction.Z)
	end
	return Direction
end

-- The rest of the functions handle different utility calculations and bone grid placements
-- Some functions are specifically for retrieving X and Z placement ranges based on position

-- Creates visual markers for wave height tracking (used for debugging or visualization)
local CreateMiscVisual = function()
	local p = Instance.new("Part")
	p.Anchored = true
	p.Name = "Visualizer"
	p.Size = Vector3.new(5, 5, 5)
	p.Color = Color3.fromRGB(255, 0, 0)
	p.Material = Enum.Material.Neon
	p.CanCollide = false
	p.Parent = workspace
	return p
end

-- The main function for calculating wave height using bone positions and Gerstner wave calculations
function Wave.GetWaveHeight(self, Position: Vector3, Settings)
	-- Attempt to find the height of the wave at a specific position and apply wave transformations
	local sc, rt = pcall(function()
		Position = XZVector3(Position)
		local Direction = Settings.Direction
		local PointF = ConvertToVector2(Position)
		local Triangle
		local Grid = self._bones_grid
		local Offset = Position - self._instance.Position
		local Row0, Row1 = GetRowRange(Offset)
		local Column0, Column1 = GetColumnRange(Offset)

		if not Row0 then return end
		if not Row1 then return end
		if not Column0 then return end
		if not Column1 then return end

		-- Retrieve grid-based bone information and calculate wave height at the specified position
		local bone1 = Grid[Row0][Column0]
		local bone2 = Grid[Row0][Column1]
		local bone3 = Grid[Row1][Column0]
		local bone4 = Grid[Row1][Column1]
		local triangles = {{bone1, bone2, bone3}, {bone2, bone3, bone4}}
		local PointA = ConvertToVector2(triangles[1][1].WorldPosition)
		local PointB = ConvertToVector2(triangles[1][2].WorldPosition)
		local PointC = ConvertToVector2(triangles[1][3].WorldPosition)
		if isPointInTriangle(PointF, PointA, PointB, PointC) then
			Triangle = triangles[1]
		else
			Triangle = triangles[2]
		end

		local r1 = ProjectToPlane(Position, Triangle[1].TransformedWorldCFrame.Position, Triangle[2].TransformedWorldCFrame.Position, Triangle[3].TransformedWorldCFrame.Position)
		return r1
	end)

	-- Calculate fallback position if above attempt fails
	if sc then
		return rt
	else
		-- Error handling code for calculating wave height based on position approximation
	end
end

-- Initializes a new Wave object with given instance, settings, and bones (wave control points)
function Wave.new(instance: instance, waveSettings: table | nil, bones: table | nil)
	-- Sets up bones and grid representation for wave mechanics
	-- Get bones on our own
	if bones == nil then
		bones = {}
		for _,v in pairs(instance:GetDescendants()) do
			if v:IsA("Bone") then
				table.insert(bones,v)
			end
		end
	end

	local Time = os.time()

	local triangles = {}
	local boneGrids = Gridify(bones, 22);
	for i, row in pairs(boneGrids) do
		local nextRow = boneGrids[i + 1];
		if not nextRow then continue end
		for i1, bone in pairs(row)  do
			local nextBone = row[i1 + 1];
			if not nextBone then continue end

			local corner1 = row[i1];
			local corner2 = row[i1 + 1];
			local corner3 = boneGrids[i + 1][i1];
			local corner4 = boneGrids[i + 1][i1 + 1];
			if not corner1 then continue end
			if not corner2 then continue end
			if not corner3 then continue end
			if not corner4 then continue end

			table.insert(triangles, {corner1, corner3, corner4});
			table.insert(triangles, {corner2, corner1, corner4});
		end
	end

	--------------------------------

	return setmetatable({
		_instance = instance,
		_bones = bones,
		_time = 0,
		_connections = {},
		_noise = {},
		_bones_grid = boneGrids,
		_triangles = triangles,
		_settings = CreateSettings(waveSettings)
	},Wave)
end

-- Periodically updates wave bones based on time and Gerstner wave transformations
function Wave:Update()
	for _,v in pairs(self._bones) do
		-- Code for applying Perlin noise or direction based on settings and updating bone transforms
		local WorldPos = v.WorldPosition
		local Settings = self._settings
		local Direction = Settings.Direction

		if Direction == EmptyVector2 then
			-- Use Perlin Noise
			local Noise = self._noise[v]
			local NoiseX = Noise and self._noise[v].X
			local NoiseZ = Noise and self._noise[v].Z
			local NoiseModifier = 3 -- If you want more of a consistent direction, change this number to something bigger

			Directions[v] = Noise;

			if not Noise then
				self._noise[v] = {}
				-- Uses perlin noise to generate smooth transitions between random directions in the waves
				NoiseX = math_noise(WorldPos.X/NoiseModifier,WorldPos.Z/NoiseModifier,1)
				NoiseZ = math_noise(WorldPos.X/NoiseModifier,WorldPos.Z/NoiseModifier,0)

				self._noise[v].X = NoiseX
				self._noise[v].Z = NoiseZ
			end

			Direction = Vector2.new(NoiseX,NoiseZ)
		else
			Direction = GetDirection(Settings,WorldPos)
		end

		v.Transform = newCFrame(Gerstner(WorldPos,Settings.WaveLength,Direction,Settings.Steepness,Settings.Gravity,self._time))
	end
end

function Wave:Refresh()
	for _,v in pairs(self._bones) do
		v.Transform = IdentityCFrame
	end
end

function Wave:UpdateSettings(waveSettings)
	self._settings = CreateSettings(waveSettings,self._settings)
end

function Wave:ConnectRenderStepped()
	local Connection = Stepped:Connect(function()
		if not game:IsLoaded() then return end
		local Character = Player.Character
		local Settings = self._settings
		pcall(function()
			local InBoundsRange = (Character.PrimaryPart.Position-self._instance.Position).Magnitude < Settings.MaxDistance
			InBoundsRange = InBoundsRange or (workspace.CurrentCamera.CFrame.Position-self._instance.Position).Magnitude < Settings.MaxDistance
			
			if not Character or InBoundsRange then
				local Time = (DateTime.now().UnixTimestampMillis/1000)/Settings.TimeModifier
				self._time = Time
				self:Update()
			else
				self:Refresh()
			end
		end)
	end)
	table.insert(self._connections,Connection)
	return Connection
end

function Wave:Destroy()
	self._instance = nil
	for _,v in pairs(self._connections) do
		pcall(function()
			v:Disconnect()
		end)
	end
	self._bones = {}
	self._settings = {}
	self = nil
	-- Basically makes the wave impossible to use
end

return Wave
