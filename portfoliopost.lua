----- Hello, this is for my portfolio!
----- Script info: This is a LocalScript located in StarterGui, which serves for rendering all "StatisticBoard" of LocalPlayer, which display sufficient infos that are synced with the Server by Instance Value Replication method!

----- Load services.
local CollectionService = game:GetService("CollectionService"); ----- CollectionService allow us to ultilize tags, which is a great way to gather all instances by just a GetTagged() function!
local PlayerService = game:GetService("Players"); ----- PlayerService, will be used to get LocalPlayer.
local LocalPlayer = PlayerService.LocalPlayer; ----- Yes, client itself.

local ProfileLoaded = LocalPlayer:WaitForChild("ProfileLoaded", 100); ----- WaitForChild() allow us to yield until the instance is created by Server, ProfileLoaded is an instance that indicates LocalPlayer's data are fully replicated, max duration of yield is set to 100 seconds.
local VisibleData = LocalPlayer:FindFirstChild("VisibleData", 100); ----- same usage of WaitForChild, but VisibleData is a folder where it stores all player's data.
local ArenaHistory = VisibleData:FindFirstChild("ArenaHistory", 100); ----- ArenaHistory is a folder where it stores all arena data. Continous WaitForChild() allow proper variable loading.

local userId = LocalPlayer.UserId ----- get UserId for profile image.
local thumbType = Enum.ThumbnailType.HeadShot ----- Enum variable
local thumbSize = Enum.ThumbnailSize.Size420x420 ----- Enum variable
local content, isReady = PlayerService:GetUserThumbnailAsync(userId, thumbType, thumbSize)  ----- get Image for player profile pic.

local GetFullPlayerName = function(LocalPlayer: Player) ----- get full name function
	return LocalPlayer.DisplayName.." (@"..LocalPlayer.Name..")" ----- example: TheValkyrie (@OriChanRBLX)
end ----- end

for _, StatisticBoard: Instance in pairs(CollectionService:GetTagged("StatisticBoard")) do ----- loop through all instances that is StatisticBoard
	print(StatisticBoard) ----- Debug purposes
	local sc, er = pcall(function() ----- pcall allow the loop still run if the code inside error, we catch error block to indicate the error.
		local DataName: string = StatisticBoard.DataName.Value; ----- get the data name value that the statistic board serves (Solo, Double...) data.
		local DataFolder: Folder = ArenaHistory:FindFirstChild(DataName); ----- find the data folder of that statistic name. (data from Solo matches, or Double matches,...)
		
		local SurfaceFrame = StatisticBoard.SurfaceGui.Frame ----- define variable for easy access
		SurfaceFrame.HRankedData.AIcon.Image = content; ----- change the image to user profile image
		SurfaceFrame.HRankedData.BData.AName.Text = GetFullPlayerName(LocalPlayer); ----- change the text to user name with the format DisplayName (@Name)
		
		local UpdateValues = function() ----- define UpdateValues function to not have to repeat the code inside the block multiple times, also faster editing since u just have to edit the function.
			local sc1, er1 = pcall(function() ----- another pcall, since update values can error so we add it one more time so it doesnt break the code, retry on another event call.
				SurfaceFrame.BType.Text = "Currently showing data from "..DataName; ----- change to the data name for display purposes.
				SurfaceFrame.CAmountMatches.Text = "Total Matches: "..DataFolder.Matches.Value ----- change to the text label CAmountMatches to the synced data from DataFolder.
				SurfaceFrame.DTotalWins.Text = "Total Wins: "..DataFolder.Win.Value ----- change to the text label DTotalWins to the synced data from DataFolder.
				
				local WLRating = (DataFolder.Win.Value / math.clamp(DataFolder.Matches.Value - DataFolder.Win.Value, 1, math.huge)); ----- Win Loss rating, DataFolder.Win.Value is divided to Loss rate.
				-- Loss rate is calculated by total match - total win, math.clamp to limit it not going below 1. If it gets 0, nan will be returned which breaks the display.
						
				WLRating = math.floor(WLRating * 100) / 100 -- this is for number simplication. for ex: 3.12391839 when multiply 100 will return  312.391839, math floor will return 312. then divide 100 to return 3.12 (simplified)
				
				SurfaceFrame.EWL.Text = "W/L Rating: "..WLRating; -- set the textlabel text to calculated rating
				SurfaceFrame.HRankedData.BData.RankedRating.Text = "RANKED RATING: "..DataFolder.Rating.Value -- set the textlabel text to ranked rating (custom data)
			end)
			
			if er1 then -- if pcall found error, warn that error for debug purposes
				warn("Board error: ", er1) -- warn.
			end
		end;
		
		UpdateValues(); -- one call  of updatevalues to do first updatte, this is because the code below is linked to .Changed. If a single value dont change, the board will remain in original state. thats why we need to call it to do first update.
		for _, Data: IntValue in DataFolder:GetChildren() do -- loop through all value instances in linked datafolder
			pcall(function() -- pcall so if Data is not a Value Instance, dont have .Changed event then it wont break the loop.
				Data.Changed:Connect(UpdateValues) -- get the change signal, if it change, update the board display by calling the functiuon again.
			end)
		end
	end)
	
	if er then -- if pcall found error, warn that error for debug purposes
		warn(er) -- warn.
	end
end
