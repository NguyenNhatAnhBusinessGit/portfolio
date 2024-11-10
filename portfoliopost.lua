--|| Hello, once again, this is for my portfolio, I'm OriChanRBLX, discord is gaaaaaaaaaa! This script is the Registry module, which is used as a part of my existing combat system ||--
--|| Purposes: This serves as a damage manager script, as Registry:Hit() can be used to damage a player gping through alot of procedures such as Block Checking, Damage Invunerable, Rig Availablity, ... ||--

--|| The first few lines are for variables, which are for easy access and usage in the script later below ||--

--||Services||--
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Debris = game:GetService("Debris")

--|| Directories ||--
local Remotes = ReplicatedStorage.Remotes

local COMBAT = ReplicatedStorage.Remotes.COMBAT
local MODULES = ReplicatedStorage.MODULES
local STATE = require(MODULES.Shared.STATE)
local DATA = require(ServerScriptService.COMBAT.Preset.DATA)
local PLAYERDATA = require(ServerScriptService.COMBAT.Preset.PLAYER)
local AnimationManager = require(MODULES.Utility.AnimationManager)

local ServerStorage = game:GetService("ServerStorage")
local VFX = require(ServerStorage.EncryptedModules.VFXManager)

local SpeedManager = require(MODULES.Shared.Speed)

local Initiate = ReplicatedStorage.Remotes.Visual.Initiate

--||We define the module, as wrapping a self named "Registry" and return it by the end of the script. This "self" will store all the functions we can pass on when requiring. ||--
local Registry = {}
Registry.Burn = {}

--||Burn is a special table which will store data for Registry:Burn() function below||--

local function Damage(Victim, Damage, Data, Callback)
	--|| We will do several check to ensure the passed character can receive damage ||--
	--|| First check if the passed character is defined, not nil. Then, we will find the Victim's Humanoid and their HumanoidRootPart ||--

	--|| More checks are managed, as if they have Forcefield protection, if they are knocked (In my game, they need to be gripped to die, or else they will ragdoll til recovery and this is called the Knocked state), check if they are in Live folder for valid parent ||--
	--|| STATE:LOADPRESET() is a special function, since Victim who are registered by this module will store all their state like (UsingAbiliities, Running,...), LOADPRESET() will together check if all these state are in valid condition, return true if all are valid ||--
	
	if not Victim then return end 
	
	local VHumanoid: Humanoid, VRoot = Victim:FindFirstChild("Humanoid"), Victim:FindFirstChild("HumanoidRootPart")
	
	if (Victim:FindFirstChild("Forcefield")) then return end
	if (VHumanoid.Parent:FindFirstChild("Knocked")) then return end
	if (VHumanoid.Parent.Parent ~= workspace.World.Live) then return end
	if not STATE:LOADPRESET(Victim, "Damagable") then return end

	--|| After all checks, the character will be damaged by Humanoid:TakeDamage() function ||--
	
	VHumanoid:TakeDamage(Damage)
	
	if not Data.DisableIndicator then
		--|| Data is a box of information, if DisableIndicator is not enabled, then DamageIndication is requested to be replicated through :FireAllClients() with data ||--
		Initiate:FireAllClients({Module = "Universal",Function = "DamageIndication",Information = {Victim = Victim, Damage = Damage}})
	end
	
	if Data.Player then
		--|| If Player is passed through, HitRegister will serve to replicate the total damage display on the client for the person who cause the damage ||--
		ReplicatedStorage.Remotes.Replicator.HitRegister:FireClient(Data.Player, Damage)
	end

	--|| If the damage is not indirect, destroy the running state || --
	if not Data.Indirect then
		if Victim:FindFirstChild("Running") then
			pcall(function()
				Victim:FindFirstChild("Running"):Destroy()
			end)
		end
	end

	--|| If Victim is an AI, catch it's attention || --
	if Victim:FindFirstChild("AISignal") then
		Victim.AISignal:Fire({Name = "Attention", Subject = Data.Player})
	end

	--|| If the damage can cause instant grip, check if the damage can take user health to below or equal zero, if it does, grip them || --
	if Data.InstantGrip then
		print('yes instant grip')
		if VHumanoid.Health - Damage <= 0 then
			print('death')
			pcall(function()
				Victim.Parent = workspace
			end);

			if Players:GetPlayerFromCharacter(Victim) then
				Remotes.OnDeath:Fire(Players:GetPlayerFromCharacter(Victim))
			end;

			VFX:CastAll("Universal", "OnDeath", {Rig = Victim})
		end
	end

	--|| Run the callback on damage succeeded, this can be a function which do knockback, or whatsoever. || --
	--|| Wrapped in pcall() so if Callback is not passed, or Callback cause an error, the code below can still run || --
	pcall(function()
		Callback()
	end)

	--|| Cancel Gripping or Carrying State on damage, first to check if there are events for them, if it does, fire it and pass a value "Execute" which indicate cancelation. || --
	if (Victim:FindFirstChild("Gripping")) then
		local GripEvent = Victim:FindFirstChild("Gripping")
		if not GripEvent:IsA("BindableFunction") then return end

		local Type, Entity = GripEvent:Invoke("Return"); if Type ~= "Attacker" then return end

		GripEvent:Invoke("Execute")
	end
	if (Victim:FindFirstChild("Carrying")) then
		local GripEvent = Victim:FindFirstChild("Carrying")
		if not GripEvent:IsA("BindableFunction") then return end

		local Type, Entity = GripEvent:Invoke("Return"); if Type ~= "Attacker" then return end

		GripEvent:Invoke("Execute")
	end
end

--|| ThirdPartyDamage instantly call Damage() function, not expecting any Blocking or Parry check. || --
function Registry:ThirdPartyDamage(Victim, Data: {Damage: number, InstantGrip: boolean, DisableIndicator: boolean})
	Damage(Victim, Data.Damage, Data)
end

--|| Registry:ApplyBurn() is wrapped in a spawn() so the wait loop won't yield the script calling. || --
function Registry:ApplyBurn(Victim, Data)
	--|| Version is served to prevent burn stacking, proper ID will be passed to control the current burn version, so newer will be prioritized and old burn called will be cancelled || --
	spawn(function()
		local Interval = Data.Interval
		local Duration = Data.Duration
		local ID = Data.ID

		local V_ersion = 0

		if ID then
			if Registry.Burn[ID] then
				Registry.Burn[ID] += 1
				V_ersion = Registry.Burn[ID]
			else
				Registry.Burn[ID] = 0
				V_ersion = Registry.Burn[ID]
			end
		end

		task.wait()

		--|| I could have used for loop with time distribution but this is my old code so.., I used them in newer version! || --
		local StartTime = tick()
		while true do
			if tick() - StartTime > Duration then break end

			if ID then
				if Registry.Burn[ID] then
					if Registry.Burn[ID] ~= V_ersion then break end
				end
			end

			Damage(Victim, Data.Damage, Data, nil)

			wait(Interval)
		end
	end)
end 

--|| Create a Parry event, the Parry event will be checked when going through Registry:Hit() || --
function Registry:CreateParry(Character, Duration)
	local Parry = Instance.new("BindableEvent")
	Parry.Name = "Parry"
	Parry.Parent = Character
	Debris:AddItem(Parry, Duration)
	--|| Debris usage || --

	--|| On event, the parry will be destroyed, as well as providing 0.2 seconds of IFrame to both characters|| --
	Parry.Event:Connect(function(Victim)
		if not Victim:FindFirstChild("Parry") then return end
		Parry:Destroy()
		Victim.Parry:Destroy()
		
		--AnimationManager.Play(Character, ReplicatedStorage.Animations.Motion.ParryFists, true)
		--AnimationManager.Play(Victim, ReplicatedStorage.Animations.Motion.ParryFists, true)
		
		STATE:SET("IFrame", 0.2, Character)
		STATE:SET("IFrame", 0.2, Victim)
	end)
end

--|| Most used, fundamental function of the script, Registry:Hit() is a primary way to call a damage casting on a registered character || --
function Registry:Hit(Character, Victim, Data, Callback)
	--|| Check if Character, Victim, Data table are passed correctly || --
	if not Character then return end
	if not Victim then return end
	if not Data then return end

	--|| Check if Data.Damage is defined since its essential, as well as a check that ensure both are not in Safe Zone || --
	if not Data.Damage then warn("Damage field is required!") return end
	if Victim:FindFirstChild("Safe Zone") or Character:FindFirstChild("Safe Zone") then return end

	--|| Find essential parts of both characters, such as Humanoid and HumanoidRootPart. If they don't exzsts, cancel the function call || --
	local Humanoid, HumanoidRootPart = Character:FindFirstChild("Humanoid"), Character:FindFirstChild("HumanoidRootPart")
	local VHumanoid, VRoot = Victim:FindFirstChild("Humanoid"), Victim:FindFirstChild("HumanoidRootPart")
	if not Humanoid then return end
	if not HumanoidRootPart then return end
	if not VHumanoid then return end
	if not VRoot then return end

	--|| Set Data.Player to Player if they exists, so it will pass through Hit() afterward, we have discussed the functionality of this earlier || --
	local Player = game.Players:GetPlayerFromCharacter(Character)
	Data.Player = Player

	--|| If victim has Perfect Block and both characters is facing, cast a perfect block stun on character who making attack.|| --
	if Victim:FindFirstChild("Perfect Block") and not (VRoot.CFrame.LookVector:Dot((HumanoidRootPart.Position - VRoot.Position).Unit) < 0) then
		--|| Set the speed of humanoid so they cant move, as well as set stun state so they cant do anything. PB animation is managed by AnimationManagerService, and PB VFX is casted to replicate at position forward victim || --
			
		SpeedManager.Set(Character, 0, 1.75, 10)
		STATE:SET("Stun", 1.75, Character)
		AnimationManager.Play(Character, ReplicatedStorage.Animations.Motion.PerfectBlock, true)
		
		VFX:CastAll("Universal", "Perfect Block", {Position = (VRoot.CFrame * CFrame.new(0, 0, -2)).p})
		
	elseif Victim:FindFirstChild("Blocking") then
		--|| If victim is blocking, first check if they are facing, if they are not facing, then damage because its a indirect hit. Else, check if the block ran out, if it does, cast block break and damage, else, just subtract one block || --
		--|| VFX Cast are followed by such as BlockHit, Guardbreak VFX replicated on client || --
		if VRoot.CFrame.LookVector:Dot((HumanoidRootPart.Position - VRoot.Position).Unit) < 0 then
			Data.Root = HumanoidRootPart
			Damage(Victim, Data.Damage, Data, Callback)
		else
			local Block = Victim:FindFirstChild("Blocking")
			if Block.Value - 1 < 1 or Data.BreakBlock then
				pcall(function()
					Block:Destroy()
				end)
				
				SpeedManager.Set(Victim, 0, 2.33, 10)
				AnimationManager.Play(Victim, ReplicatedStorage.Animations.Motion.Guardbreak, true)
				STATE:SET("Stun", 2.33, Victim)
				
				VFX:CastAll("Universal", "Guardbreak", {Position = (VRoot.CFrame * CFrame.new(0, 0, -2)).p})
				
				Data.Root = HumanoidRootPart
				Damage(Victim, Data.Damage, Data, Callback)
			else
				AnimationManager.Play(Victim, ReplicatedStorage.Animations.Motion.BlockHit, true)
				
				VFX:CastAll("Universal", "BlockHit", {Position = (VRoot.CFrame * CFrame.new(0, 0, -2)).p})
				
				Block.Value = Block.Value - 1
			end
		end
	else
		Data.Root = HumanoidRootPart
		Damage(Victim, Data.Damage, Data, Callback)
	end
end

return Registry
