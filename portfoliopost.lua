--|| OriChanRBLX's Wave Module - A portfolio piece demonstrating Gerstner wave simulation on deformed mesh bones to create a custom ocean ||--
-- This script uses the Gerstner wave formula on bones to simulate ocean movement. Core functionality includes calculating wave height by sampling triangles and nearby bones.

-- This code simulates a wave effect using Gerstner wave principles. The wave height is calculated based on a grid of "bones" (control points that can be transformed) using trigonometric transformations. Here's a breakdown of how it works:

-- Key Components of the Code
-- Wave.GetWaveHeight:

-- Calculates the height of a wave at a specific position.
-- Uses a grid of bones as the wave’s base structure, divided into triangles.
-- Determines which triangle contains the position in question, then uses Gerstner wave functions to simulate the wave's height at that position.
-- If the first method of determining wave height fails, it falls back on an approximation that adjusts based on surrounding grid cells.
-- Wave.new:

-- Initializes a new Wave object with given settings and bones.
-- The bones are found and structured into a grid, which will be used to calculate the wave surface.
-- The wave "surface" is represented by triangles created between four adjacent bones in the grid. These triangles form the basis for determining wave height at any point.


-- Key Calculations and Concepts
-- Gerstner Wave Calculations:

-- Gerstner waves simulate ocean waves realistically by displacing points along both the vertical and horizontal axes.
-- Each bone in the grid is displaced based on wave parameters like steepness, wavelength, and direction.
-- Over time, this displacement changes based on the TimeModifier, creating a rolling wave effect.
-- Grid and Triangular Surface Representation:

-- The grid of bones is divided into small triangles, which makes the wave calculation manageable by localizing calculations to smaller areas.
-- By calculating the height of each triangle, the wave can respond to specific points more accurately.
-- Summary of Execution Flow
-- Initialize the Wave:

-- The wave is initialized with bones, which form the surface grid.
-- Continuous Update:

-- In each frame, the Update function recalculates each bone’s position based on Gerstner wave equations, making the wave move realistically.
-- Dynamic Settings:

-- UpdateSettings and ConnectRenderStepped allow real-time adjustments and optimizations. The wave will stop updating when the player moves far enough away, reducing computational load.
-- Cleanup:

-- Destroy is called when the wave object is no longer needed, releasing memory and resources.

-- Create Wave table and enable object-oriented behavior through metatable setup
local Wave = {}
Wave.__index = Wave 

-- Shortcuts for common methods, variables, and constants to improve performance
local newCFrame = CFrame.new
local IdentityCFrame = newCFrame() -- Identity matrix for transformations reset
local EmptyVector2 = Vector2.new()
local math_noise = math.noise
local random = math.random
local setseed = math.randomseed
local TAU = 2 * math.pi -- Constant for better readability and performance

-- Services for game components
local Stepped = game:GetService("RunService").RenderStepped
local Player = game:GetService("Players").LocalPlayer

-- Sea data from shared module, containing sea level and wave settings
local SeaData = require(game.ReplicatedStorage.MODULES.Sea)

-- Default wave properties
local default = {
    WaveLength = 85,              -- Controls wavelength
    Gravity = 1.5,                -- Gravity affecting wave speed
    Direction = Vector2.new(1, 0),-- Default direction vector
    FollowPoint = nil,            -- Optional point to direct wave towards
    Steepness = 1,                -- Steepness factor affecting wave height
    TimeModifier = 4,             -- Speed of wave animation over time
    MaxDistance = 1500,           -- Max effective distance for waves
}

-- Projects a vector vertically to simulate wave height impact on the y-axis
local function ProjectVertically(vec, p, n)
    local off = vec - p
    local y = -(n.X * off.X + n.Z * off.Z) / n.Y
    return p + Vector3.new(off.X, y, off.Z)
end

-- Projects position onto a plane defined by three points, to simulate water level changes
local function ProjectToPlane(pos, a, b, c)
    local ab, bc = b - a, c - b
    local n = ab:Cross(bc).Unit -- Normal vector for the plane
    if n.Y < 0 then n = -n end  -- Ensures upward orientation
    return ProjectVertically(pos, a, n)
end

-- Converts a list of objects into a grid based on Z and X positions, useful for organizing wave effect areas
local function Gridify(objects, cols: number)
    table.sort(objects, function(a, b) return a.Position.Z < b.Position.Z end) -- Sort by Z-axis for rows
    local grid = {}
    for row = 1, #objects / cols do
        local lowerIndex = 1 + (row - 1) * cols
        local upperIndex = row * cols
        local thisRow = {}
        table.move(objects, lowerIndex, upperIndex, 1, thisRow)
        table.sort(thisRow, function(a, b) return a.Position.X < b.Position.X end) -- Sort row by X-axis
        grid[row] = thisRow
    end
    return grid
end

-- Gerstner wave formula to create realistic wave displacement on the mesh
local function Gerstner(Position: Vector3, Wavelength: number, Direction: Vector2, Steepness: number, Gravity: number, Time: number)
    local k = TAU / Wavelength            -- Wave number, relates to wave length
    local a = Steepness / k               -- Wave amplitude based on steepness
    local d = Direction.Unit              -- Normalized direction vector for consistency
    local c = math.sqrt(Gravity / k)      -- Wave speed derived from gravity and wave number
    local f = k * d:Dot(Vector2.new(Position.X, Position.Z)) - c * Time
    local cosF = math.cos(f)

    -- Displacement vectors for wave movement in 3D space
    local dX = (d.X * (a * cosF))
    local dY = a * math.sin(f)
    local dZ = (d.Y * (a * cosF))
    return Vector3.new(dX, dY, dZ)
end

-- Combines default and custom settings to create a new settings table
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

-- Determines if a point lies within a triangle using barycentric coordinates, used to track wave height influence areas
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

-- Calculates direction for wave propagation based on settings or a reference point
local function GetDirection(Settings, WorldPos)
    local Direction = Settings.Direction
    local PushPoint = Settings.PushPoint

    if PushPoint then
        local PartPos = PushPoint:IsA("Attachment") and PushPoint.WorldPosition or PushPoint.Position
        if PartPos then
            Direction = (PartPos - WorldPos).Unit
            Direction = Vector2.new(Direction.X, Direction.Z)
        else
            warn("Invalid class for FollowPart, must be BasePart or Attachment")
            return
        end
    end
    return Direction
end

-- Creates a debug visualizer for wave tracking
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
		-- Convert position to 2D XZ plane and set up variables
		Position = XZVector3(Position)
		local Direction = Settings.Direction
		local PointF = ConvertToVector2(Position)
		local Triangle
		local Grid = self._bones_grid
		local Offset = Position - self._instance.Position
		
		-- Calculate row and column range in the bone grid
		local Row0, Row1 = GetRowRange(Offset)
		local Column0, Column1 = GetColumnRange(Offset)

		-- Return if row/column ranges are not defined
		if not Row0 or not Row1 or not Column0 or not Column1 then return end

		-- Retrieve grid-based bone information and define triangles for wave height calculations
		local bone1, bone2, bone3, bone4 = Grid[Row0][Column0], Grid[Row0][Column1], Grid[Row1][Column0], Grid[Row1][Column1]
		local triangles = {{bone1, bone2, bone3}, {bone2, bone3, bone4}}

		-- Convert triangle vertices to 2D vectors and determine if PointF lies within triangle 1 or triangle 2
		local PointA, PointB, PointC = ConvertToVector2(triangles[1][1].WorldPosition), ConvertToVector2(triangles[1][2].WorldPosition), ConvertToVector2(triangles[1][3].WorldPosition)
		Triangle = isPointInTriangle(PointF, PointA, PointB, PointC) and triangles[1] or triangles[2]

		-- Project the position onto the plane formed by the triangle and return the result
		local r1 = ProjectToPlane(Position, Triangle[1].TransformedWorldCFrame.Position, Triangle[2].TransformedWorldCFrame.Position, Triangle[3].TransformedWorldCFrame.Position)
		return r1
	end)

	-- Fallback: If the first attempt fails, calculate an approximate height using Gerstner wave sampling
	if sc then return rt else
		local XMin, XMax, ZMin, ZMax = GetXPlacement(Position), GetZPlacement(Position)
		local X, Z = XMax * DistanceBetweenBones, ZMax * DistanceBetweenBones
		local NewPosition = Vector3.new(X, 0, Z)
		
		-- Compute offset and retrieve rows/columns for bone grid adjustment
		local Offset = Position - NewPosition
		local Row0, Row1, Column0, Column1 = GetRowRange(Offset), GetColumnRange(Offset)
		local PointF, Triangle = ConvertToVector2(Position)

		-- Calculate bones based on grid offset and distance between bones
		local bone1 = Vector3.new((Column0 - OffsetCount) * DistanceBetweenBones, 0, (Row0 - OffsetCount) * DistanceBetweenBones) + NewPosition
		local bone2 = Vector3.new((Column0 - OffsetCount) * DistanceBetweenBones, 0, (Row1 - OffsetCount) * DistanceBetweenBones) + NewPosition
		local bone3 = Vector3.new((Column1 - OffsetCount) * DistanceBetweenBones, 0, (Row0 - OffsetCount) * DistanceBetweenBones) + NewPosition
		local bone4 = Vector3.new((Column1 - OffsetCount) * DistanceBetweenBones, 0, (Row1 - OffsetCount) * DistanceBetweenBones) + NewPosition
		local triangles = {{bone1, bone2, bone3}, {bone2, bone3, bone4}}
		
		-- Determine the triangle that contains PointF and calculate Gerstner wave transformations
		local PointA, PointB, PointC = ConvertToVector2(bone1), ConvertToVector2(bone2), ConvertToVector2(bone3)
		Triangle = isPointInTriangle(PointF, PointA, PointB, PointC) and triangles[1] or triangles[2]

		-- Apply Gerstner wave transformations for each point in the triangle
		local _time = (DateTime.now().UnixTimestampMillis / 1000) / Settings.TimeModifier
		local Transform1 = Gerstner(Triangle[1], Settings.WaveLength, Settings.Direction, Settings.Steepness, Settings.Gravity, _time) + Vector3.new(0, SeaData.SeaLevel, 0) + Triangle[1]
		local Transform2 = Gerstner(Triangle[2], Settings.WaveLength, Settings.Direction, Settings.Steepness, Settings.Gravity, _time) + Vector3.new(0, SeaData.SeaLevel, 0) + Triangle[2]
		local Transform3 = Gerstner(Triangle[3], Settings.WaveLength, Settings.Direction, Settings.Steepness, Settings.Gravity, _time) + Vector3.new(0, SeaData.SeaLevel, 0) + Triangle[3]

		-- Project the position onto the transformed plane and return the height result
		local r1 = ProjectToPlane(Position, Transform1, Transform2, Transform3)
		return r1
	end
end

-- Initializes a new Wave object with given instance, settings, and bones (wave control points)
function Wave.new(instance: instance, waveSettings: table | nil, bones: table | nil)
	-- Sets up bones and grid representation for wave mechanics; if no bones are provided, retrieve them from instance
	if not bones then
		bones = {}
		for _, v in pairs(instance:GetDescendants()) do
			if v:IsA("Bone") then table.insert(bones, v) end
		end
	end

	-- Create grid for bones and define triangles for wave calculations
	local Time, triangles, boneGrids = os.time(), {}, Gridify(bones, 22)
	for i, row in pairs(boneGrids) do
		local nextRow = boneGrids[i + 1]
		if not nextRow then continue end
		for i1, bone in pairs(row) do
			local nextBone = row[i1 + 1]
			if not nextBone then continue end

			-- Create triangles for wave height calculation
			local corner1, corner2, corner3, corner4 = row[i1], row[i1 + 1], boneGrids[i + 1][i1], boneGrids[i + 1][i1 + 1]
			if corner1 and corner2 and corner3 and corner4 then
				table.insert(triangles, {corner1, corner3, corner4})
				table.insert(triangles, {corner2, corner1, corner4})
			end
		end
	end

	-- Return new Wave instance
	return setmetatable({
		_instance = instance,
		_bones = bones,
		_time = 0,
		_connections = {},
		_noise = {},
		_bones_grid = boneGrids,
		_triangles = triangles,
		_settings = CreateSettings(waveSettings)
	}, Wave)
end

-- Periodically updates wave bones based on time and Gerstner wave transformations
function Wave:Update()
	for _, v in pairs(self._bones) do
		-- Determine wave direction, applying Perlin noise if no specific direction is set in settings
		local WorldPos, Settings, Direction = v.WorldPosition, self._settings, Settings.Direction
		if Direction == EmptyVector2 then
			local Noise = self._noise[v]
			local NoiseX, NoiseZ = Noise and Noise.X or math_noise(WorldPos.X / 3, WorldPos.Z / 3, 1), Noise and Noise.Z or math_noise(WorldPos.X / 3, WorldPos.Z / 3, 0)
			self._noise[v] = self._noise[v] or {X = NoiseX, Z = NoiseZ}
			Direction = Vector2.new(NoiseX, NoiseZ)
		else
			Direction = GetDirection(Settings, WorldPos)
		end

		-- Apply Gerstner wave transform and update bone position
		v.Transform = newCFrame(Gerstner(WorldPos, Settings.WaveLength, Direction, Settings.Steepness, Settings.Gravity, self._time))
	end
end

-- Resets all bone transformations
function Wave:Refresh()
	for _, v in pairs(self._bones) do
		v.Transform = IdentityCFrame
	end
end

-- Updates wave settings
function Wave:UpdateSettings(waveSettings)
	self._settings = CreateSettings(waveSettings, self._settings)
end

-- Connects wave update to the rendering loop to maintain smooth updates based on player distance
function Wave:ConnectRenderStepped()
	local Connection = Stepped:Connect(function()
		if not game:IsLoaded() then return end
		local Character, Settings = Player.Character, self._settings
		pcall(function()
			local InBoundsRange = (Character.PrimaryPart.Position - self._instance.Position).Magnitude < Settings.MaxDistance or 
								  (workspace.CurrentCamera.CFrame.Position - self._instance.Position).Magnitude < Settings.MaxDistance
			self._time = InBoundsRange and (DateTime.now().UnixTimestampMillis / 1000) / Settings.TimeModifier or self:Refresh()
		end)
	end)
	table.insert(self._connections, Connection)
	return Connection
end

-- Disconnects and clears wave data, making it unusable
function Wave:Destroy()
	self._instance, self._bones, self._settings, self = nil, {}, {}, nil
	for _, v in pairs(self._connections) do pcall(function() v:Disconnect() end) end
end

return Wave
