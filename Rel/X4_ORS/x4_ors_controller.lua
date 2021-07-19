-- Load 'ffi' (for calling WinAPI / X4 exported functions)
local ffi = require("ffi")

-- Load 'bit' (bitwise operations)
local bit = require("bit")

-- SirNukes Mod Support APIs library
local snLib = require ("extensions.sn_mod_support_apis.lua_interface").Library

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


HANDLE OpenFileMappingA(DWORD dwDesiredAccess, BOOL bInheritHandle, LPCSTR lpName);	
void* MapViewOfFile(HANDLE hFileMappingObject, DWORD dwDesiredAccess, DWORD dwFileOffsetHigh, DWORD dwFileOffsetLow, size_t dwNumberOfBytesToMap);
BOOL UnmapViewOfFile(void* lpBaseAddress);

DWORD GetFullPathNameA(LPCSTR lpFileName,DWORD nBufferLength, LPSTR lpBuffer, LPSTR *lpFilePart);
BOOL CreateProcessA(LPCSTR lpApplicationName, LPSTR lpCommandLine, LPSECURITY_ATTRIBUTES lpProcessAttributes, LPSECURITY_ATTRIBUTES lpThreadAttributes, BOOL bInheritHandles, DWORD dwCreationFlags, LPVOID lpEnvironment, LPCSTR lpCurrentDirectory, LPSTARTUPINFOA lpStartupInfo, LPPROCESS_INFORMATION lpProcessInformation);
DWORD GetLastError();

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

-- Overrides Music slider setting
local gameoptions

--[[
	************************************************************
	************* Show Radio Name upon Changing Radio **********
	********* Based on Kuertee HUD + SN Mod Support APIs *******
	************************************************************
]]--

local topLevelMenu

local radioNameMenu =
{
	lastPopupTime = 0,
	shown = false,
	text = "",
	bgColor = {r = 0, g = 0, b = 0, a = 60},
	textColor = {r = 0, g = 204, b = 204, a = 100}
}

function radioNameMenu.onCreateRadioNameMenu(frame)
	local ftable
	if radioNameMenu.shown then
		ftable = frame:addTable(1, {width = 400, height = 200, x = (frame.properties.width / 2) - 200, y = 100, scaling = true})
		local row = ftable:addRow(false, {bgColor = radioNameMenu.bgColor})
		row[1]:createText(radioNameMenu.text, {halign = "center", color = radioNameMenu.textColor, font = Helper.standardFontBold, fontsize = Helper.standardFontSize * 4})
		ftable.properties.height = ftable:getVisibleHeight()
	else
		ftable = frame:addTable(1, {width = 0, height = 0, x = 0, y = 0, scaling = false})
		ftable.properties.height = 0
	end
	return {ftables = {ftable}}
end

local function showRadioName(text)
	radioNameMenu.lastPopupTime = getElapsedTime()
	radioNameMenu.shown = true
	radioNameMenu.text = text
	topLevelMenu.requestUpdate()
end

local function hideRadioName()
	radioNameMenu.shown = false
	topLevelMenu.requestUpdate()
end

--[[
	************************************************************
	************* Background Music Volume Control **************
	************************************************************
]]--

local is_bg_mus_muted = false

local function HandleBgMusVol(bRestore)
	if bRestore then
		if is_bg_mus_muted then
			is_bg_mus_muted = false
			SetVolumeOption("music", __CORE_GAMEOPTIONS_RESTOREINFO.x4_ors_cached_bgvol)
		end
	else
		if not is_bg_mus_muted then
			is_bg_mus_muted = true
			__CORE_GAMEOPTIONS_RESTOREINFO.x4_ors_cached_bgvol = GetVolumeOption("music")
			SetVolumeOption("music", 0)
		end
	end
end

--[[
	************************************************************
	************************* Helpers **************************
	************************************************************
]]--

local function trim1(s)
   return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function PrintError(str)
	str = "X4_ORS: " .. str
	DebugError(str) -- Print to debug log
end

--[[
	************************************************************
	******************** EXE Communication *********************
	************************************************************
]]--

local maxlatency
local rsnames
local rsindex
local musvol

local function OpenMemFile()
	return C.OpenFileMappingA(C.FILE_MAP_ALL_ACCESS, 0, "jupiter_x4_ors_memory__main_shared_mem")
end

local function GetExeData(buf)
	local i

	-- Request data
	local request = "request"
	
	for i = 1, #request do
		buf[i - 1] = string.byte(request, i)
	end
	buf[#request] = 0 -- null-terminator
	
	-- Read data from shared memory
	local data
	repeat
		data = ""
		for i = 0, 262143 do
			if buf[i] == 0 then -- null-terminator
				break
			else
				data = data .. string.char(buf[i])
			end
		end
		C.Sleep(10) -- must wait!
	until (data:find("programdata") == 1)
	
	-- (Re)-Initialize variables
	data = string.sub(data, 12, #data) -- cut off 'programdata'
	rsnames = {} -- New, empty list
	rsindex = -1
	musvol = 100
	
	-- Tokenize
	local tok
	local tok2
	local currentToken
	local tokenName
	local tokenValue
	repeat
		tok = data:find(",")
		if tok == nil then
			currentToken = data
		else
			currentToken = string.sub(data, 1, tok - 1)
			data = string.sub(data, tok + 1, #data)
		end
		tok2 = currentToken:find(":")
		if tok2 ~= nil then
			tokenName = trim1(string.sub(currentToken, 1, tok2 - 1))
			tokenValue = trim1(string.sub(currentToken, tok2 + 1, #currentToken))
			if string.lower(tokenName) == "latency" then
				maxlatency = tonumber(tokenValue)
				SetNPCBlackboard(ConvertStringTo64Bit(tostring(C.GetPlayerID())), "$x4_ors_latency", maxlatency)
			elseif string.lower(tokenName) == "radio_name" then
				table.insert(rsnames, tokenValue)
			end
		end
	until (tok == nil)
	
	buf[0] = 0 -- Reset data in mem file (script can send data!)
end

local function SendExeData(buf, isactivemenu, isdriving, isalive, isskipmp3, isreplaymp3)
	local out_string
	
	if isreplaymp3 then
		out_string = "replay_mp3"
	elseif isskipmp3 then
		out_string = "skip_next_mp3"
	else
		out_string = "gamedata"
		
		-- Current station index
		out_string = out_string .. "current_station_index: " .. tostring(rsindex)
		
		-- Music vol
		local localmusvol
		if gameoptions.issoundenabled then
			localmusvol = math.floor(musvol * gameoptions.mastervolume * __CORE_GAMEOPTIONS_RESTOREINFO.x4_ors_cached_bgvol)
		else
			localmusvol = 0
		end
		out_string = out_string .. ", music_volume: " .. tostring(localmusvol)
		
		-- Is active menu
		if isactivemenu then
			out_string = out_string .. ", is_active_menu: 1"
		else
			out_string = out_string .. ", is_active_menu: 0"
		end
		
		-- Is driving
		if isdriving then
			out_string = out_string .. ", is_driving: 1"
		else
			out_string = out_string .. ", is_driving: 0"
		end
		
		-- Is alive
		if isalive then
			out_string = out_string .. ", is_alive: 1"
		else
			out_string = out_string .. ", is_alive: 0"
		end
		
		-- What we need... We only query faction data, if we are eligible to listen to the music
		if isactivemenu and isdriving and isalive and (localmusvol > 0) and (rsindex >= 0) then
			-- Faction data
			local numFactions = C.GetNumAllFactions(true)
			local factionNames = ffi.new("const char*[?]", numFactions)
			numFactions = C.GetAllFactions(factionNames, numFactions, true)
			
			local plyr = ffi.cast("UniverseID", C.GetPlayerID())
			
			local i = 0
			for i = 0, numFactions - 1 do
				local numCurrFactStations = C.GetNumAllFactionStations(factionNames[i])
				local currFactStations = ffi.new("UniverseID[?]", numCurrFactStations)
				numCurrFactStations = C.GetAllFactionStations(currFactStations, numCurrFactStations, factionNames[i])
				
				if numCurrFactStations > 0 then
					-- Write faction name
					local currFactionName = ffi.string(factionNames[i])
					
					-- Find shortest distance
					local j = 0
					local mindist = 1000000000000
					for j = 0, numCurrFactStations - 1 do
						local currstation = ConvertStringTo64Bit(tostring(currFactStations[j]))
						if IsComponentClass(currstation, "station") then
							local currStationDistance = C.GetDistanceBetween(currstation, plyr)
							if (currStationDistance < mindist) then
								mindist = currStationDistance
							end
						end
					end
					
					if mindist < 1000000000000 then
						out_string = out_string .. ", faction_station: " .. currFactionName .. ": " .. tostring(mindist)
					end
				end
			end
		end
	end

	-- Write byte data
	for i = 1, #out_string do
		buf[i - 1] = string.byte(out_string, i)
	end
	buf[#out_string] = 0  -- null-terminator
end

--[[
	************************************************************
	******************* Script Main Process ********************
	************************************************************
]]--

local initialized = false
local failed = false
local buttonpressed = false

local function ProcessScriptMain(shmem)
	local buf = ffi.cast("LPBYTE", C.MapViewOfFile(shmem, C.FILE_MAP_ALL_ACCESS, 0, 0, 262144))
	if (initialized == nil) or (not initialized) then -- If not initialized, query data from exe
		initialized = true
		GetExeData(buf)
	else
		local ship = C.GetPlayerControlledShipID()
		
		-- Player state vars
		local isactivemenu = not C.IsGamePaused()
		local isdriving = (ship ~= 0) and (not C.IsComponentClass(ship, "spacesuit"))
		local isalive = C.IsPlayerValid()	
		local isskipmp3 = false
		local isreplaymp3 = false
		
		if isactivemenu and isdriving and isalive then		
			-- Only react to radio changer keys, if we're full ok
			local ctrlstate = bit.band(C.GetAsyncKeyState(0x11), 0x8000)
			local altstate = bit.band(C.GetAsyncKeyState(0x12), 0x8000)
			if (altstate ~= 0) and (ctrlstate ~= 0) then
				local downstate = bit.band(C.GetAsyncKeyState(0x28), 0x8000)
				local upstate = bit.band(C.GetAsyncKeyState(0x26), 0x8000)
				local rightstate = bit.band(C.GetAsyncKeyState(0x27), 0x8000)
				local leftstate = bit.band(C.GetAsyncKeyState(0x25), 0x8000)
				if (downstate ~= 0) or (upstate ~= 0) or (rightstate ~= 0) or (leftstate ~= 0) then
					if (buttonpressed == nil) or (not buttonpressed) then
						buttonpressed = true
						
						local previndex = rsindex
						local radiotext
						
						-- Change station on button press
						if downstate ~= 0 then
							rsindex = rsindex - 1
						elseif upstate ~= 0 then
							rsindex = rsindex + 1
						elseif rightstate ~= 0 then
							isskipmp3 = true
						else
							isreplaymp3 = true
						end
						if rsindex < -1 then
							rsindex = #rsnames - 1
						elseif rsindex == #rsnames then
							rsindex = -1
						end
						
						if previndex ~= rsindex then
							if (rsindex < 0) or (rsindex >= #rsnames) then
								radiotext = "[RADIO OFF]"
							else
								radiotext = rsnames[rsindex + 1]
							end
							showRadioName(radiotext)
						end
					end
				else
					buttonpressed = false
				end
			else
				buttonpressed = false
			end
			
			-- Keep background music muted, if we're full OK, and radio is on too
			HandleBgMusVol(rsindex < 0)
		else
			-- Restore background music, if we're  not OK
			HandleBgMusVol(true)
		end
		
		-- Send the data, if both the EXE, and WE are ready to send that data...
		if (buf[0] == 0) then
			SendExeData(buf, isactivemenu, isdriving, isalive, isskipmp3, isreplaymp3)
		end
	end
	C.UnmapViewOfFile(buf)
end

local function DoInitScript()
	local startupinfo = ffi.new("STARTUPINFOA")
	local procinfo = ffi.new("PROCESS_INFORMATION")
	local fullpath = ffi.new("char[2048]")
	local mem
	if C.GetFullPathNameA("extensions/X4_ORS/radiostations/X4OwnRadioStationsPlayer.exe", 2048, fullpath, nil) ~= 0 then
		if C.CreateProcessA(fullpath, nil, nil, nil, 0, 0, nil, nil, ffi.cast("LPSTARTUPINFOA", startupinfo), ffi.cast("LPPROCESS_INFORMATION", procinfo)) ~= 0 then
			repeat
				mem = OpenMemFile()
				C.Sleep(10)
			until (mem ~= nil)
			-- Read EXE data
			initialized = false
			ProcessScriptMain(mem)
			C.CloseHandle(mem)
		else
			PrintError("Failed to run EXE, error: " .. tostring(C.GetLastError()))
			failed = true
		end
	else
		PrintError("Failed to get full path name to EXE!")
		failed = true
	end
	-- GC
	startupinfo = nil
	procinfo = nil
	fullpath = nil
end

local function DoProcess()
	if failed then
		return
	else
		local mem = OpenMemFile()
		if mem ~= nil then
			ProcessScriptMain(mem)
			C.CloseHandle(mem)
		else
			DoInitScript()
		end
	end
	if radioNameMenu.shown and (getElapsedTime() > (radioNameMenu.lastPopupTime + 5.0)) then
		hideRadioName()
	end
end

--[[
	************************************************************
	** Event Handlers (fired by MD script, regular intervals) **
	************************************************************
]]--

local function onTick(event, param)
	DoProcess()
end

local function onStartSpeak(event, param)
	musvol = musvol * 0.375 -- Lower volume
end

local function onEndSpeak(event, param)
	musvol = musvol / 0.375 -- Restore volume
	if (musvol > 100) then
		musvol = 100
	end
end

--[[
	************************************************************
	*********** Hooks for Music / Sfx menu handlers ************
	************************************************************
]]--

local function onRestoreDefaults()
	gameoptions.oldRestoreDefaultsFunc()
	__CORE_GAMEOPTIONS_RESTOREINFO.x4_ors_cached_bgvol = GetVolumeOption("music")
	if is_bg_mus_muted then
		SetVolumeOption("music", 0)
	end
	gameoptions.mastervolume = GetVolumeOption("master")
	gameoptions.issoundenabled = GetSoundOption()
end

local function onRestoreSfxDefaults()
	gameoptions.oldRestoreSfxDefaultsFunc()
	__CORE_GAMEOPTIONS_RESTOREINFO.x4_ors_cached_bgvol = GetVolumeOption("music")
	if is_bg_mus_muted then
		SetVolumeOption("music", 0)
	end
	gameoptions.mastervolume = GetVolumeOption("master")
	gameoptions.issoundenabled = GetSoundOption()
end

local function onGetSlider(sfxtype)
	local scale = gameoptions.oldGetSliderFunc(sfxtype)
	if (sfxtype == "music" and is_bg_mus_muted) then
		scale.start = Helper.round(__CORE_GAMEOPTIONS_RESTOREINFO.x4_ors_cached_bgvol * 100)
	end
	return scale
end

local function onSetSlider(sfxtype, value)
	if (sfxtype == "music") then
		__CORE_GAMEOPTIONS_RESTOREINFO.x4_ors_cached_bgvol = value / 100.0
		if is_bg_mus_muted then
			SetVolumeOption("music", 0)
		else
			SetVolumeOption("music", value / 100.0)
		end
	elseif (sfxtype == "master") then
		gameoptions.oldSetSliderFunc(sfxtype, value)
		gameoptions.mastervolume = value / 100.0
	else
		gameoptions.oldSetSliderFunc(sfxtype, value)
	end
end

local function onSetSound()
	gameoptions.oldSetSoundFunc()
	gameoptions.issoundenabled = GetSoundOption()
end

local function onDestroyOptionsMenu(obj)
	gameoptions.menu.callbackDefaults = gameoptions.oldRestoreDefaultsFunc
	gameoptions.menu.callbackSfxDefaults = gameoptions.oldRestoreSfxDefaultsFunc
	gameoptions.menu.valueSfxSetting = gameoptions.oldGetSliderFunc 
	gameoptions.menu.callbackSfxSetting = gameoptions.oldSetSliderFunc
	gameoptions.menu.callbackSfxSound = gameoptions.oldSetSoundFunc
	
	-- Set bg music back to original value
	SetVolumeOption("music", __CORE_GAMEOPTIONS_RESTOREINFO.x4_ors_cached_bgvol)
	is_bg_mus_muted = false
end

--[[
	************************************************************
	*********************** Script Init ************************
	************************************************************
]]--

-- Copied from: https://stackoverflow.com/questions/55585619/why-is-the-userdata-object-added-to-tables-in-this-lua-5-1-gc-workaround
-- Updated to support LUA 5.2 (where there's no 'newproxy', but tables have valid '__gc' instead)
local function setmt__gc(t, mt)
	if (newproxy ~= nil) then
		local p = newproxy(true)
		getmetatable(p).__gc =
			function()
				mt.__gc(t)
			end
		t[p] = true
	end
	return setmetatable(t, mt)
end

local function init()
	initialized = false
	failed = false
	
	-- Show Radio Name callback registration
	topLevelMenu = snLib.Get_Egosoft_Menu ("TopLevelMenu")
	topLevelMenu.registerCallback("kHUD_add_HUD_tables", radioNameMenu.onCreateRadioNameMenu)
	
	-- Hook into SFX menu: to mutually exclude BG Mus / Radio, and to store SFX settings in vraiables, to avoid costly SFX setting query calls in the main process
	gameoptions = setmt__gc({}, {__gc = onDestroyOptionsMenu})
	gameoptions.menu = snLib.Get_Egosoft_Menu ("OptionsMenu")
	gameoptions.oldRestoreDefaultsFunc = gameoptions.menu.callbackDefaults
	gameoptions.menu.callbackDefaults = onRestoreDefaults
	gameoptions.oldRestoreSfxDefaultsFunc = gameoptions.menu.callbackSfxDefaults
	gameoptions.menu.callbackSfxDefaults = onRestoreSfxDefaults
	gameoptions.oldGetSliderFunc = gameoptions.menu.valueSfxSetting
	gameoptions.menu.valueSfxSetting = onGetSlider
	gameoptions.oldSetSliderFunc = gameoptions.menu.callbackSfxSetting
	gameoptions.menu.callbackSfxSetting = onSetSlider
	gameoptions.oldSetSoundFunc = gameoptions.menu.callbackSfxSound
	gameoptions.menu.callbackSfxSound = onSetSound
	
	-- Get the relevant sfx options
	gameoptions.mastervolume = GetVolumeOption("master")
	gameoptions.issoundenabled = GetSoundOption()
	__CORE_GAMEOPTIONS_RESTOREINFO = __CORE_GAMEOPTIONS_RESTOREINFO or {}
	if (__CORE_GAMEOPTIONS_RESTOREINFO.x4_ors_cached_bgvol == nil) then
		__CORE_GAMEOPTIONS_RESTOREINFO.x4_ors_cached_bgvol = GetVolumeOption("music")
	else
		SetVolumeOption("music", __CORE_GAMEOPTIONS_RESTOREINFO.x4_ors_cached_bgvol)
	end
	
	-- Register event handlers
	RegisterEvent("X4_ORS_Tick", onTick)
	RegisterEvent("X4_ORS_StartSpeak", onStartSpeak)
	RegisterEvent("X4_ORS_EndSpeak", onEndSpeak)
	
	-- First run
	DoProcess()
end

init() -- Start script
