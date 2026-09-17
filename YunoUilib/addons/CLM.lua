--[[

    ____          _                     _                
  / ___|   _ ___| |_ ___  _ __ ___    | |   _   _  __ _ 
 | |  | | | / __| __/ _ \| '_ ` _ \   | |  | | | |/ _` |
 | |__| |_| \__ \ || (_) | | | | | |  | |__| |_| | (_| |
  \____\__,_|___/\__\___/|_| |_| |_|  |_____\__,_|\__,_| b0.1
                                                        
    By xyznick

    CAUTION!!

    Custom Lua is still in BETA, meaning some features might not work
    Report bugs to my discord: @xyzznick 

    author is shown

]]

--[[

    Load Custom Lua (only works on UELinoriaLib for now (i think because i havent even tested this idek if this works)):
        
        local CLM = loadstring(game:HttpGet(".../CLuaManager.lua"))()
		CLM:SetLibrary(Library)
		CLM:SetWindow(Window)

    Add a new tab

    	local Tab = CLM:AddTab("My Tab")
		local Groupbox = Tab:AddLeftGroupbox("Stuff")
		Groupbox:AddButton("Click me", function() end)

    Register a feature, this makes a new groupbox with a name/description/author

    	CLM:RegisterScript({
			Name = "Speedhack",
			Author = "xyznick",
			Description = "Doubles walkspeed",
			Tab = "Movement", -- created automatically if tab doesnt exist
			Callback = function(self, Library, Window, Tab, Groupbox)
				self.OldSpeed = game.Players.LocalPlayer.Character.Humanoid.WalkSpeed
				game.Players.LocalPlayer.Character.Humanoid.WalkSpeed = self.OldSpeed * 2
			end,
			Cleanup = function(self)
				game.Players.LocalPlayer.Character.Humanoid.WalkSpeed = self.OldSpeed
			end,
		})
    
    And much more! (2 lazy to make more examples)

    Also create the manager tab:
    
        CLM:CreateManagerTab("Script Manager")

]]

local CustomLuaManager = {} do
	CustomLuaManager.Library = nil
	CustomLuaManager.Window = nil

	CustomLuaManager.Tabs = {}
	CustomLuaManager.Scripts = {}
	CustomLuaManager.Order = {}

	function CustomLuaManager:SetLibrary(lib)
		self.Library = lib
	end

	function CustomLuaManager:SetWindow(window)
		self.Window = window
	end

	function CustomLuaManager:AddTab(Name, Config)
		assert(self.Window, 'CustomLuaManager: call SetWindow(Window) first.')
		assert(type(Name) == 'string' and #Name > 0, 'CustomLuaManager:AddTab: `Name` must be a non-empty string.')

		if self.Tabs[Name] then
			return self.Tabs[Name]
		end

		local Tab = self.Window:AddTab(Name)
		self.Tabs[Name] = Tab

		Config = Config or {}
		if Config.Groupboxes == 'double' or Config.Groupboxes == 2 then
			Tab.Left = Tab:AddLeftGroupbox(Config.LeftName or 'Main')
			Tab.Right = Tab:AddRightGroupbox(Config.RightName or 'Extra')
		end

		return Tab
	end

	function CustomLuaManager:GetTab(Name)
		return self.Tabs[Name]
	end

	function CustomLuaManager:RemoveTab(Name)
		local Tab = self.Tabs[Name]
		if not Tab then return end

		if Tab.HideTab then
			Tab:HideTab()
		end

		self.Tabs[Name] = nil
	end

--[[

    Scripts 

    Info = {
    Name        = string, required, if you register the same name, it unregisters the old one and cleans up the previous one
    
    Author      = string, optional, shown under desc
    Description = string, optional, shown under the script name
    Tab         = string, which tab to make the ui in, default "Scripts", creates one automatically if it doesnt exist yet
    Side        = 'Left', 'Right', which side of the tab, default "Left"
    Toggleable  = bool, adds an Enabled toggle
    Default     = bool, whether the toggle starts enabled, default true
    Callback    = function(self, Library, Window, Tab, Groupbox) ... end
                  'self' is this scripts own table, good for stashing state (e.g. self.Connection = ...) that cleanup needs
    Cleanup     = function(self) ... end
                  called when the toggle is off, or the script is unregistered while enabled

    }

]]

	function CustomLuaManager:RegisterScript(Info)
		assert(self.Library, 'CustomLuaManager: call SetLibrary(Library) first.')
		assert(type(Info) == 'table', 'CustomLuaManager:RegisterScript expects a table.')
		assert(type(Info.Name) == 'string' and #Info.Name > 0, 'CustomLuaManager:RegisterScript: `Name` is required.')
		assert(type(Info.Callback) == 'function', 'CustomLuaManager:RegisterScript: `Callback` is required.')

		if self.Scripts[Info.Name] then
			self:Unregister(Info.Name)
		end

		local Library = self.Library
		local Window = self.Window

		local Script = {
			Name = Info.Name,
			Author = Info.Author,
			Description = Info.Description,
			Callback = Info.Callback,
			Cleanup = Info.Cleanup,
			Toggleable = Info.Toggleable ~= false,
			Enabled = false,
			HasRun = false,
			Idx = 'CLuaManager_' .. Info.Name,
		}

		local Tab = self:AddTab(Info.Tab or 'Scripts')
		local Groupbox = (Info.Side == 'Right') and Tab:AddRightGroupbox(Info.Name) or Tab:AddLeftGroupbox(Info.Name)

		Script.Tab = Tab
		Script.Groupbox = Groupbox

		if Info.Description then
			Groupbox:AddGrayText(Info.Description, { DoesWrap = true })
		end
		if Info.Author then
			Groupbox:AddGrayText('by ' .. Info.Author)
		end

		local function RunCallback()
			local Ok, Err = pcall(Info.Callback, Script, Library, Window, Tab, Groupbox)
			if not Ok then
				Library:Notify(('[%s] error: %s'):format(Info.Name, tostring(Err)), 5)
			end
			Script.HasRun = true
		end

		local function RunCleanup()
			if Info.Cleanup then
				pcall(Info.Cleanup, Script)
			end
		end

		if Script.Toggleable then
			Groupbox:AddToggle(Script.Idx, {
				Text = 'Enabled',
				Default = Info.Default ~= false,
			}):OnChanged(function(Value)
				Script.Enabled = Value
				if Value then
					RunCallback()
				elseif Script.HasRun then
					RunCleanup()
				end
			end)
		else
			Script.Enabled = true
			RunCallback()
		end

		self.Scripts[Info.Name] = Script
		table.insert(self.Order, Info.Name)

		return Script
	end

	function CustomLuaManager:Unregister(Name)
		local Script = self.Scripts[Name]
		if not Script then return end

		if Script.Enabled and Script.Cleanup then
			pcall(Script.Cleanup, Script)
		end

		if Script.Groupbox and Script.Groupbox.Container then
			local BoxOuter = Script.Groupbox.Container.Parent.Parent
			if BoxOuter then
				BoxOuter:Destroy()
			end
		end

		self.Scripts[Name] = nil
		for Idx, ExistingName in next, self.Order do
			if ExistingName == Name then
				table.remove(self.Order, Idx)
				break
			end
		end
	end

	function CustomLuaManager:GetScript(Name)
		return self.Scripts[Name]
	end
--[[

    Loading lua source as script

    compiles 'source' and runs it, passing (library, window, clm) as its arguments so the loaded code can build its own tabs/groupboxes
    or call CLM:RegisterScript, returns whatever the chunk returns
    or nil + an error string if compiling failed

]]

	function CustomLuaManager:LoadScript(Source)
		assert(type(Source) == 'string', 'CLM:LoadScript expects a string of Lua')

		local Chunk, CompileErr = loadstring(Source)
		if not Chunk then
			if self.Library then
				self.Library:Notify('CLM: failed to compile script - ' .. tostring(CompileErr), 5)
			end
			return nil, CompileErr
		end

		local Ok, ResultOrErr = pcall(Chunk, self.Library, self.Window, self)
		if not Ok then
			if self.Library then
				self.Library:Notify('CLM: script errored - ' .. tostring(ResultOrErr), 5)
			end
			return nil, ResultOrErr
		end

		return ResultOrErr
	end

-- manager ui (i am not making more comments)
	function CustomLuaManager:CreateManagerTab(TabName)
		local Tab = self:AddTab(TabName or 'script manager')
		local Groupbox = Tab:AddLeftGroupbox('scripts')

		if #self.Order == 0 then
			Groupbox:AddGrayText('no scripts yet', { Center = true })
			return Tab, Groupbox
		end

		for _, Name in next, self.Order do
			local Script = self.Scripts[Name]

			Groupbox:AddLabel(Script.Name)
			if Script.Description then
				Groupbox:AddGrayText(Script.Description, { DoesWrap = true })
			end

			Groupbox:AddButton('unregister', function()
				self:Unregister(Name)
				self.Library:Notify(('unregistered %q'):format(Name), 3)
			end)
			Groupbox:AddDivider()
		end

		return Tab, Groupbox
	end
end

return CustomLuaManager

