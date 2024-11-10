local CollectionService = game:GetService("CollectionService");
local PlayerService = game:GetService("Players");
local LocalPlayer = PlayerService.LocalPlayer;

local ProfileLoaded = LocalPlayer:WaitForChild("ProfileLoaded", 100);
local VisibleData = LocalPlayer:FindFirstChild("VisibleData", 100);
local ArenaHistory = VisibleData:FindFirstChild("ArenaHistory", 100);

local userId = LocalPlayer.UserId
local thumbType = Enum.ThumbnailType.HeadShot
local thumbSize = Enum.ThumbnailSize.Size420x420
local content, isReady = PlayerService:GetUserThumbnailAsync(userId, thumbType, thumbSize)

local GetFullPlayerName = function(LocalPlayer: Player)
	return LocalPlayer.DisplayName.." (@"..LocalPlayer.Name..")"
end

for _, StatisticBoard: Instance in pairs(CollectionService:GetTagged("StatisticBoard")) do
	print(StatisticBoard)
	local sc, er = pcall(function()
		local DataName: string = StatisticBoard.DataName.Value;
		local DataFolder: Folder = ArenaHistory:FindFirstChild(DataName);
		
		local SurfaceFrame = StatisticBoard.SurfaceGui.Frame
		SurfaceFrame.HRankedData.AIcon.Image = content;
		SurfaceFrame.HRankedData.BData.AName.Text = GetFullPlayerName(LocalPlayer);
		
		local UpdateValues = function()
			local sc1, er1 = pcall(function()
				SurfaceFrame.BType.Text = "Currently showing data from "..DataName;
				SurfaceFrame.CAmountMatches.Text = "Total Matches: "..DataFolder.Matches.Value
				SurfaceFrame.DTotalWins.Text = "Total Wins: "..DataFolder.Win.Value
				
				local WLRating = (DataFolder.Win.Value / math.clamp(DataFolder.Matches.Value - DataFolder.Win.Value, 1, math.huge));
				WLRating = math.floor(WLRating * 100) / 100
				
				SurfaceFrame.EWL.Text = "W/L Rating: "..WLRating;
				SurfaceFrame.HRankedData.BData.RankedRating.Text = "RANKED RATING: "..DataFolder.Rating.Value
			end)
			
			if er1 then
				warn("Board error: ", er1)
			end
		end;
		
		UpdateValues();
		for _, Data: IntValue in DataFolder:GetChildren() do
			pcall(function()
				Data.Changed:Connect(UpdateValues)
			end)
		end
	end)
	
	if er then
		warn(er)
	end
end
