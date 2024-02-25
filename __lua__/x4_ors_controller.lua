-- Load 'ffi' (for calling WinAPI / X4 exported functions)
local ffi = require("ffi")

-- Load 'bit' (bitwise operations)
local bit = require("bit")

-- SirNukes Mod Support APIs library
local snLib = require("extensions.sn_mod_support_apis.lua_interface").Library

-- Register the required WinAPI / X4 exported functions
ffi.cdef[[

typedef uint8_t BYTE, *LPBYTE;
typedef uint16_t WORD;
typedef int16_t SHORT;
typedef uint32_t DWORD;
typedef const char *LPCSTR;
typedef char *LPSTR;
typedef void *HANDLE;
typedef int BOOL;
typedef void *LPVOID;

typedef struct _STARTUPINFOA
{
	DWORD  cb;
	LPSTR  lpReserved;
	LPSTR  lpDesktop;
	LPSTR  lpTitle;
	DWORD  dwX;
	DWORD  dwY;
	DWORD  dwXSize;
	DWORD  dwYSize;
	DWORD  dwXCountChars;
	DWORD  dwYCountChars;
	DWORD  dwFillAttribute;
	DWORD  dwFlags;
	WORD   wShowWindow;
	WORD   cbReserved2;
	LPBYTE lpReserved2;
	HANDLE hStdInput;
	HANDLE hStdOutput;
	HANDLE hStdError;
} STARTUPINFOA, *LPSTARTUPINFOA;

typedef struct _PROCESS_INFORMATION
{
	HANDLE hProcess;
	HANDLE hThread;
	DWORD  dwProcessId;
	DWORD  dwThreadId;
} PROCESS_INFORMATION, *PPROCESS_INFORMATION, *LPPROCESS_INFORMATION;

typedef struct _SECURITY_ATTRIBUTES
{
	DWORD  nLength;
	LPVOID lpSecurityDescriptor;
	BOOL   bInheritHandle;
} SECURITY_ATTRIBUTES, *PSECURITY_ATTRIBUTES, *LPSECURITY_ATTRIBUTES;

static const DWORD FILE_MAP_ALL_ACCESS = 0x000f001f;
static const DWORD MUTEX_ALL_ACCESS = 0x1f0001;


HANDLE OpenFileMappingA(DWORD dwDesiredAccess, BOOL bInheritHandle, LPCSTR lpName);	
void* MapViewOfFile(HANDLE hFileMappingObject, DWORD dwDesiredAccess, DWORD dwFileOffsetHigh, DWORD dwFileOffsetLow, size_t dwNumberOfBytesToMap);
BOOL UnmapViewOfFile(void* lpBaseAddress);

DWORD GetFullPathNameA(LPCSTR lpFileName,DWORD nBufferLength, LPSTR lpBuffer, LPSTR *lpFilePart);
BOOL CreateProcessA(LPCSTR lpApplicationName, LPSTR lpCommandLine, LPSECURITY_ATTRIBUTES lpProcessAttributes, LPSECURITY_ATTRIBUTES lpThreadAttributes, BOOL bInheritHandles, DWORD dwCreationFlags, LPVOID lpEnvironment, LPCSTR lpCurrentDirectory, LPSTARTUPINFOA lpStartupInfo, LPPROCESS_INFORMATION lpProcessInformation);
DWORD GetLastError();
HANDLE OpenMutexA(DWORD dwDesiredAccess, BOOL bInheritHandle, LPCSTR lpName);
BOOL CloseHandle(HANDLE hObject);

void Sleep(DWORD dwMilliseconds);
BOOL CloseHandle(HANDLE hObject);
SHORT GetAsyncKeyState(int vKey);


typedef uint64_t UniverseID;

float GetDistanceBetween(UniverseID component1id, UniverseID component2id);
bool IsComponentClass(UniverseID componentid, const char* classname);
bool IsGamePaused(void);
bool IsPlayerValid(void);
UniverseID GetPlayerControlledShipID(void);
UniverseID GetPlayerID(void);

]]

-- Shorthand for C namespace
local C = ffi.C


--[[
	************************************************************
	************* Show Radio Name upon Changing Radio **********
	********* Based on Kuertee HUD + SN Mod Support APIs *******
	************************************************************
]]--

local RadioNameMenu =
{
	Visible = false,
	PopupTime = 0,
	Text = "",
	BgColor = {r = 0, g = 0, b = 0, a = 60},
	TextColor = {r = 0, g = 204, b = 204, a = 100},
	TopLevelMenu = nil
}

function RadioNameMenu.onCreateRadioNameMenu(frame)
	local ftable
	if RadioNameMenu.Visible then
		ftable = frame:addTable(1, {width = 400, height = 200, x = (frame.properties.width / 2) - 200, y = 100, scaling = true})
		local row = ftable:addRow(false, {bgColor = RadioNameMenu.BgColor})
		row[1]:createText(RadioNameMenu.Text, {halign = "center", color = RadioNameMenu.TextColor, font = Helper.standardFontBold, fontsize = Helper.standardFontSize * 4})
		ftable.properties.height = ftable:getVisibleHeight()
	else
		ftable = frame:addTable(1, {width = 0, height = 0, x = 0, y = 0, scaling = false})
		ftable.properties.height = 0
	end
	return {ftables = {ftable}}
end

function RadioNameMenu.Show(myText)
	RadioNameMenu.Visible = true
	RadioNameMenu.PopupTime = getElapsedTime()
	RadioNameMenu.Text = myText
	if (RadioNameMenu.TopLevelMenu == nil) then
		RadioNameMenu.TopLevelMenu = snLib.Get_Egosoft_Menu("TopLevelMenu")
		RadioNameMenu.TopLevelMenu.registerCallback("kHUD_add_HUD_tables", RadioNameMenu.onCreateRadioNameMenu)
	end
	RadioNameMenu.TopLevelMenu.requestUpdate()
end

function RadioNameMenu.Hide()
	RadioNameMenu.Visible = false
	if (RadioNameMenu.TopLevelMenu ~= nil) then
		RadioNameMenu.TopLevelMenu.requestUpdate()
	end
end

--[[
	************************************************************
	********************** Script Header ***********************
	************************************************************
]]--

-- Stores game options menu, and related stuff (used for overriding music slider setting)
local GameOptions =
{
	IsSoundEnabled = true,
	MasterVolume = 0,
	Menu = nil,
	OldFunctions = nil
}

-- Stores script vars
local X4Ors =
{
	Failed = false,
	IsInitialized = false,
	KeyBindings = nil,
	ScriptButtonPressed = false,
	RadioStationIndex = nil,
	RadioStations = nil,
	MusicVolume = 100,
	IsBgMusicMuted = false
}

--[[
	************************************************************
	************************* Helpers **************************
	************************************************************
]]--

local function trim(s)
	return string.gsub(s, "^%s*(.-)%s*$", "%1")
end

local function PrintError(str)
	DebugError(string.format("X4 ORS: %s", str)) -- Print to debug log
end

local function HandleBgMusVol(allowGameBgMusic)
	if allowGameBgMusic then
		if X4Ors.IsBgMusicMuted then
			X4Ors.IsBgMusicMuted = false
			SetVolumeOption("music", __CORE_GAMEOPTIONS_RESTOREINFO.x4_ors_cached_bgvol)
		end
	else
		if not X4Ors.IsBgMusicMuted then
			X4Ors.IsBgMusicMuted = true
			__CORE_GAMEOPTIONS_RESTOREINFO.x4_ors_cached_bgvol = GetVolumeOption("music")
			SetVolumeOption("music", 0)
		end
	end
end

--[[
	************************************************************
	********************* Data Processing **********************
	************************************************************
]]--

local function ConstructGameDataOutputString(isActiveMenu, isPiloting, isAlive)
	local dataOut = ""
	
	-- Current radio station index
	dataOut = dataOut .. string.format("current_station_index: %d", X4Ors.RadioStationIndex)
	
	-- Music volume
	local locMusVol
	if GameOptions.IsSoundEnabled then
		locMusVol = math.floor(X4Ors.MusicVolume * GameOptions.MasterVolume * __CORE_GAMEOPTIONS_RESTOREINFO.x4_ors_cached_bgvol)
	else
		locMusVol = 0
	end
	dataOut = dataOut .. string.char(10) .. string.format("music_volume: %d", locMusVol)
	
	-- Is active menu
	if isActiveMenu then
		dataOut = dataOut .. string.char(10) .. " is_active_menu: 1"
	else
		dataOut = dataOut .. string.char(10) .. " is_active_menu: 0"
	end
	
	-- Is piloting
	if isPiloting then
		dataOut = dataOut .. string.char(10) .. " is_piloting: 1"
	else
		dataOut = dataOut .. string.char(10) .. " is_piloting: 0"
	end
	
	-- Is alive
	if isAlive then
		dataOut = dataOut .. string.char(10) .. " is_alive: 1"
	else
		dataOut = dataOut .. string.char(10) .. " is_alive: 0"
	end
	
	-- Faction station distance data. Only query data, if it actually has an effect.
	if isActiveMenu and isPiloting and isAlive and (locMusVol > 0) and (X4Ors.RadioStationIndex >= 0) then
		-- Collect data
		local playerID = ffi.cast("UniverseID", C.GetPlayerID())
		local numFactions = C.GetNumAllFactions(true)
		local factionNames = ffi.new("const char*[?]", numFactions)
		numFactions = C.GetAllFactions(factionNames, numFactions, true)
		
		-- Enumerate all factions
		for i = 0, numFactions - 1 do
			local numCurrFactStations = C.GetNumAllFactionStations(factionNames[i])
			local currFactStations = ffi.new("UniverseID[?]", numCurrFactStations)
			numCurrFactStations = C.GetAllFactionStations(currFactStations, numCurrFactStations, factionNames[i])
			
			-- Enumerate all stations for this faction
			if (numCurrFactStations > 0) then
				local currFactionName = ffi.string(factionNames[i])
				
				-- Find the closest station (by distance)
				local shortestDist = 1000000000000
				for j = 0, numCurrFactStations - 1 do
					local currStation = ConvertStringTo64Bit(tostring(currFactStations[j]))
					if IsComponentClass(currStation, "station") then
						local currStationDistance = C.GetDistanceBetween(currStation, playerID)
						if (currStationDistance < shortestDist) then
							shortestDist = currStationDistance
						end
					end
				end
				
				-- Write the data
				dataOut = dataOut .. string.char(10) .. string.format(" faction_station: %s %f", currFactionName, shortestDist)
			end
		end
	end
	
	-- Done
	return dataOut
end

--[[
	************************************************************
	******************** EXE Communication *********************
	************************************************************
]]--

local function GetSharedMemHandle()
	return C.OpenFileMappingA(C.FILE_MAP_ALL_ACCESS, 0, "jupiter_x4_ors_memory__main_shared_mem")
end

local function IsExeRunning()
	local appMutexHandle = C.OpenMutexA(C.MUTEX_ALL_ACCESS, 0, "jupiter_x4_ors__program_instance")
	if (appMutexHandle == nil) or (appMutexHandle == 0) then
		return false
	else
		C.CloseHandle(appMutexHandle)
		return true
	end
end

local function ReadExeData(memoryBuffer)
	local dataIn = ""
	
	-- Check, if EXE is running
	if (not IsExeRunning()) then
		PrintError("Cannot request data, because the X4 ORS Player EXE is not running!")
		memoryBuffer[0] = 0
		return
	end
	
	-- Wait for completion of the request
	while true do
		dataIn = ""
		for i = 0, 262143 do
			if (memoryBuffer[i] == 0) then
				break
			else
				dataIn = dataIn .. string.char(memoryBuffer[i])
			end
		end
		dataIn = trim(dataIn)
		if (string.find(dataIn, "programdata") == 1) then
			break
		elseif (not IsExeRunning()) then
			PrintError("The X4 ORS Player EXE crashed during request!")
			memoryBuffer[0] = 0
			return
		else
			C.Sleep(10)
		end
	end
	
	-- Initialize the script
	X4Ors.KeyBindings = {0, 0, 0, 0, 0, 0, 0}
	X4Ors.RadioStations = {}
	X4Ors.RadioStationIndex = -1
	X4Ors.MusicVolume = 100
	X4Ors.ScriptButtonPressed = false
	
	-- Parse the data on the fly
	local tok, tok2, tok3, currentToken, tokenName, tokenValue, tokenName2, tokenValue2
	dataIn = trim(string.sub(dataIn, 12, #dataIn)) -- cut off 'programdata'
	repeat
		tok = string.find(dataIn, string.char(10))
		if (tok == nil) then
			currentToken = dataIn
		else
			currentToken = string.sub(dataIn, 1, tok - 1)
			dataIn = string.sub(dataIn, tok + 1, #dataIn)
		end
		tok2 = string.find(currentToken, ":")
		if (tok2 ~= nil) then
			tokenName = trim(string.sub(currentToken, 1, tok2 - 1))
			tokenValue = trim(string.sub(currentToken, tok2 + 1, #currentToken))
		end
		
		-- Process the tokens
		if (string.lower(tokenName) == "latency") then
			SetNPCBlackboard(ConvertStringTo64Bit(tostring(C.GetPlayerID())), "$x4_ors_latency", tonumber(tokenValue))
		elseif string.lower(tokenName) == "radio_station" then
			table.insert(X4Ors.RadioStations, tokenValue)
		elseif string.lower(tokenName) == "key_binding" then
			tok3 = string.find(tokenValue, " ")
			if (tok3 == nil) then
				tok3 = string.find(tokenValue, string.char(9))
			end
			if (tok3 ~= nil) then
				tokenName2 = trim(string.sub(tokenValue, 1, tok3 - 1))
				tokenValue2 = trim(string.sub(tokenValue, tok3 + 1, #tokenValue))
				local keyIndex = tonumber(tokenName2)
				local keyID = tonumber(tokenValue2)
				if (keyIndex > 0) and (keyIndex <= 7) then
					X4Ors.KeyBindings[keyIndex] = keyID
					SetNPCBlackboard(ConvertStringTo64Bit(tostring(C.GetPlayerID())), string.format("$x4_ors_currentkey_%d", keyIndex), keyID)
				else
					PrintError(string.format("Key binding '%d' is out of range!", keyIndex))
				end
			else
				PrintError(string.format("Key binding '%s' is malformed!", tokenValue))
			end
		end
	until (tok == nil)
	
	-- Done
	memoryBuffer[0] = 0
end

local function SendExeData(functionID, functionParamString, memoryBuffer)
	-- Write Function Param Str
	memoryBuffer[0] = 0
	memoryBuffer[#functionID] = 10
	memoryBuffer[#functionID + #functionParamString + 1] = 0
	for i = 1, #functionParamString do
		memoryBuffer[i + #functionID] = string.byte(functionParamString, i)
	end
	
	-- Write Function ID
	for i = 1, #functionID do
		memoryBuffer[i - 1] = string.byte(functionID, i)
	end
end

--[[
	************************************************************
	******************* Script Main Process ********************
	************************************************************
]]--

local function ProcessScriptMain(sharedMemHandle)
	local memoryBuffer = ffi.cast("LPBYTE", C.MapViewOfFile(sharedMemHandle, C.FILE_MAP_ALL_ACCESS, 0, 0, 262144))
	
	-- Generic vars
	local playerShip = C.GetPlayerControlledShipID()
	local exeFunction = ""
	local prevRadioStationIndex = X4Ors.RadioStationIndex
	
	-- Player state vars
	local isActiveMenu = not C.IsGamePaused()
	local isPiloting = (playerShip ~= 0) and (not C.IsComponentClass(playerShip, "spacesuit"))
	local isAlive = C.IsPlayerValid()
	
	-- Only react to keys, if we're OK
	if isActiveMenu and isPiloting and isAlive and X4Ors.IsInitialized then
		if (X4Ors.KeyBindings ~= nil) then
			local mk1State = false
			local mk2State = false
			for i = 1, 7 do
				if (X4Ors.KeyBindings[i] ~= nil) and (X4Ors.KeyBindings[i] ~= 0) then
					if (bit.band(C.GetAsyncKeyState(X4Ors.KeyBindings[i]), 0x8000) ~= 0) then
						if (i == 1) then
							mk1State = true
						elseif (i == 2) then
							mk2State = true
						elseif (not X4Ors.ScriptButtonPressed) and mk1State and mk2State then -- Prevent the script from detecting a long keypress as multiple keypresses...
							X4Ors.ScriptButtonPressed = true
							if (i == 3) then
								X4Ors.RadioStationIndex = X4Ors.RadioStationIndex - 1
							elseif (i == 4) then
								X4Ors.RadioStationIndex = X4Ors.RadioStationIndex + 1
							elseif (i == 5) then
								exeFunction = "replay_mp3"
							elseif (i == 6) then
								exeFunction = "skip_mp3"
							elseif (i == 7) then
								exeFunction = "reload"
							end
							
							-- If we've changed the radio station, we must handle it!
							if (X4Ors.RadioStationIndex ~= prevRadioStationIndex) then
								-- Radio station index must be within the bounds
								if (X4Ors.RadioStationIndex < -1) then
									X4Ors.RadioStationIndex = #X4Ors.RadioStations - 1
								elseif (X4Ors.RadioStationIndex == #X4Ors.RadioStations) then
									X4Ors.RadioStationIndex = -1
								end
								
								-- Radio station has changed, show its name!
								if (X4Ors.RadioStationIndex < 0) then
									RadioNameMenu.Show("\027[faction_ownerless]\027X")
								else
									RadioNameMenu.Show(X4Ors.RadioStations[X4Ors.RadioStationIndex + 1])
								end
							end
						end
					end
				else
					if (i == 1) then
						mk1State = true
					elseif (i == 2) then
						mk2State = true
					end
				end
			end
			if X4Ors.ScriptButtonPressed then
				local currentKeyPressed = false
				for i = 3, 7 do
					if (X4Ors.KeyBindings[i] ~= nil) and (X4Ors.KeyBindings[i] ~= 0) and (bit.band(C.GetAsyncKeyState(X4Ors.KeyBindings[i]), 0x8000) ~= 0) then
						currentKeyPressed = true
						break
					end
				end
				if (not currentKeyPressed) then
					X4Ors.ScriptButtonPressed = false -- This restores the ability to detect keypresses...
				end
			end
		end
		
		-- If the radio is on, keep the game music muted
		HandleBgMusVol(X4Ors.RadioStationIndex < 0)
	else
		-- If we're currently not eligible to listen to the radio, restore game music
		HandleBgMusVol(true)
	end
	
	-- Send EXE data
	if (not X4Ors.IsInitialized) then
		X4Ors.IsInitialized = true
		SendExeData("request", "", memoryBuffer)
		ReadExeData(memoryBuffer)
	elseif (memoryBuffer[0] == 0) then
		if (exeFunction == "") then
			SendExeData("gamedata", ConstructGameDataOutputString(isActiveMenu, isPiloting, isAlive), memoryBuffer)
		else
			SendExeData(exeFunction, "", memoryBuffer)
			-- If we've triggered an EXE reload, then we must also reload the LUA script
			if (exeFunction == "reload") then
				X4Ors.IsInitialized = false
			end
		end
	end
	C.UnmapViewOfFile(memoryBuffer)
end

local function InitExe()
	local startupInfoStruct = ffi.new("STARTUPINFOA")
	local processInfoStruct = ffi.new("PROCESS_INFORMATION")
	local exeFullPath = ffi.new("char[2048]")
	local startupInfoStructPtr = ffi.cast("LPSTARTUPINFOA", startupInfoStruct)
	local processInfoStructPtr = ffi.cast("LPPROCESS_INFORMATION", processInfoStruct)
	
	-- Start the EXE
	if (C.GetFullPathNameA("extensions/X4_ORS/radiostations/X4OwnRadioStationsPlayer.exe", 2048, exeFullPath, nil) ~= 0) then
		if (C.CreateProcessA(exeFullPath, nil, nil, nil, 0, 0, nil, nil, startupInfoStructPtr, processInfoStructPtr) ~= 0) then
			-- Wait until the EXE starts up, and creates the shared memory
			while (not IsExeRunning()) do
				C.Sleep(0)
			end
			local sharedMemHandle = nil
			while (sharedMemHandle == nil) do
				if (not IsExeRunning()) then
					PrintError("The X4 ORS Player EXE failed to initialize!")
					return false
				else
					sharedMemHandle = GetSharedMemHandle()
					if (sharedMemHandle ~= nil) then
						C.CloseHandle(sharedMemHandle)
						return true
					else
						C.Sleep(10)
					end
				end
			end
		else
			PrintError(string.format("Failed to start the X4 ORS Player EXE! Error code: %d", C.GetLastError()))
			return false
		end
	else
		PrintError(string.format("Failed to get full path to the X4 ORS Player EXE! Error code: %d", C.GetLastError()))
		return false
	end
end

local function ProcessScript()
	-- Hide rado name, if the time has elapsed
	if RadioNameMenu.Visible and (getElapsedTime() > (RadioNameMenu.PopupTime + 5.0)) then
		RadioNameMenu.Hide()
	end
	
	-- An already failed script would not benefit from trying to continuously start the EXE
	if X4Ors.Failed then
		HandleBgMusVol(true)
		return
	end
	
	-- If the EXE is not running, try to start it
	if (not IsExeRunning()) then
		X4Ors.IsInitialized = false
		HandleBgMusVol(true)
		if (not InitExe()) then
			X4Ors.Failed = true
			return
		end
	end
	
	-- Access the shared memory, and run the script
	local sharedMemHandle = GetSharedMemHandle()
	ProcessScriptMain(sharedMemHandle)
	C.CloseHandle(sharedMemHandle)
end

--[[
	************************************************************
	************ Event Handlers (fired by MD script) ***********
	************************************************************
]]--

local function onTick(_, param)
	ProcessScript()
end

local function onStartSpeak(_, param)
	X4Ors.MusicVolume = math.floor(X4Ors.MusicVolume * 0.375) -- Lower volume
end

local function onEndSpeak(_, param)
	X4Ors.MusicVolume = math.floor(X4Ors.MusicVolume / 0.375) -- Restore volume
	if (X4Ors.MusicVolume > 100) then
		X4Ors.MusicVolume = 100
	end
end

local function onChangeKeyBinding(_, param)
	if IsExeRunning() and X4Ors.IsInitialized and (not X4Ors.Failed) then
		-- Store key binding
		local keyIndex = GetNPCBlackboard(ConvertStringTo64Bit(tostring(C.GetPlayerID())), "$x4_ors_setkey_keyindex")
		local keyID = GetNPCBlackboard(ConvertStringTo64Bit(tostring(C.GetPlayerID())), "$x4_ors_setkey_vkey")
		if (keyIndex > 0) and (keyIndex <= 7) and (X4Ors.KeyBindings ~= nil) then
			-- Save to MD
			SetNPCBlackboard(ConvertStringTo64Bit(tostring(C.GetPlayerID())), string.format("$x4_ors_currentkey_%d", keyIndex), keyID)
			
			-- Save to LUA
			X4Ors.KeyBindings[keyIndex] = keyID
			
			-- Save to INI via EXE
			local sharedMemHandle = GetSharedMemHandle()
			local memoryBuffer = ffi.cast("LPBYTE", C.MapViewOfFile(sharedMemHandle, C.FILE_MAP_ALL_ACCESS, 0, 0, 262144))
			SendExeData("set_key", string.format("%d: %d", keyIndex, keyID), memoryBuffer)
			C.UnmapViewOfFile(memoryBuffer)
			C.CloseHandle(sharedMemHandle)
		else
			PrintError(string.format("Key binding '%d' is out of range!", keyIndex))
		end
	end
end

--[[
	************************************************************
	*********** Hooks for Music / Sfx menu handlers ************
	************************************************************
]]--

local function onRestoreDefaults()
	GameOptions.OldFunctions.RestoreDefaults()
	__CORE_GAMEOPTIONS_RESTOREINFO.x4_ors_cached_bgvol = GetVolumeOption("music")
	if X4Ors.IsBgMusicMuted then
		SetVolumeOption("music", 0)
	end
	GameOptions.MasterVolume = GetVolumeOption("master")
	GameOptions.IsSoundEnabled = GetSoundOption()
end

local function onRestoreSfxDefaults()
	GameOptions.OldFunctions.RestoreSfxDefaults()
	__CORE_GAMEOPTIONS_RESTOREINFO.x4_ors_cached_bgvol = GetVolumeOption("music")
	if X4Ors.IsBgMusicMuted then
		SetVolumeOption("music", 0)
	end
	GameOptions.MasterVolume = GetVolumeOption("master")
	GameOptions.IsSoundEnabled = GetSoundOption()
end

local function onGetSlider(sfxtype)
	local scale = GameOptions.OldFunctions.GetSlider(sfxtype)
	if (sfxtype == "music" and X4Ors.IsBgMusicMuted) then
		scale.start = Helper.round(__CORE_GAMEOPTIONS_RESTOREINFO.x4_ors_cached_bgvol * 100)
	end
	return scale
end

local function onSetSlider(sfxtype, value)
	if (sfxtype == "music") then
		__CORE_GAMEOPTIONS_RESTOREINFO.x4_ors_cached_bgvol = value / 100.0
		if X4Ors.IsBgMusicMuted then
			SetVolumeOption("music", 0)
		else
			SetVolumeOption("music", value / 100.0)
		end
	elseif (sfxtype == "master") then
		GameOptions.OldFunctions.SetSlider(sfxtype, value)
		GameOptions.MasterVolume = value / 100.0
	else
		GameOptions.OldFunctions.SetSlider(sfxtype, value)
	end
end

local function onSetSound()
	GameOptions.OldFunctions.SetSound()
	GameOptions.IsSoundEnabled = GetSoundOption()
end

local function onDestroyOptionsMenu(obj)
	GameOptions.Menu.callbackDefaults = GameOptions.OldFunctions.RestoreDefaults
	GameOptions.Menu.callbackSfxDefaults = GameOptions.OldFunctions.RestoreSfxDefaults
	GameOptions.Menu.valueSfxSetting = GameOptions.OldFunctions.GetSlider
	GameOptions.Menu.callbackSfxSetting = GameOptions.OldFunctions.SetSlider
	GameOptions.Menu.callbackSfxSound = GameOptions.OldFunctions.SetSound
	
	-- Set bg music back to original value
	SetVolumeOption("music", __CORE_GAMEOPTIONS_RESTOREINFO.x4_ors_cached_bgvol)
	X4Ors.IsBgMusicMuted = false
end

--[[
	************************************************************
	*********************** Script Init ************************
	************************************************************
]]--

-- Based on: https://stackoverflow.com/questions/55585619/why-is-the-userdata-object-added-to-tables-in-this-lua-5-1-gc-workaround
-- Updated to support LUA 5.2 (where there's no 'newproxy', but tables have valid '__gc' instead)
local function SetObjectGC(obj, gc)
	if (newproxy ~= nil) then
		local gcNewProxy = newproxy(true)
		getmetatable(gcNewProxy).__gc =
			function()
				gc(obj)
			end
		obj[gcNewProxy] = true
	end
	return setmetatable(obj, {__gc = gc})
end

local function InitScript()
	X4Ors.Failed = false
	X4Ors.IsInitialized = false
	
	-- Install hooks for X4 Sound Options menu
	GameOptions = SetObjectGC(GameOptions, onDestroyOptionsMenu)
	GameOptions.Menu = snLib.Get_Egosoft_Menu("OptionsMenu")
	GameOptions.OldFunctions = {}
	GameOptions.OldFunctions.RestoreDefaults = GameOptions.Menu.callbackDefaults
	GameOptions.Menu.callbackDefaults = onRestoreDefaults
	GameOptions.OldFunctions.RestoreSfxDefaults = GameOptions.Menu.callbackSfxDefaults
	GameOptions.Menu.callbackSfxDefaults = onRestoreSfxDefaults
	GameOptions.OldFunctions.GetSlider = GameOptions.Menu.valueSfxSetting
	GameOptions.Menu.valueSfxSetting = onGetSlider
	GameOptions.OldFunctions.SetSlider = GameOptions.Menu.callbackSfxSetting
	GameOptions.Menu.callbackSfxSetting = onSetSlider
	GameOptions.OldFunctions.SetSound = GameOptions.Menu.callbackSfxSound
	GameOptions.Menu.callbackSfxSound = onSetSound
	
	-- Initialize the relevant SFX options
	GameOptions.MasterVolume = GetVolumeOption("master")
	GameOptions.IsSoundEnabled = GetSoundOption()
	__CORE_GAMEOPTIONS_RESTOREINFO = __CORE_GAMEOPTIONS_RESTOREINFO or {}
	if (__CORE_GAMEOPTIONS_RESTOREINFO.x4_ors_cached_bgvol == nil) then
		__CORE_GAMEOPTIONS_RESTOREINFO.x4_ors_cached_bgvol = GetVolumeOption("music")
	else
		SetVolumeOption("music", __CORE_GAMEOPTIONS_RESTOREINFO.x4_ors_cached_bgvol)
	end
	
	-- Register MD event handlers
	RegisterEvent("X4_ORS_Tick", onTick)
	RegisterEvent("X4_ORS_StartSpeak", onStartSpeak)
	RegisterEvent("X4_ORS_EndSpeak", onEndSpeak)
	RegisterEvent("X4_ORS_ChangeKeyBinding", onChangeKeyBinding)
	
	-- First-time run
	ProcessScript()
end

-- Start script
InitScript()
