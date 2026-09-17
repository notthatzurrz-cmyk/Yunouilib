local httpService = game:GetService('HttpService')

local SaveManager = {} do
	SaveManager.Folder = 'LinoriaLibSettings'
	SaveManager.Ignore = {}
	SaveManager.Parser = {
		Toggle = {
			Save = function(idx, object) 
				return { type = 'Toggle', idx = idx, value = object.Value } 
			end,
			Load = function(idx, data)
				if Toggles[idx] then 
					Toggles[idx]:SetValue(data.value)
				end
			end,
		},
		Slider = {
			Save = function(idx, object)
				return { type = 'Slider', idx = idx, value = tostring(object.Value) }
			end,
			Load = function(idx, data)
				if Options[idx] then 
					Options[idx]:SetValue(data.value)
				end
			end,
		},
		Dropdown = {
			Save = function(idx, object)
				return { type = 'Dropdown', idx = idx, value = object.Value, mutli = object.Multi }
			end,
			Load = function(idx, data)
				if Options[idx] then 
					Options[idx]:SetValue(data.value)
				end
			end,
		},
		ColorPicker = {
			Save = function(idx, object)
				return { type = 'ColorPicker', idx = idx, value = object.Value:ToHex(), transparency = object.Transparency }
			end,
			Load = function(idx, data)
				if Options[idx] then 
					Options[idx]:SetValueRGB(Color3.fromHex(data.value), Options[idx].HasTransparency and data.transparency or 0)
				end
			end,
		},
		KeyPicker = {
			Save = function(idx, object)
				return { type = 'KeyPicker', idx = idx, mode = object.Mode, key = object.Value }
			end,
			Load = function(idx, data)
				if Options[idx] then 
					Options[idx]:SetValue({ data.key, data.mode })
				end
			end,
		},

		Input = {
			Save = function(idx, object)
				return { type = 'Input', idx = idx, text = object.Value }
			end,
			Load = function(idx, data)
				if Options[idx] and type(data.text) == 'string' then
					Options[idx]:SetValue(data.text)
				end
			end,
		},
	}

	function SaveManager:SetIgnoreIndexes(list)
		for _, key in next, list do
			self.Ignore[key] = true
		end
	end

	function SaveManager:SetFolder(folder)
		self.Folder = folder;
		self:BuildFolderTree()
	end

	local function isOptionActiveForSave(saveMgr, opt, idx, toggles)
		if not opt then return false end
		if saveMgr.Ignore and saveMgr.Ignore[idx] then return false end

		-- If attached to a toggle addon, verify parent toggle is active
		if opt.Owner and type(opt.Owner) == 'table' and opt.Owner.Type == 'Toggle' then
		if opt.Owner.Value ~= true then
			return false
		end
		end

		-- If inside a dependency box, verify its Holder is visible
		if opt.Container and opt.Container.Parent and typeof(opt.Container.Parent) == 'Instance' and opt.Container.Parent:IsA('GuiObject') then
		if not opt.Container.Parent.Visible then
			return false
		end
		end

		-- If part of a section with a master toggle (e.g. P1S1T1), skip if master toggle is off
		local sec = tostring(idx):match('^(P%d+S%w+?)[SDCKI_]') or tostring(idx):match('^(P%d+S%d+)')
		if sec and toggles then
		local masterToggle = toggles[sec .. 'T1'] or toggles[sec .. '_T1']
		if masterToggle and type(masterToggle) == 'table' and masterToggle.Value == false then
			return false
		end
		end

		-- Skip unconfigured/blank options
		if opt.Type == 'KeyPicker' then
		if not opt.Value or opt.Value == 'None' or opt.Value == '' then
			return false
		end
		elseif opt.Type == 'Input' then
		if not opt.Value or opt.Value == '' then
			return false
		end
		elseif opt.Type == 'Dropdown' then
		if opt.Multi then
			local hasAny = false
			for _, v in pairs(opt.Value or {}) do
				if v then hasAny = true break end
			end
			if not hasAny then return false end
		else
			if not opt.Value or opt.Value == '' or opt.Value == 'None' then
				return false
			end
		end
		end

		return true
	end

	function SaveManager:Save(name)
		if (not name) then
		return false, 'no config file is selected'
		end

		local fullPath = self.Folder .. '/settings/' .. name .. '.json'
		local env = (type(getgenv) == 'function' and getgenv()) or _G
		local lib = self.Library or (type(env) == 'table' and env.Library)
		local toggles = (lib and lib.Toggles) or (type(env) == 'table' and env.Toggles) or Toggles or {}
		local options = (lib and lib.Options) or (type(env) == 'table' and env.Options) or Options or {}

		local data = {
		objects = {}
		}

		-- Only save toggles that are ENABLED (maps out ONLY active features)
		for idx, toggle in next, toggles do
		if self.Ignore[idx] then continue end
		if type(toggle) == 'table' and toggle.Value == true then
			if self.Parser[toggle.Type] and type(self.Parser[toggle.Type].Save) == 'function' then
				local ok, saved = pcall(self.Parser[toggle.Type].Save, idx, toggle)
				if ok and saved then
					table.insert(data.objects, saved)
				end
			end
		end
		end

		-- Only save options belonging to enabled features
		for idx, option in next, options do
		if not self.Parser[option.Type] then continue end
		if self.Ignore[idx] then continue end
		if not isOptionActiveForSave(self, option, idx, toggles) then continue end

		if self.Parser[option.Type] and type(self.Parser[option.Type].Save) == 'function' then
			local ok, saved = pcall(self.Parser[option.Type].Save, idx, option)
			if ok and saved then
				table.insert(data.objects, saved)
			end
		end
		end

		local success, encoded = pcall(httpService.JSONEncode, httpService, data)
		if not success then
		return false, 'failed to encode data'
		end

		writefile(fullPath, encoded)
		return true
	end

	local function ApplyConfigData(self, decoded)
		local objects = decoded and (decoded.objects or decoded)
		if type(objects) ~= 'table' then
		return false, 'invalid config format'
		end

		local env = (type(getgenv) == 'function' and getgenv()) or _G
		local lib = self.Library or (type(env) == 'table' and env.Library)
		local toggles = (lib and lib.Toggles) or (type(env) == 'table' and env.Toggles) or Toggles or {}
		local options = (lib and lib.Options) or (type(env) == 'table' and env.Options) or Options or {}
		local bridge = (type(env) == 'table' and env.RivalsRuntimeBridge) or (type(RivalsRuntimeBridge) == 'table' and RivalsRuntimeBridge)

		-- 1. Suspend layout and refresh callbacks so everything applies smoothly and instantly without lag or crashes
		if lib then
		lib.ConfigLoading = true
		if type(lib.SuspendLayout) == 'function' then
			pcall(lib.SuspendLayout, lib)
		end
		end
		if bridge then
		bridge.RuntimeRefreshSuspended = true
		end

		-- 2. Build quick lookup of items written in the config
		local writtenConfig = {}
		local optionsToLoad = {}
		local togglesToLoad = {}

		for _, item in ipairs(objects) do
		if type(item) == 'table' and item.idx and item.type then
			writtenConfig[item.idx] = item
			if item.type == 'Toggle' then
				table.insert(togglesToLoad, item)
			else
				table.insert(optionsToLoad, item)
			end
		end
		end

		-- 3. Reset any toggles that were previously true but are NOT written in this config
		for idx, toggle in pairs(toggles) do
		if not self.Ignore[idx] and type(toggle) == 'table' and toggle.Value == true and not writtenConfig[idx] then
			pcall(toggle.SetValue, toggle, false)
		end
		end

		-- 4. Apply Options first (so toggles that turn on immediately see configured values)
		for _, option in ipairs(optionsToLoad) do
		if self.Parser[option.type] and type(self.Parser[option.type].Load) == 'function' then
			pcall(self.Parser[option.type].Load, option.idx, option)
		end
		end

		-- 5. Apply Toggles (only set if value differs to prevent duplicate triggers)
		for _, option in ipairs(togglesToLoad) do
		local toggle = toggles[option.idx]
		if toggle and type(toggle) == 'table' then
			local targetVal = (not not option.value)
			if toggle.Value ~= targetVal then
				pcall(toggle.SetValue, toggle, targetVal)
			end
		end
		end

		-- 6. Single batch update of dependency boxes & UI
		if lib and type(lib.UpdateDependencyBoxes) == 'function' then
		pcall(lib.UpdateDependencyBoxes, lib)
		end

		-- 7. Resume layout and callbacks
		if bridge then
		bridge.RuntimeRefreshSuspended = false
		end
		if lib then
		lib.ConfigLoading = false
		if type(lib.ResumeLayout) == 'function' then
			pcall(lib.ResumeLayout, lib)
		end
		end

		return true
	end

	function SaveManager:Load(name)
		if (not name) then
		return false, 'no config file is selected'
		end

		local file = self.Folder .. '/settings/' .. name .. '.json'
		if not isfile(file) then
		local altFile = self.Folder .. '/' .. name .. '.json'
		if isfile(altFile) then
			file = altFile
		else
			return false, 'invalid file'
		end
		end

		local readOk, content = pcall(readfile, file)
		if not readOk or type(content) ~= 'string' then
		return false, 'read error'
		end

		local decodeOk, decoded = pcall(httpService.JSONDecode, httpService, content)
		if not decodeOk or type(decoded) ~= 'table' then
		return false, 'decode error'
		end

		return ApplyConfigData(self, decoded)
	end

	function SaveManager:LoadFromString(str)
		if not str or str:gsub(' ', '') == '' then
		return false, 'empty string'
		end

		local decodeOk, decoded = pcall(httpService.JSONDecode, httpService, str)
		if not decodeOk or type(decoded) ~= 'table' then
		return false, 'invalid config json'
		end

		return ApplyConfigData(self, decoded)
	end
function SaveManager:IgnoreThemeSettings()
		self:SetIgnoreIndexes({ 
			"BackgroundColor", "MainColor", "AccentColor", "OutlineColor", "FontColor", "RiskColor", -- themes
			"ThemeManager_ThemeList", 'ThemeManager_CustomThemeList', 'ThemeManager_CustomThemeName', -- themes
		})
	end

	function SaveManager:BuildFolderTree()
		local paths = {
			self.Folder,
			self.Folder .. '/themes',
			self.Folder .. '/settings'
		}

		for i = 1, #paths do
			local str = paths[i]
			if not isfolder(str) then
				makefolder(str)
			end
		end
	end

	function SaveManager:RefreshConfigList()
		local list = listfiles(self.Folder .. '/settings')

		local out = {}
		for i = 1, #list do
			local file = list[i]
			if file:sub(-5) == '.json' then
				-- i hate this but it has to be done ...

				local pos = file:find('.json', 1, true)
				local start = pos

				local char = file:sub(pos, pos)
				while char ~= '/' and char ~= '\\' and char ~= '' do
					pos = pos - 1
					char = file:sub(pos, pos)
				end

				if char == '/' or char == '\\' then
					table.insert(out, file:sub(pos + 1, start - 1))
				end
			end
		end
		
		return out
	end

	function SaveManager:SetLibrary(library)
		self.Library = library
	end

	function SaveManager:LoadAutoloadConfig()
		if isfile(self.Folder .. '/settings/autoload.txt') then
			local name = readfile(self.Folder .. '/settings/autoload.txt')

			local success, err = self:Load(name)
			if not success and not SILENT then
				return self.Library:Notify('failed to load autoload config: ' .. err)
			end
			if not SILENT then
				self.Library:Notify(string.format('auto loaded config %q', name))
			end
		end
	end


	function SaveManager:BuildConfigSection(tab)
		assert(self.Library, 'Must set SaveManager.Library')

		local section = tab:AddRightGroupbox('configuration')
		local lib = self.Library

		local function setRisk(btn, text)
			lib:RemoveFromRegistry(btn.Label)
			lib:AddToRegistry(btn.Label, { TextColor3 = 'RiskColor' })
			btn.Label.TextColor3 = lib.RiskColor or Color3.fromRGB(255, 50, 50)
			btn.Label.Text      = text
		end

		local function resetLabel(btn, text)
			lib:RemoveFromRegistry(btn.Label)
			lib:AddToRegistry(btn.Label, { TextColor3 = 'FontColor' })
			btn.Label.TextColor3 = lib.FontColor
			btn.Label.Text       = text
		end

		section:AddInput('SaveManager_ConfigName',    { Text = 'config name' })
		section:AddDropdown('SaveManager_ConfigList', { Text = 'config list', Values = self:RefreshConfigList(), AllowNull = true })

		section:AddDivider()


		section:AddButton('create config', function()
			local name = Options.SaveManager_ConfigName.Value
			if name:gsub(' ', '') == '' then
				return lib:Notify('invalid config name (empty)', 2)
			end
			local success, err = self:Save(name)
			if not success then return lib:Notify('failed to save config: ' .. err) end
			lib:Notify(string.format('created config %q', name))
			Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
			Options.SaveManager_ConfigList:SetValue(nil)
		end):AddButton('load config', function()
			local name = Options.SaveManager_ConfigList.Value
			local success, err = self:Load(name)
			if not success then return lib:Notify('failed to load config: ' .. err) end
			lib:Notify(string.format('loaded config %q', name))
		end)


		local overwriteConfirming, overwriteTimer = false, nil
		local deleteConfirming,  deleteTimer  = false, nil
		local overwriteBtn, deleteBtn

		overwriteBtn = section:AddButton('overwrite config', function()
			if not overwriteConfirming then
				overwriteConfirming = true
				setRisk(overwriteBtn, 'are you sure?')
				if overwriteTimer then task.cancel(overwriteTimer) end
				overwriteTimer = task.delay(1.0, function()
					overwriteConfirming = false
					resetLabel(overwriteBtn, 'overwrite config')
				end)
			else
				if overwriteTimer then task.cancel(overwriteTimer) end
				overwriteConfirming = false
				resetLabel(overwriteBtn, 'overwrite config')
				local name = Options.SaveManager_ConfigList.Value
				local success, err = self:Save(name)
				if not success then return lib:Notify('failed to overwrite config: ' .. err) end
				lib:Notify(string.format('overwrote config %q', name))
			end
		end)

		deleteBtn = overwriteBtn:AddButton('delete config', function()
			if not deleteConfirming then
				deleteConfirming = true
				setRisk(deleteBtn, 'are you sure?')
				if deleteTimer then task.cancel(deleteTimer) end
				deleteTimer = task.delay(1.0, function()
					deleteConfirming = false
					resetLabel(deleteBtn, 'delete config')
				end)
			else
				if deleteTimer then task.cancel(deleteTimer) end
				deleteConfirming = false
				resetLabel(deleteBtn, 'delete config')
				local name = Options.SaveManager_ConfigList.Value
				if not name then return lib:Notify('no config selected') end
				local path = self.Folder .. '/settings/' .. name .. '.json'
				if isfile(path) then
					delfile(path)
					lib:Notify(string.format('deleted config %q', name))
				else
					lib:Notify('config file not found')
				end
				Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
				Options.SaveManager_ConfigList:SetValue(nil)
			end
		end)


		task.defer(function()
			if deleteBtn and deleteBtn.Outer and overwriteBtn and overwriteBtn.Outer then
				local w = overwriteBtn.Outer.AbsoluteSize.X
				local h = overwriteBtn.Outer.AbsoluteSize.Y
				if w > 0 then
					deleteBtn.Outer.Size = UDim2.fromOffset(w - 2, h)
				end
			end
		end)


		section:AddButton('refresh list', function()
			Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
			Options.SaveManager_ConfigList:SetValue(nil)
		end)


		section:AddButton('set autoload', function()
			local name = Options.SaveManager_ConfigList.Value
			if not name then return end
			writefile(self.Folder .. '/settings/autoload.txt', name)
			SaveManager.AutoloadLabel:SetText('current autoload config: ' .. name)
			lib:Notify(string.format('set %q to auto load', name))
		end):AddButton('remove autoload', function()
			if isfile(self.Folder .. '/settings/autoload.txt') then
				delfile(self.Folder .. '/settings/autoload.txt')
			end
			SaveManager.AutoloadLabel:SetText('current autoload config: none')
			lib:Notify('removed autoload')
		end)

		SaveManager.AutoloadLabel = section:AddLabel('current autoload config: none', true)

		if isfile(self.Folder .. '/settings/autoload.txt') then
			local name = readfile(self.Folder .. '/settings/autoload.txt')
			SaveManager.AutoloadLabel:SetText('current autoload config: ' .. name)
		end

		section:AddDivider()

		section:AddInput('SaveManager_ClipboardInput', { Text = 'import from clipboard' })

		Options.SaveManager_ClipboardInput:OnChanged(function()
			local str = Options.SaveManager_ClipboardInput.Value
			if str:gsub(' ', '') == '' then return end
			local success, err = self:LoadFromString(str)
			if not success then
				lib:Notify('failed to pasted config, did you copy it properly?')
			else
				lib:Notify('loaded copied config!')
				Options.SaveManager_ClipboardInput:SetValue('')
			end
		end)




		section:AddButton('copy config to clipboard', function()
			local name = Options.SaveManager_ConfigList.Value
			if not name then return lib:Notify('no config selected') end
			local path = self.Folder .. '/settings/' .. name .. '.json'
			if not isfile(path) then return lib:Notify('config file not found') end
			pcall(setclipboard, readfile(path))
			lib:Notify(string.format('copied %q to clipboard', name))
		end)
		SaveManager:SetIgnoreIndexes({ 'SaveManager_ConfigList', 'SaveManager_ConfigName', 'SaveManager_ClipboardInput' })
	end
	SaveManager:BuildFolderTree()
end

getgenv().SaveManager = SaveManager;
return SaveManager
