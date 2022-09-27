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

local initialized = false
local failed = false
local buttonpressed = false

local maxlatency
local rsnames
local rsindex
local musvol
local keys

local function OpenMemFile()
	return C.OpenFileMappingA(C.FILE_MAP_ALL_ACCESS, 0, "jupiter_x4_ors_memory__main_shared_mem")
end

local function IsExeRunning()
	local mutexhandle = C.OpenMutexA(C.MUTEX_ALL_ACCESS, 0, "jupiter_x4_ors__program_instance")
	if (mutexhandle == nil) or (mutexhandle == 0) then
		return false
	else
		C.CloseHandle(mutexhandle)
		return true
	end
end

local function GetExeData(buf)
	-- Request data
	local request = "request"
	for i = 1, #request do
		buf[i - 1] = string.byte(request, i)
	end
	buf[#request] = 0 -- null-terminator
	
	-- EXE check
	if not IsExeRunning() then
		PrintError("[@Jupiter] GetExeData - EXE is not running!")
	else
		C.Sleep(10)
		repeat
			if not IsExeRunning() then
				failed = true
				PrintError("EXE crashed during request!")
				break
			end
			
			C.Sleep(10) -- must wait!
			
			-- Read the data
			if not failed then
				data = ""
				for i = 0, 262143 do
					if buf[i] == 0 then -- null-terminator
						break
					else
						data = data .. string.char(buf[i])
					end
				end
			end
		until (data:find("programdata") == 1)
		C.Sleep(10)
		
		-- Setup variables
		if not failed then
			data = trim1(string.sub(data, 12, #data)) -- cut off 'programdata'
			rsnames = {} -- New, empty list
			rsindex = -1
			musvol = 100
			keys = {}
			
			-- Tokebnize input data, and fill data structures
			local tok, tok2, tok3, currentToken, tokenName, tokenValue, tokenName2, tokenValue2
			repeat
				tok = data:find(string.char(10))
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
					elseif string.lower(tokenName) == "radio_station" then
						table.insert(rsnames, tokenValue)
					elseif string.lower(tokenName) == "key_binding" then
						tok3 = tokenValue:find(" ")
						if (tok3 == nil) then
							tok3 = tokenValue:find(string.char(9))
						end
						if (tok3 ~= nil) then
							tokenName2 = trim1(string.sub(tokenValue, 1, tok3 - 1))
							tokenValue2 = trim1(string.sub(tokenValue, tok3 + 1, #tokenValue))
							local keyindex = tonumber(tokenName2)
							local keyid = tonumber(tokenValue2)
							if (keyindex > 0) and (keyindex <= 7) then
								keys[keyindex] = keyid
								SetNPCBlackboard(ConvertStringTo64Bit(tostring(C.GetPlayerID())), "$x4_ors_currentkey_" .. tostring(keyindex), keyid)
							else
								PrintError("Invalid key binding found in EXE data. Index " .. tostring(keyindex) .. " is out of range!")
							end
						end
					end
				end
			until (tok == nil)
			
			-- Reset data in mem file (script can send data!)
			buf[0] = 0 
		end
	end
end

local function SendExeData(buf, isactivemenu, isdriving, isalive, isskipmp3, isreplaymp3, isreloadapp)
	local exefunction = ""
	local dataout = ""
	if isreplaymp3 then
		exefunction = "replay_mp3"
	elseif isskipmp3 then
		exefunction = "skip_mp3"
	elseif isreloadapp then
		exefunction = "reload"
	else
		exefunction = "gamedata"
		
		-- Current station index
		dataout = dataout .. string.char(10) .. "current_station_index: " .. tostring(rsindex)
		
		-- Music vol
		local localmusvol
		if gameoptions.issoundenabled then
			localmusvol = math.floor(musvol * gameoptions.mastervolume * __CORE_GAMEOPTIONS_RESTOREINFO.x4_ors_cached_bgvol)
		else
			localmusvol = 0
		end
		dataout = dataout .. string.char(10) .. " music_volume: " .. tostring(localmusvol)
		
		-- Is active menu
		if isactivemenu then
			dataout = dataout .. string.char(10) .. " is_active_menu: 1"
		else
			dataout = dataout .. string.char(10) .. " is_active_menu: 0"
		end
		
		-- Is driving
		if isdriving then
			dataout = dataout .. string.char(10) .. " is_driving: 1"
		else
			dataout = dataout .. string.char(10) .. " is_driving: 0"
		end
		
		-- Is alive
		if isalive then
			dataout = dataout .. string.char(10) .. " is_alive: 1"
		else
			dataout = dataout .. string.char(10) .. " is_alive: 0"
		end
		
		-- What we need... We only query faction data, if we are eligible to listen to the music
		if isactivemenu and isdriving and isalive and (localmusvol > 0) and (rsindex >= 0) then
			-- Faction data
			local numFactions = C.GetNumAllFactions(true)
			local factionNames = ffi.new("const char*[?]", numFactions)
			numFactions = C.GetAllFactions(factionNames, numFactions, true)
			
			local plyr = ffi.cast("UniverseID", C.GetPlayerID())
			
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
					if (numCurrFactStations > 0) then
						dataout = dataout .. string.char(10) .. " faction_station: " .. currFactionName .. " " .. tostring(mindist)
					end
				end
			end
		end
	end
	
	-- First, write the meaningful data
	buf[0] = 0
	buf[#exefunction] = 10
	buf[#exefunction + #dataout + 1] = 0
	for i = 1, #dataout do
		buf[i + #exefunction] = string.byte(dataout, i)
	end
	
	-- Then, write the EXE function identifier
	for i = 1, #exefunction do
		buf[i - 1] = string.byte(exefunction, i)
	end
	
	-- If we've triggered the app to reload, force the script top request data from it, again
	if isreloadapp then
		initialized = false
	end
end

--[[
	************************************************************
	******************* Script Main Process ********************
	************************************************************
]]--

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
		local isreplaymp3 = false
		local isskipmp3 = false
		local isreloadapp = false
		
		if isactivemenu and isdriving and isalive then		
			-- Only react to radio changer keys, if we're full ok
			if (keys ~= nil) then
				local mk1state, mk2state, doprevstation, donextstation, doreplaymp3, doskipmp3, doreloadapp
				if (keys[1] ~= nil) and (keys[1] ~= 0) then
					mk1state = (bit.band(C.GetAsyncKeyState(keys[1]), 0x8000) ~= 0)
				else
					mk1state = true
				end
				if (keys[2] ~= nil) and (keys[2] ~= 0) then
					mk2state = (bit.band(C.GetAsyncKeyState(keys[2]), 0x8000) ~= 0)
				else
					mk2state = true
				end
				if mk1state and mk2state then
					if (keys[3] ~= nil) and (keys[3] ~= 0) then
						doprevstation = (bit.band(C.GetAsyncKeyState(keys[3]), 0x8000) ~= 0)
					else
						doprevstation = false
					end
					if (keys[4] ~= nil) and (keys[4] ~= 0) then
						donextstation = (bit.band(C.GetAsyncKeyState(keys[4]), 0x8000) ~= 0)
					else
						donextstation = false
					end
					if (keys[5] ~= nil) and (keys[5] ~= 0) then
						doreplaymp3 = (bit.band(C.GetAsyncKeyState(keys[5]), 0x8000) ~= 0)
					else
						doreplaymp3 = false
					end
					if (keys[6] ~= nil) and (keys[6] ~= 0) then
						doskipmp3 = (bit.band(C.GetAsyncKeyState(keys[6]), 0x8000) ~= 0)
					else
						doskipmp3 = false
					end
					if (keys[7] ~= nil) and (keys[7] ~= 0) then
						doreloadapp = (bit.band(C.GetAsyncKeyState(keys[7]), 0x8000) ~= 0)
					else
						doreloadapp = false
					end
					
					if doprevstation or donextstation or doreplaymp3 or doskipmp3 or doreloadapp then
						-- Prevent the script from detecting a long keypress as multiple keypresses...
						if (buttonpressed == nil) or (not buttonpressed) then
							buttonpressed = true
							
							local previndex = rsindex
							local radiotext
							
							-- Key function implemantation
							if doprevstation then
								rsindex = rsindex - 1
							elseif donextstation then
								rsindex = rsindex + 1
							elseif doreplaymp3 then
								isreplaymp3 = true
							elseif doskipmp3 then
								isskipmp3 = true
							elseif doreloadapp then
								isreloadapp = true
							end
							
							-- Rs index is bounded, show radio name, if changed
							if (rsindex ~= previndex) then
								if (rsindex < -1) then
									rsindex = #rsnames - 1
								elseif (rsindex == #rsnames) then
									rsindex = -1
								end
								if (rsindex < 0) or (rsindex >= #rsnames) then
									radiotext = "\027[faction_ownerless]\027X"
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
			end
				
			-- Keep background music muted, if we're full OK, and radio is on too
			HandleBgMusVol(rsindex < 0)
		else
			-- Restore background music, if we're  not OK
			HandleBgMusVol(true)
		end
		
		-- Send the data, if both the EXE, and WE are ready to send that data...
		if (buf[0] == 0) then
			SendExeData(buf, isactivemenu, isdriving, isalive, isskipmp3, isreplaymp3, isreloadapp)
		end
	end
	C.UnmapViewOfFile(buf)
end

local function DoInitExe()
	local startupinfo = ffi.new("STARTUPINFOA")
	local procinfo = ffi.new("PROCESS_INFORMATION")
	local fullpath = ffi.new("char[2048]")
	local cmdline = ffi.new("char[2048]")
	local mem
	if C.GetFullPathNameA("extensions/X4_ORS/radiostations/X4OwnRadioStationsPlayer.exe", 2048, fullpath, nil) ~= 0 then
		if C.CreateProcessA(fullpath, nil, nil, nil, 0, 0, nil, nil, ffi.cast("LPSTARTUPINFOA", startupinfo), ffi.cast("LPPROCESS_INFORMATION", procinfo)) ~= 0 then
			repeat
				C.Sleep(10)
			until IsExeRunning()
			repeat
				if not IsExeRunning() then
					PrintError("Failed to initialize EXE!")
					failed = true
					break
				else
					mem = OpenMemFile()
				end
				C.Sleep(10)
			until (mem ~= nil)
			
			-- Init
			initialized = false
			if not failed then
				ProcessScriptMain(mem)
				C.CloseHandle(mem)
			end
		else
			PrintError("Failed to create process, error code: " .. tostring(C.GetLastError()))
			failed = true
		end
	else
		PrintError("Failed to get full path to EXE, error code: " .. tostring(C.GetLastError()))
		failed = true
	end
	
	-- GC
	startupinfo = nil
	procinfo = nil
	fullpath = nil
	cmdline = nil
end

local function DoProcess()
	if failed then
		HandleBgMusVol(true)
		return
	elseif not IsExeRunning() then
		DoInitExe()
	else
		local mem = OpenMemFile()
		ProcessScriptMain(mem)
		C.CloseHandle(mem)
	end
	if radioNameMenu.shown and (getElapsedTime() > (radioNameMenu.lastPopupTime + 5.0)) then
		hideRadioName()
	end
end

--[[
	************************************************************
	** Event Handlers (fired by MD script)                    **
	************************************************************
]]--

local function onTick(_, param)
	DoProcess()
end

local function onStartSpeak(_, param)
	musvol = musvol * 0.375 -- Lower volume
end

local function onEndSpeak(_, param)
	musvol = musvol / 0.375 -- Restore volume
	if (musvol > 100) then
		musvol = 100
	end
end

local function onChangeKeyBinding(_, param)
	if (not failed) and IsExeRunning() and initialized then
		local mem = OpenMemFile()
		if (mem ~= nil) then
			local buf = ffi.cast("LPBYTE", C.MapViewOfFile(mem, C.FILE_MAP_ALL_ACCESS, 0, 0, 262144))
			
			-- Get the index and value from MD
			local keyindex = GetNPCBlackboard(ConvertStringTo64Bit(tostring(C.GetPlayerID())), "$x4_ors_setkey_keyindex")
			local newkey = GetNPCBlackboard(ConvertStringTo64Bit(tostring(C.GetPlayerID())), "$x4_ors_setkey_vkey")
			
			-- Save the values to script and MD
			SetNPCBlackboard(ConvertStringTo64Bit(tostring(C.GetPlayerID())), "$x4_ors_currentkey_" .. tostring(keyindex), newkey)
			keys[keyindex] = newkey
			
			-- Save the values to INI via EXE
			local dataout = "set_key" .. string.char(10) .. tostring(keyindex) .. ":" .. tostring(newkey)
			for i = 1, #dataout do
				buf[i - 1] = string.byte(dataout, i)
			end
			buf[#dataout] = 0
			C.UnmapViewOfFile(buf)
		end
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
	RegisterEvent("X4_ORS_ChangeKeyBinding", onChangeKeyBinding)
	
	-- First run
	DoProcess()
end

init() -- Start script
