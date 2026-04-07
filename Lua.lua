local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")

local LP = Players.LocalPlayer

-- Orbit / Void keyboard toggles (nil = unbound; change via UI "키" buttons)
local KEYBIND_ORBIT_TOGGLE = Enum.KeyCode.F6
local KEYBIND_VOID_TOGGLE = Enum.KeyCode.F7
local keybindCaptureMode = nil -- "orbit" | "void" while waiting for a key
local keybindHotkeysEnabled = true -- master switch for Orbit/Void hotkeys
local KEY_STATUS_DOWN = Color3.fromRGB(40, 175, 85)
local KEY_STATUS_UP = Color3.fromRGB(185, 50, 55)
local KEY_STATUS_NONE = Color3.fromRGB(70, 70, 82)

local function keyCodeFromName(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    for _, kc in pairs(Enum.KeyCode:GetEnumItems()) do
        if kc.Name == name then
            return kc
        end
    end
    return nil
end

local function orbitBtnLabel(on)
    local s = on and "ON" or "OFF"
    if KEYBIND_ORBIT_TOGGLE then
        return "Orbit: " .. s .. " [" .. KEYBIND_ORBIT_TOGGLE.Name .. "]"
    end
    return "Orbit: " .. s
end

local function voidBtnLabel(on)
    local s = on and "ON" or "OFF"
    if KEYBIND_VOID_TOGGLE then
        return "Void: " .. s .. " [" .. KEYBIND_VOID_TOGGLE.Name .. "]"
    end
    return "Void: " .. s
end

-- Orbit/Rage state
local orbitEnabled = false
local orbitConn = nil
local orbitAngle = 0
local orbitSpeed = 140 -- slider default (max on slider is higher)
local tpInterval = 0.018 -- seconds between orbit TP steps (smaller = faster)
local tpRadius = 6 -- studs
local tpAccumulator = 0
local orbitPatternIndex = 1
local orbitPatterns = {"Circle", "Random", "Star", "Figure8", "Ellipse", "Square", "Mixer", "Random spot"}
local orbitPatternNamesKo = nil
local rageBurstHits = 2
local selectedTargetName = ""

local voidEnabled = false
local voidThread = nil
local voidHideTime = 0.65
local voidAttackTime = 0.35
local voidDistanceStuds = 200000000
local voidAnchorPos = nil

-- InVoid removed
local inVoidEnabled = false
local inVoidThread = nil
-- NOTE: extremely large coordinates (e.g. 1e9) often get clamped / desynced / rejected.
-- keep this at a safer scale similar to Void.
local inVoidDistanceStuds = 200000000

local espEnabled = false
local espConn = nil
local espPool = {}

-- Executor workspace (Synapse/Krnl 등): Ice Lua/config 아래에 저장
local SETTINGS_REL_DIR = "Ice Lua/config"
local SETTINGS_FILENAME = "Simple_Draggable_Toggle_UI_Config.json"
local SETTINGS_FILE = SETTINGS_REL_DIR .. "/" .. SETTINGS_FILENAME
-- 예전 버전: 워크스페이스 루트에만 있던 파일 (로드 폴백)
local SETTINGS_FILE_LEGACY = SETTINGS_FILENAME
-- When readfile/writefile is missing or fails, same JSON is kept here (same executor session / some teleports).
local SETTINGS_MEM_KEY = "__SimpleDraggableToggleUI_ConfigJSON"

local function configWriteMemory(json)
    if type(json) ~= "string" or json == "" then
        return false
    end
    local any = false
    pcall(function()
        if typeof(getgenv) == "function" then
            local ok, g = pcall(getgenv)
            if ok and type(g) == "table" then
                g[SETTINGS_MEM_KEY] = json
                any = true
            end
        end
    end)
    pcall(function()
        if type(shared) == "table" then
            shared[SETTINGS_MEM_KEY] = json
            any = true
        end
    end)
    return any
end

local function configReadMemory()
    local s
    pcall(function()
        if typeof(getgenv) == "function" then
            local ok, g = pcall(getgenv)
            if ok and type(g) == "table" then
                local v = g[SETTINGS_MEM_KEY]
                if type(v) == "string" and v ~= "" then
                    s = v
                end
            end
        end
    end)
    if s then
        return s
    end
    pcall(function()
        if type(shared) == "table" then
            local v = shared[SETTINGS_MEM_KEY]
            if type(v) == "string" and v ~= "" then
                s = v
            end
        end
    end)
    return s
end

-- forward declarations
local getSelectedTargetPlayer
local isAntiAimActive
local getMyHRP
-- NoBody removed
local startNoBodyAttack, stopNoBodyAttack
local function getMyHumanoid()
    local ch = LP.Character
    if not ch then return nil end
    return ch:FindFirstChildOfClass("Humanoid")
end

-- define early to avoid nil during early calls
local function getMyHRP()
    local ch = LP.Character
    if not ch then return nil end
    return ch:FindFirstChild("HumanoidRootPart")
end

-- Anti-Aim state
local aaPitchMode = "Off" -- Off | UpsideDown | BackHead | NoHead | Jitter | ZeroG | Sway | Nod | Shake | WavePitch | Bounce | SpiralPitch | Pulse | RandomStep | MicroJitter | TiltLeft | TiltRight
local aaSpinOn = false
local aaSpinSpeed = 12
local aaRollOn = false
local aaRollSpeed = 20
local aaConn = nil
local aaBindKey = "AA_Run_" .. tostring(LP.UserId)
local aaAutoRotConn = nil
local aaJoints = { neck = nil, waist = nil }
local aaBase = { neckC0 = nil, waistC0 = nil }
local aaSpecialMode = "Off" -- Off | Forward | Backward | Chaos
local aaIgnoreAC = false
local aaHardMode = false
local aaSteppedConn = nil
local aaLastRot = CFrame.new()
local aaAnimateScript = nil
local aaAnimateWasEnabled = nil

-- Drone removed
local droneEnabled = false
local droneConn = nil
local droneParts = {}
local dronePanel -- forward

-- TP (go under target) state
local tp2Enabled = false
local tp2Conn = nil
local tp2Radius = 8 -- circle radius around target (studs)
local tp2Height = -8 -- vertical offset: up(+)/down(-) relative to target
local tp2Speed = 18 -- angular speed / follow smoothness
local tpPanel -- forward

-- Moving (무빙) state
local mvPanel -- forward
local mvTabBtn -- forward
local mvEnabled = false
local mvConn = nil
local mvCrouchSpamOn = false
local mvCrouchTempo = 0.26 -- seconds half-cycle
local mvCrouchDepth = 0.9 -- studs hipheight delta
local mvBaseHipHeight = nil
local mvJoints = { waist = nil, neck = nil, lHip = nil, rHip = nil, lKnee = nil, rKnee = nil }
local mvBaseC0 = { waist = nil, neck = nil, lHip = nil, rHip = nil, lKnee = nil, rKnee = nil }

-- NoBody Attack removed
local nbaPanel -- forward
local nbaTabBtn -- forward
local nbaEnabled = false
local nbaThread = nil
local nbaHoldMs = 30 -- dwell at target in ms
local nbaRepeat = 3 -- clicks per cycle
local nbaPeriodMs = 120 -- cycle period

local function captureMVJoints()
	-- cache joints for visual crouch (no body lowering)
	for k in pairs(mvJoints) do mvJoints[k] = nil; mvBaseC0[k] = nil end
	local ch = LP.Character
	if not ch then return end
	local upper = ch:FindFirstChild("UpperTorso")
	local lower = ch:FindFirstChild("LowerTorso")
	local head = ch:FindFirstChild("Head")
	if upper then
		for _,m in ipairs(upper:GetChildren()) do
			if m:IsA("Motor6D") and m.Name == "Waist" then
				mvJoints.waist = m; mvBaseC0.waist = m.C0
			end
		end
	end
	if upper and head then
		local neck = upper:FindFirstChild("Neck") or head:FindFirstChild("Neck")
		if not neck then
			for _,m in ipairs(upper:GetChildren()) do
				if m:IsA("Motor6D") and m.Part1 == head then neck = m break end
			end
		end
		if neck then mvJoints.neck = neck; mvBaseC0.neck = neck.C0 end
	end
	-- Hips/Knees (R15)
	local function findMotor(parent, name)
		return parent and parent:FindFirstChild(name)
	end
	local rl = ch:FindFirstChild("RightUpperLeg")
	local ll = ch:FindFirstChild("LeftUpperLeg")
	if lower then
		mvJoints.rHip = findMotor(lower, "RightHip") or (rl and rl:FindFirstChildOfClass("Motor6D"))
		mvJoints.lHip = findMotor(lower, "LeftHip") or (ll and ll:FindFirstChildOfClass("Motor6D"))
	end
	if mvJoints.rHip then mvBaseC0.rHip = mvJoints.rHip.C0 end
	if mvJoints.lHip then mvBaseC0.lHip = mvJoints.lHip.C0 end
	-- Knees are on UpperLegs
	if rl then
		for _,m in ipairs(rl:GetChildren()) do
			if m:IsA("Motor6D") and m.Name:find("Knee") then mvJoints.rKnee = m; mvBaseC0.rKnee = m.C0 end
		end
	end
	if ll then
		for _,m in ipairs(ll:GetChildren()) do
			if m:IsA("Motor6D") and m.Name:find("Knee") then mvJoints.lKnee = m; mvBaseC0.lKnee = m.C0 end
		end
	end
end


local aaHeadState = {
    mesh = nil,
    meshOrigScale = nil,
    head = nil,
    saved = {}, -- {instance -> number(LocalTransparencyModifier)}
}

local function stopAntiAim()
    if aaConn then aaConn:Disconnect(); aaConn = nil end
    pcall(function() RunService:UnbindFromRenderStep(aaBindKey) end)
    if aaAutoRotConn then aaAutoRotConn:Disconnect(); aaAutoRotConn = nil end
    if aaSteppedConn then aaSteppedConn:Disconnect(); aaSteppedConn = nil end
    local hum = getMyHumanoid()
    local hrp = getMyHRP()
    if hum then
        pcall(function() hum.AutoRotate = true end)
    end
    -- Restore neck and head visual changes
    if aaJoints.neck and aaBase.neckC0 then
        pcall(function() aaJoints.neck.C0 = aaBase.neckC0 end)
    end
    if aaJoints.waist and aaBase.waistC0 then
        pcall(function() aaJoints.waist.C0 = aaBase.waistC0 end)
    end
    if aaHeadState then
        -- restore transparency modifiers
        for inst, val in pairs(aaHeadState.saved) do
            pcall(function()
                if inst and inst.Parent then
                    inst.LocalTransparencyModifier = val or 0
                end
            end)
        end
        aaHeadState.saved = {}
        -- restore mesh scale
        if aaHeadState.mesh and aaHeadState.meshOrigScale then
            pcall(function() aaHeadState.mesh.Scale = aaHeadState.meshOrigScale end)
        end
        aaHeadState.mesh = nil
        aaHeadState.meshOrigScale = nil
        aaHeadState.head = nil
    end
    -- Re-enable Animate script if we disabled it
    if aaAnimateScript and aaAnimateScript.Parent then
        pcall(function()
            if aaAnimateWasEnabled ~= nil then
                aaAnimateScript.Disabled = not aaAnimateWasEnabled
            else
                aaAnimateScript.Disabled = false
            end
        end)
    end
    aaAnimateScript = nil
    aaAnimateWasEnabled = nil
    if hum and hrp then
        pcall(function()
            local pos = hrp.Position
            local md = hum.MoveDirection
            if md and md.Magnitude > 0.1 then
                local look = Vector3.new(md.X, 0, md.Z).Unit
                hrp.CFrame = CFrame.new(pos, pos + look)
            end
            hrp.AssemblyAngularVelocity = Vector3.zero
        end)
    end
end

local function hasFileAPI()
    return type(readfile) == "function" and type(writefile) == "function" and type(isfile) == "function"
end

local function ensureIceLuaConfigDir()
    pcall(function()
        if type(isfolder) ~= "function" or type(makefolder) ~= "function" then
            return
        end
        if not isfolder("Ice Lua") then
            makefolder("Ice Lua")
        end
        if not isfolder(SETTINGS_REL_DIR) then
            makefolder(SETTINGS_REL_DIR)
        end
    end)
end

local function readFileIfExists(path)
    local ok, r = pcall(function()
        if isfile(path) then
            return readfile(path)
        end
        return nil
    end)
    if ok and type(r) == "string" and r ~= "" then
        return r
    end
    local ok2, r2 = pcall(function()
        return readfile(path)
    end)
    if ok2 and type(r2) == "string" and r2 ~= "" then
        return r2
    end
    return nil
end

local function writeSettings(tbl)
    local encOk, json = pcall(function()
        return HttpService:JSONEncode(tbl)
    end)
    if not encOk or type(json) ~= "string" or json == "" then
        return false
    end
    local diskOk = false
    if hasFileAPI() then
        ensureIceLuaConfigDir()
        diskOk = pcall(function()
            if isfile(SETTINGS_FILE) and type(delfile) == "function" then
                pcall(delfile, SETTINGS_FILE)
            end
            writefile(SETTINGS_FILE, json)
        end)
    end
    local memOk = configWriteMemory(json)
    return diskOk or memOk, diskOk
end

local function readSettings()
    local raw
    if hasFileAPI() then
        raw = readFileIfExists(SETTINGS_FILE)
        if not raw and SETTINGS_FILE_LEGACY ~= SETTINGS_FILE then
            raw = readFileIfExists(SETTINGS_FILE_LEGACY)
        end
    end
    if not raw then
        raw = configReadMemory()
    end
    if not raw then
        return nil
    end
    local ok, result = pcall(function()
        return HttpService:JSONDecode(raw)
    end)
    if ok and type(result) == "table" then
        pcall(function()
            configWriteMemory(raw)
        end)
        return result
    end
    return nil
end

local gui = Instance.new("ScreenGui")
gui.Name = "SimpleDraggableToggleUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999

pcall(function()
    gui.Parent = game:GetService("CoreGui")
end)
if not gui.Parent then
    gui.Parent = LP:WaitForChild("PlayerGui")
end
pcall(function() gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling end)

-- Main draggable UI
local main = Instance.new("Frame")
main.Name = "MainUI"
main.Parent = gui
main.Size = UDim2.new(0, 340, 0, 834)
main.Position = UDim2.new(0.5, -140, 0.5, -120)
main.BackgroundColor3 = Color3.fromRGB(28, 28, 35)
main.BorderSizePixel = 1
main.BorderColor3 = Color3.fromRGB(80, 80, 100)
main.Active = true
main.ClipsDescendants = false

-- (removed UI scale)

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = main

local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Parent = main
topBar.Size = UDim2.new(1, 0, 0, 32)
topBar.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
topBar.BorderSizePixel = 0

local topCorner = Instance.new("UICorner")
topCorner.CornerRadius = UDim.new(0, 8)
topCorner.Parent = topBar

local title = Instance.new("TextLabel")
title.Parent = topBar
title.Size = UDim2.new(1, -10, 1, 0)
title.Position = UDim2.new(0, 10, 0, 0)
title.BackgroundTransparency = 1
title.Text = "Draggable UI"
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(235, 235, 245)
title.Font = Enum.Font.GothamBold
title.TextSize = 13

-- Anti-Aim Tab toggle button (in title bar)
local aaTabBtn = Instance.new("TextButton")
aaTabBtn.Parent = topBar
aaTabBtn.Size = UDim2.new(0, 90, 0, 20)
aaTabBtn.Position = UDim2.new(1, -96, 0.5, -10)
aaTabBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
aaTabBtn.BorderSizePixel = 0
aaTabBtn.TextColor3 = Color3.fromRGB(230, 230, 245)
aaTabBtn.Font = Enum.Font.Gotham
aaTabBtn.TextSize = 11
aaTabBtn.Text = "Anti-Aim"
Instance.new("UICorner", aaTabBtn).CornerRadius = UDim.new(0, 6)
aaTabBtn.ZIndex = 60

-- Drone Tab removed

-- Moving Tab toggle button (in title bar)
mvTabBtn = Instance.new("TextButton")
mvTabBtn.Parent = topBar
mvTabBtn.Size = UDim2.new(0, 72, 0, 20)
mvTabBtn.Position = UDim2.new(1, -246, 0.5, -10)
mvTabBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
mvTabBtn.BorderSizePixel = 0
mvTabBtn.TextColor3 = Color3.fromRGB(230, 230, 245)
mvTabBtn.Font = Enum.Font.Gotham
mvTabBtn.TextSize = 11
mvTabBtn.Text = "Moving"
Instance.new("UICorner", mvTabBtn).CornerRadius = UDim.new(0, 6)
mvTabBtn.ZIndex = 60
-- Disable Moving feature (hidden from UI)
mvTabBtn.Visible = false

-- NoBody Tab removed
-- Animation Tab toggle button
-- (Animation Tab removed)

-- TP Tab toggle button (in title bar)
local tpTabBtn = Instance.new("TextButton")
tpTabBtn.Parent = topBar
tpTabBtn.Size = UDim2.new(0, 50, 0, 20)
tpTabBtn.Position = UDim2.new(1, -356, 0.5, -10)
tpTabBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
tpTabBtn.BorderSizePixel = 0
tpTabBtn.TextColor3 = Color3.fromRGB(230, 230, 245)
tpTabBtn.Font = Enum.Font.Gotham
tpTabBtn.TextSize = 11
tpTabBtn.Text = "TP"
Instance.new("UICorner", tpTabBtn).CornerRadius = UDim.new(0, 6)
tpTabBtn.ZIndex = 60

local bodyText = Instance.new("TextLabel")
bodyText.Parent = main
bodyText.Size = UDim2.new(1, -16, 0, 34)
bodyText.Position = UDim2.new(0, 8, 0, 40)
bodyText.BackgroundTransparency = 1
bodyText.TextWrapped = true
bodyText.TextXAlignment = Enum.TextXAlignment.Left
bodyText.TextYAlignment = Enum.TextYAlignment.Top
bodyText.TextColor3 = Color3.fromRGB(200, 200, 215)
bodyText.Font = Enum.Font.Gotham
bodyText.TextSize = 12
bodyText.Text = "Draggable | Toggle Orbit/Rage"

-- Orbit toggle (keys: left "키바인드" panel)
local orbitBtn = Instance.new("TextButton")
orbitBtn.Name = "OrbitToggleButton"
orbitBtn.Parent = main
orbitBtn.Size = UDim2.new(0, 180, 0, 34)
orbitBtn.Position = UDim2.new(0.5, -90, 0, 102)
orbitBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 78)
orbitBtn.BorderSizePixel = 0
orbitBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
orbitBtn.Font = Enum.Font.GothamBold
orbitBtn.TextSize = 12
orbitBtn.Text = orbitBtnLabel(false)

local orbitCorner = Instance.new("UICorner")
orbitCorner.CornerRadius = UDim.new(0, 8)
orbitCorner.Parent = orbitBtn

local orbitPatternBtn = Instance.new("TextButton")
orbitPatternBtn.Parent = main
orbitPatternBtn.Size = UDim2.new(1, -20, 0, 24)
orbitPatternBtn.Position = UDim2.new(0, 10, 0, 138)
orbitPatternBtn.BackgroundColor3 = Color3.fromRGB(52, 52, 70)
orbitPatternBtn.BorderSizePixel = 0
orbitPatternBtn.TextColor3 = Color3.fromRGB(235, 235, 245)
orbitPatternBtn.Font = Enum.Font.Gotham
orbitPatternBtn.TextSize = 11
orbitPatternBtn.Text = "Orbit Pattern: " .. (orbitPatterns[orbitPatternIndex])
Instance.new("UICorner", orbitPatternBtn).CornerRadius = UDim.new(0, 6)

local function createSlider(parent, y, titleText, minV, maxV, startV, decimals, onChanged)
    local holder = Instance.new("Frame")
    holder.Parent = parent
    holder.Size = UDim2.new(1, -20, 0, 50)
    holder.Position = UDim2.new(0, 10, 0, y)
    holder.BackgroundTransparency = 1

    local title = Instance.new("TextLabel")
    title.Parent = holder
    title.Size = UDim2.new(1, -86, 0, 16)
    title.BackgroundTransparency = 1
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = Color3.fromRGB(220, 220, 235)
    title.Font = Enum.Font.Gotham
    title.TextSize = 12

    local valueBox = Instance.new("TextBox")
    valueBox.Parent = holder
    valueBox.Size = UDim2.new(0, 80, 0, 18)
    valueBox.Position = UDim2.new(1, -80, 0, 0)
    valueBox.BackgroundColor3 = Color3.fromRGB(48, 48, 62)
    valueBox.BorderSizePixel = 0
    valueBox.TextColor3 = Color3.fromRGB(240, 240, 248)
    valueBox.Font = Enum.Font.Gotham
    valueBox.TextSize = 11
    valueBox.ClearTextOnFocus = false
    valueBox.Text = ""
    Instance.new("UICorner", valueBox).CornerRadius = UDim.new(0, 5)

    local track = Instance.new("TextButton")
    track.Parent = holder
    track.Size = UDim2.new(1, 0, 0, 10)
    track.Position = UDim2.new(0, 0, 0, 30)
    track.Text = ""
    track.AutoButtonColor = false
    track.BackgroundColor3 = Color3.fromRGB(60, 60, 76)
    track.BorderSizePixel = 0
    Instance.new("UICorner", track).CornerRadius = UDim.new(0, 5)

    local fill = Instance.new("Frame")
    fill.Parent = track
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(110, 85, 220)
    fill.BorderSizePixel = 0
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 5)

    local draggingSlider = false
    local value = startV
    local editingBox = false

    local function fmt(v)
        if decimals <= 0 then return tostring(math.floor(v + 0.5)) end
        local p = 10 ^ decimals
        return tostring(math.floor(v * p + 0.5) / p)
    end

    local function setValue(v)
        value = math.clamp(v, minV, maxV)
        local alpha = (value - minV) / (maxV - minV)
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        title.Text = titleText .. ": " .. fmt(value)
        if not editingBox then
            valueBox.Text = fmt(value)
        end
        if onChanged then onChanged(value) end
    end

    local function setFromX(x)
        local alpha = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
        setValue(minV + (maxV - minV) * alpha)
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = true
            setFromX(input.Position.X)
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if not draggingSlider then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            setFromX(input.Position.X)
        end
    end)

    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = false
        end
    end)

    valueBox.Focused:Connect(function()
        editingBox = true
    end)

    valueBox.FocusLost:Connect(function()
        editingBox = false
        local num = tonumber(valueBox.Text)
        if num then
            setValue(num)
        else
            valueBox.Text = fmt(value)
        end
    end)

    setValue(startV)
    return {
        setValue = setValue,
        getValue = function() return value end,
    }
end

-- (removed UI Scale slider)

local speedSlider = createSlider(main, 168, "Orbit Speed", 1, 4500, orbitSpeed, 0, function(v)
    orbitSpeed = math.floor(v + 0.5)
end)

local distanceSlider = createSlider(main, 218, "Orbit Distance", 2, 700000, tpRadius, 0, function(v)
    tpRadius = v
end)

local intervalSlider = createSlider(main, 268, "Orbit TP Time", 0.0002, 1.5, tpInterval, 4, function(v)
    tpInterval = v
end)

-- Target select UI (player list)
local targetLabel = Instance.new("TextLabel")
targetLabel.Parent = main
targetLabel.Size = UDim2.new(1, -20, 0, 18)
targetLabel.Position = UDim2.new(0, 10, 0, 322)
targetLabel.BackgroundTransparency = 1
targetLabel.TextColor3 = Color3.fromRGB(220, 220, 235)
targetLabel.Font = Enum.Font.Gotham
targetLabel.TextSize = 12
targetLabel.TextXAlignment = Enum.TextXAlignment.Left
targetLabel.Text = "Target: None"

local refreshTargetBtn = Instance.new("TextButton")
refreshTargetBtn.Parent = main
refreshTargetBtn.Size = UDim2.new(1, -20, 0, 24)
refreshTargetBtn.Position = UDim2.new(0, 10, 0, 342)
refreshTargetBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
refreshTargetBtn.BorderSizePixel = 0
refreshTargetBtn.TextColor3 = Color3.fromRGB(230, 230, 245)
refreshTargetBtn.Font = Enum.Font.Gotham
refreshTargetBtn.TextSize = 11
refreshTargetBtn.Text = "Refresh Player List"
Instance.new("UICorner", refreshTargetBtn).CornerRadius = UDim.new(0, 6)

local playerListFrame = Instance.new("ScrollingFrame")
playerListFrame.Parent = main
playerListFrame.Size = UDim2.new(1, -20, 0, 88)
playerListFrame.Position = UDim2.new(0, 10, 0, 370)
playerListFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 48)
playerListFrame.BorderSizePixel = 0
playerListFrame.ScrollBarThickness = 4
playerListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
playerListFrame.AutomaticCanvasSize = Enum.AutomaticSize.None
Instance.new("UICorner", playerListFrame).CornerRadius = UDim.new(0, 6)

local listLayout = Instance.new("UIListLayout")
listLayout.Parent = playerListFrame
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 4)

-- Rage UI removed

-- Void UI
local voidBtn = Instance.new("TextButton")
voidBtn.Parent = main
voidBtn.Size = UDim2.new(1, -20, 0, 30)
voidBtn.Position = UDim2.new(0, 10, 0, 508)
voidBtn.BackgroundColor3 = Color3.fromRGB(42, 62, 96)
voidBtn.BorderSizePixel = 0
voidBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
voidBtn.Font = Enum.Font.GothamBold
voidBtn.TextSize = 12
voidBtn.Text = voidBtnLabel(false)
Instance.new("UICorner", voidBtn).CornerRadius = UDim.new(0, 6)

-- Left keybind list (follows main when dragged); green = key held, red = not held
local keybindSidebar = Instance.new("Frame")
keybindSidebar.Name = "KeybindSidebar"
keybindSidebar.Parent = main
keybindSidebar.ZIndex = 8
keybindSidebar.Size = UDim2.new(0, 120, 0, 178)
keybindSidebar.Position = UDim2.new(0, -128, 0, 70)
keybindSidebar.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
keybindSidebar.BorderSizePixel = 1
keybindSidebar.BorderColor3 = Color3.fromRGB(65, 65, 88)
Instance.new("UICorner", keybindSidebar).CornerRadius = UDim.new(0, 8)

local ksTitle = Instance.new("TextLabel")
ksTitle.Parent = keybindSidebar
ksTitle.Size = UDim2.new(1, -8, 0, 14)
ksTitle.Position = UDim2.new(0, 4, 0, 6)
ksTitle.BackgroundTransparency = 1
ksTitle.Font = Enum.Font.GothamBold
ksTitle.TextSize = 11
ksTitle.TextColor3 = Color3.fromRGB(210, 210, 225)
ksTitle.TextXAlignment = Enum.TextXAlignment.Left
ksTitle.Text = "키바인드"

local keybindMasterBtn = Instance.new("TextButton")
keybindMasterBtn.Parent = keybindSidebar
keybindMasterBtn.Size = UDim2.new(1, -8, 0, 22)
keybindMasterBtn.Position = UDim2.new(0, 4, 0, 22)
keybindMasterBtn.BackgroundColor3 = Color3.fromRGB(48, 52, 68)
keybindMasterBtn.BorderSizePixel = 0
keybindMasterBtn.TextColor3 = Color3.fromRGB(235, 235, 245)
keybindMasterBtn.Font = Enum.Font.Gotham
keybindMasterBtn.TextSize = 10
keybindMasterBtn.Text = "단축키: ON"
Instance.new("UICorner", keybindMasterBtn).CornerRadius = UDim.new(0, 5)

local function makeKeyRow(y, labelText)
    local lbl = Instance.new("TextLabel")
    lbl.Parent = keybindSidebar
    lbl.Size = UDim2.new(0, 38, 0, 18)
    lbl.Position = UDim2.new(0, 4, 0, y)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 10
    lbl.TextColor3 = Color3.fromRGB(180, 180, 195)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = labelText

    local pick = Instance.new("TextButton")
    pick.Parent = keybindSidebar
    pick.Size = UDim2.new(0, 52, 0, 18)
    pick.Position = UDim2.new(0, 42, 0, y)
    pick.BackgroundColor3 = Color3.fromRGB(46, 46, 60)
    pick.BorderSizePixel = 0
    pick.TextColor3 = Color3.fromRGB(220, 220, 235)
    pick.Font = Enum.Font.Gotham
    pick.TextSize = 9
    pick.Text = "-"
    Instance.new("UICorner", pick).CornerRadius = UDim.new(0, 4)

    local dot = Instance.new("Frame")
    dot.Parent = keybindSidebar
    dot.Size = UDim2.new(0, 14, 0, 14)
    dot.Position = UDim2.new(0, 100, 0, y + 2)
    dot.BackgroundColor3 = KEY_STATUS_NONE
    dot.BorderSizePixel = 0
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

    return pick, dot
end

local orbitKeyPickBtn, orbitKeyStatusDot = makeKeyRow(48, "Orbit")
orbitKeyPickBtn.Name = "OrbitKeyPick"
local voidKeyPickBtn, voidKeyStatusDot = makeKeyRow(72, "Void")
voidKeyPickBtn.Name = "VoidKeyPick"

local ksHint = Instance.new("TextLabel")
ksHint.Parent = keybindSidebar
ksHint.Size = UDim2.new(1, -8, 0, 28)
ksHint.Position = UDim2.new(0, 4, 0, 96)
ksHint.BackgroundTransparency = 1
ksHint.Font = Enum.Font.Gotham
ksHint.TextSize = 9
ksHint.TextColor3 = Color3.fromRGB(130, 130, 150)
ksHint.TextWrapped = true
ksHint.TextXAlignment = Enum.TextXAlignment.Left
ksHint.TextYAlignment = Enum.TextYAlignment.Top
ksHint.Text = "키 칸 클릭 → 키 누르기. Esc 취소. 누르는 동안 초록."

local function refreshKeyBindUI()
    orbitBtn.Text = orbitBtnLabel(orbitEnabled)
    voidBtn.Text = voidBtnLabel(voidEnabled)
    keybindMasterBtn.Text = keybindHotkeysEnabled and "단축키: ON" or "단축키: OFF"
    keybindMasterBtn.BackgroundColor3 = keybindHotkeysEnabled and Color3.fromRGB(48, 62, 52) or Color3.fromRGB(62, 48, 48)
    if keybindCaptureMode == "orbit" then
        orbitKeyPickBtn.Text = "…"
        orbitKeyPickBtn.BackgroundColor3 = Color3.fromRGB(75, 60, 120)
    else
        orbitKeyPickBtn.Text = KEYBIND_ORBIT_TOGGLE and KEYBIND_ORBIT_TOGGLE.Name or "없음"
        orbitKeyPickBtn.BackgroundColor3 = Color3.fromRGB(46, 46, 60)
    end
    if keybindCaptureMode == "void" then
        voidKeyPickBtn.Text = "…"
        voidKeyPickBtn.BackgroundColor3 = Color3.fromRGB(55, 80, 125)
    else
        voidKeyPickBtn.Text = KEYBIND_VOID_TOGGLE and KEYBIND_VOID_TOGGLE.Name or "없음"
        voidKeyPickBtn.BackgroundColor3 = Color3.fromRGB(46, 46, 60)
    end
end

keybindMasterBtn.MouseButton1Click:Connect(function()
    keybindHotkeysEnabled = not keybindHotkeysEnabled
    keybindCaptureMode = nil
    refreshKeyBindUI()
end)

orbitKeyPickBtn.MouseButton1Click:Connect(function()
    if keybindCaptureMode == "orbit" then
        keybindCaptureMode = nil
    else
        keybindCaptureMode = "orbit"
    end
    refreshKeyBindUI()
end)

voidKeyPickBtn.MouseButton1Click:Connect(function()
    if keybindCaptureMode == "void" then
        keybindCaptureMode = nil
    else
        keybindCaptureMode = "void"
    end
    refreshKeyBindUI()
end)

refreshKeyBindUI()

RunService.RenderStepped:Connect(function()
    local function setDot(dot, key)
        if not key then
            dot.BackgroundColor3 = KEY_STATUS_NONE
            return
        end
        local down = false
        pcall(function()
            down = UIS:IsKeyDown(key)
        end)
        dot.BackgroundColor3 = down and KEY_STATUS_DOWN or KEY_STATUS_UP
    end
    setDot(orbitKeyStatusDot, KEYBIND_ORBIT_TOGGLE)
    setDot(voidKeyStatusDot, KEYBIND_VOID_TOGGLE)
end)

local voidHideSlider = createSlider(main, 546, "Void Hide Time", 0.05, 10, voidHideTime, 2, function(v)
    voidHideTime = v
end)

local voidAttackSlider = createSlider(main, 596, "Void Attack Time", 0.05, 10, voidAttackTime, 2, function(v)
    voidAttackTime = v
end)

-- In Void UI removed

-- ESP UI
local espBtn = Instance.new("TextButton")
espBtn.Parent = main
espBtn.Size = UDim2.new(1, -20, 0, 30)
espBtn.Position = UDim2.new(0, 10, 0, 676)
espBtn.BackgroundColor3 = Color3.fromRGB(42, 96, 72)
espBtn.BorderSizePixel = 0
espBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
espBtn.Font = Enum.Font.GothamBold
espBtn.TextSize = 12
espBtn.Text = "ESP: OFF"
Instance.new("UICorner", espBtn).CornerRadius = UDim.new(0, 6)

local saveCfgBtn = Instance.new("TextButton")
saveCfgBtn.Parent = main
saveCfgBtn.Size = UDim2.new(1, -20, 0, 30)
saveCfgBtn.Position = UDim2.new(0, 10, 0, 710)
saveCfgBtn.BackgroundColor3 = Color3.fromRGB(82, 88, 130)
saveCfgBtn.BorderSizePixel = 0
saveCfgBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
saveCfgBtn.Font = Enum.Font.GothamBold
saveCfgBtn.TextSize = 12
saveCfgBtn.Text = "Save Config"
Instance.new("UICorner", saveCfgBtn).CornerRadius = UDim.new(0, 6)

local loadCfgBtn = Instance.new("TextButton")
loadCfgBtn.Parent = main
loadCfgBtn.Size = UDim2.new(1, -20, 0, 30)
loadCfgBtn.Position = UDim2.new(0, 10, 0, 744)
loadCfgBtn.BackgroundColor3 = Color3.fromRGB(100, 84, 150)
loadCfgBtn.BorderSizePixel = 0
loadCfgBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
loadCfgBtn.Font = Enum.Font.GothamBold
loadCfgBtn.TextSize = 12
loadCfgBtn.Text = "Load Config"
Instance.new("UICorner", loadCfgBtn).CornerRadius = UDim.new(0, 6)

-- Animation panel (side tab)
-- (Animation UI removed per user request)
-- Anti-Aim panel (side tab)
local aaPanel = Instance.new("Frame")
aaPanel.Parent = main
aaPanel.Size = UDim2.new(0, 300, 0, 300)
aaPanel.Position = UDim2.new(1, 10, 0, 60)
aaPanel.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
aaPanel.BorderSizePixel = 1
aaPanel.BorderColor3 = Color3.fromRGB(70, 70, 100)
aaPanel.Visible = false
Instance.new("UICorner", aaPanel).CornerRadius = UDim.new(0, 8)
aaPanel.ZIndex = 50
aaPanel.ClipsDescendants = false

local aaSec = Instance.new("TextLabel")
aaSec.Parent = aaPanel
aaSec.Size = UDim2.new(1, -16, 0, 18)
aaSec.Position = UDim2.new(0, 8, 0, 8)
aaSec.BackgroundTransparency = 1
aaSec.TextColor3 = Color3.fromRGB(220, 220, 235)
aaSec.Font = Enum.Font.GothamBold
aaSec.TextSize = 12
aaSec.TextXAlignment = Enum.TextXAlignment.Left
aaSec.Text = "Anti-Aim"

local aaPitchBtn = Instance.new("TextButton")
aaPitchBtn.Parent = aaPanel
aaPitchBtn.Size = UDim2.new(1, -16, 0, 24)
aaPitchBtn.Position = UDim2.new(0, 8, 0, 34)
aaPitchBtn.BackgroundColor3 = Color3.fromRGB(52, 52, 70)
aaPitchBtn.BorderSizePixel = 0
aaPitchBtn.TextColor3 = Color3.fromRGB(235, 235, 245)
aaPitchBtn.Font = Enum.Font.Gotham
aaPitchBtn.TextSize = 11
aaPitchBtn.Text = "Pitch: Off"
Instance.new("UICorner", aaPitchBtn).CornerRadius = UDim.new(0, 6)

local aaSpinBtn = Instance.new("TextButton")
aaSpinBtn.Parent = aaPanel
aaSpinBtn.Size = UDim2.new(1, -16, 0, 24)
aaSpinBtn.Position = UDim2.new(0, 8, 0, 64)
aaSpinBtn.BackgroundColor3 = Color3.fromRGB(52, 52, 70)
aaSpinBtn.BorderSizePixel = 0
aaSpinBtn.TextColor3 = Color3.fromRGB(235, 235, 245)
aaSpinBtn.Font = Enum.Font.Gotham
aaSpinBtn.TextSize = 11
aaSpinBtn.Text = "Spin: OFF"
Instance.new("UICorner", aaSpinBtn).CornerRadius = UDim.new(0, 6)

local aaSpinSlider = createSlider(aaPanel, 94, "Spin Speed", 0, 50, aaSpinSpeed, 0, function(v)
    aaSpinSpeed = math.floor(v + 0.5)
end)

local aaRollBtn = Instance.new("TextButton")
aaRollBtn.Parent = aaPanel
aaRollBtn.Size = UDim2.new(1, -16, 0, 24)
aaRollBtn.Position = UDim2.new(0, 8, 0, 140)
aaRollBtn.BackgroundColor3 = Color3.fromRGB(52, 52, 70)
aaRollBtn.BorderSizePixel = 0
aaRollBtn.TextColor3 = Color3.fromRGB(235, 235, 245)
aaRollBtn.Font = Enum.Font.Gotham
aaRollBtn.TextSize = 11
aaRollBtn.Text = "Roll: Off"
Instance.new("UICorner", aaRollBtn).CornerRadius = UDim.new(0, 6)

local aaRollSlider = createSlider(aaPanel, 170, "Roll Speed", 0, 200, aaRollSpeed, 0, function(v)
    aaRollSpeed = math.floor(v + 0.5)
end)

-- Special modes (below Roll)
local aaSpecialBtn = Instance.new("TextButton")
aaSpecialBtn.Parent = aaPanel
aaSpecialBtn.Size = UDim2.new(1, -16, 0, 24)
aaSpecialBtn.Position = UDim2.new(0, 8, 0, 200)
aaSpecialBtn.BackgroundColor3 = Color3.fromRGB(52, 52, 70)
aaSpecialBtn.BorderSizePixel = 0
aaSpecialBtn.TextColor3 = Color3.fromRGB(235, 235, 245)
aaSpecialBtn.Font = Enum.Font.Gotham
aaSpecialBtn.TextSize = 11
aaSpecialBtn.Text = "Special: Off"
Instance.new("UICorner", aaSpecialBtn).CornerRadius = UDim.new(0, 6)

local aaHardModeBtn = Instance.new("TextButton")
aaHardModeBtn.Parent = aaPanel
aaHardModeBtn.Size = UDim2.new(1, -16, 0, 24)
aaHardModeBtn.Position = UDim2.new(0, 8, 0, 230)
aaHardModeBtn.BackgroundColor3 = Color3.fromRGB(84, 48, 48)
aaHardModeBtn.BorderSizePixel = 0
aaHardModeBtn.TextColor3 = Color3.fromRGB(255, 225, 225)
aaHardModeBtn.Font = Enum.Font.GothamBold
aaHardModeBtn.TextSize = 11
aaHardModeBtn.Text = "Hard Mode: OFF"
Instance.new("UICorner", aaHardModeBtn).CornerRadius = UDim.new(0, 6)

local aaIgnoreACBtn = Instance.new("TextButton")
aaIgnoreACBtn.Parent = aaPanel
aaIgnoreACBtn.Size = UDim2.new(1, -16, 0, 24)
aaIgnoreACBtn.Position = UDim2.new(0, 8, 0, 260)
aaIgnoreACBtn.BackgroundColor3 = Color3.fromRGB(52, 52, 70)
aaIgnoreACBtn.BorderSizePixel = 0
aaIgnoreACBtn.TextColor3 = Color3.fromRGB(235, 235, 245)
aaIgnoreACBtn.Font = Enum.Font.Gotham
aaIgnoreACBtn.TextSize = 11
aaIgnoreACBtn.Text = "Ignore AnimationController: OFF"
Instance.new("UICorner", aaIgnoreACBtn).CornerRadius = UDim.new(0, 6)

-- Drone removed

-- Moving side panel (Tab 3)
mvPanel = Instance.new("Frame")
mvPanel.Parent = main
mvPanel.Size = UDim2.new(0, 300, 0, 520)
mvPanel.Position = UDim2.new(1, 10, 0, 60)
mvPanel.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
mvPanel.BorderSizePixel = 1
mvPanel.BorderColor3 = Color3.fromRGB(70, 70, 100)
mvPanel.Visible = false
Instance.new("UICorner", mvPanel).CornerRadius = UDim.new(0, 8)
mvPanel.ZIndex = 50
mvPanel.ClipsDescendants = false
-- Hide Moving panel entirely
mvPanel.Visible = false

-- NoBody side panel removed

-- TP side panel
tpPanel = Instance.new("Frame")
tpPanel.Parent = main
tpPanel.Size = UDim2.new(0, 300, 0, 200)
tpPanel.Position = UDim2.new(1, 10, 0, 60)
tpPanel.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
tpPanel.BorderSizePixel = 1
tpPanel.BorderColor3 = Color3.fromRGB(70, 70, 100)
tpPanel.Visible = false
Instance.new("UICorner", tpPanel).CornerRadius = UDim.new(0, 8)
tpPanel.ZIndex = 50
tpPanel.ClipsDescendants = false

local tpSec = Instance.new("TextLabel")
tpSec.Parent = tpPanel
tpSec.Size = UDim2.new(1, -16, 0, 18)
tpSec.Position = UDim2.new(0, 8, 0, 8)
tpSec.BackgroundTransparency = 1
tpSec.TextColor3 = Color3.fromRGB(220, 220, 235)
tpSec.Font = Enum.Font.GothamBold
tpSec.TextSize = 12
tpSec.TextXAlignment = Enum.TextXAlignment.Left
tpSec.Text = "TP (Under Target)"

local tpToggle = Instance.new("TextButton")
tpToggle.Parent = tpPanel
tpToggle.Size = UDim2.new(1, -16, 0, 24)
tpToggle.Position = UDim2.new(0, 8, 0, 34)
tpToggle.BackgroundColor3 = Color3.fromRGB(52, 52, 70)
tpToggle.BorderSizePixel = 0
tpToggle.TextColor3 = Color3.fromRGB(235, 235, 245)
tpToggle.Font = Enum.Font.Gotham
tpToggle.TextSize = 11
tpToggle.Text = "TP: OFF"
Instance.new("UICorner", tpToggle).CornerRadius = UDim.new(0, 6)

local tpHeightSlider = createSlider(tpPanel, 64, "TP Height (up/down)", -50, 50, tp2Height, 0, function(v)
	tp2Height = math.floor(v + 0.5)
end)

local tpRadSlider = createSlider(tpPanel, 114, "TP Radius (circle)", 1, 100, tp2Radius, 0, function(v)
	tp2Radius = math.floor(v + 0.5)
end)

local tpSpeedSlider = createSlider(tpPanel, 164, "TP Speed", 1, 60, tp2Speed, 0, function(v)
	tp2Speed = math.floor(v + 0.5)
end)

local function stopTP()
	tp2Enabled = false
	if tp2Conn then tp2Conn:Disconnect(); tp2Conn = nil end
	if tpToggle and tpToggle.Parent then
		tpToggle.Text = "TP: OFF"
		tpToggle.BackgroundColor3 = Color3.fromRGB(52, 52, 70)
	end
end

local function startTP()
	if tp2Conn then tp2Conn:Disconnect() end
	tp2Enabled = true
	tpToggle.Text = "TP: ON"
	tpToggle.BackgroundColor3 = Color3.fromRGB(80, 100, 200)

	local angle = 0
	tp2Conn = RunService.RenderStepped:Connect(function(dt)
		if not tp2Enabled then return end
		-- avoid conflict with strong controllers
		if voidEnabled or inVoidEnabled then return end
		local myHRP = getMyHRP()
		local target = getSelectedTargetPlayer() or findClosestAliveTarget()
		local targetHRP = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
		local targetHum = target and target.Character and target.Character:FindFirstChildOfClass("Humanoid")
		if not myHRP or not targetHRP or not targetHum or targetHum.Health <= 0 then return end
		angle = angle + dt * math.max(0.1, tp2Speed)
		local circle = Vector3.new(math.cos(angle) * tp2Radius, tp2Height, math.sin(angle) * tp2Radius)
		local dest = targetHRP.Position + circle
		local cur = myHRP.Position
		local alpha = math.clamp(dt * tp2Speed, 0, 1)
		local newPos = cur:Lerp(dest, alpha)
		pcall(function()
			myHRP.CFrame = CFrame.new(newPos, targetHRP.Position)
			myHRP.AssemblyLinearVelocity = Vector3.zero
			myHRP.AssemblyAngularVelocity = Vector3.zero
		end)
	end)
end

tpToggle.MouseButton1Click:Connect(function()
	if tp2Enabled then stopTP() else startTP() end
end)

tpTabBtn.MouseButton1Click:Connect(function()
	tpPanel.Visible = not tpPanel.Visible
end)

-- NoBody UI removed

local mvSec = Instance.new("TextLabel")
mvSec.Parent = mvPanel
mvSec.Size = UDim2.new(1, -16, 0, 18)
mvSec.Position = UDim2.new(0, 8, 0, 8)
mvSec.BackgroundTransparency = 1
mvSec.TextColor3 = Color3.fromRGB(220, 220, 235)
mvSec.Font = Enum.Font.GothamBold
mvSec.TextSize = 12
mvSec.TextXAlignment = Enum.TextXAlignment.Left
mvSec.Text = "Moving"

local mvToggle = Instance.new("TextButton")
mvToggle.Parent = mvPanel
mvToggle.Size = UDim2.new(1, -16, 0, 24)
mvToggle.Position = UDim2.new(0, 8, 0, 34)
mvToggle.BackgroundColor3 = Color3.fromRGB(52, 52, 70)
mvToggle.BorderSizePixel = 0
mvToggle.TextColor3 = Color3.fromRGB(235, 235, 245)
mvToggle.Font = Enum.Font.Gotham
mvToggle.TextSize = 11
mvToggle.Text = "Moving: OFF"
Instance.new("UICorner", mvToggle).CornerRadius = UDim.new(0, 6)

-- (removed other moving controls; keeping crouch spam only)

local crouchBtn = Instance.new("TextButton")
crouchBtn.Parent = mvPanel
crouchBtn.Size = UDim2.new(1, -16, 0, 22)
crouchBtn.Position = UDim2.new(0, 8, 0, 64)
crouchBtn.BackgroundColor3 = Color3.fromRGB(70, 52, 52)
crouchBtn.BorderSizePixel = 0
crouchBtn.TextColor3 = Color3.fromRGB(235, 235, 245)
crouchBtn.Font = Enum.Font.Gotham
crouchBtn.TextSize = 11
crouchBtn.Text = "Crouch Spam: OFF"
Instance.new("UICorner", crouchBtn).CornerRadius = UDim.new(0, 6)

local crouchTempoSlider = createSlider(mvPanel, 90, "Crouch Tempo (s)", 0.12, 0.60, mvCrouchTempo, 2, function(v)
	mvCrouchTempo = v
end)

local crouchDepthSlider = createSlider(mvPanel, 140, "Crouch Depth (hip height)", 0.0, 1.8, mvCrouchDepth, 2, function(v)
	mvCrouchDepth = v
end)

-- moving core
local function stopMoving()
    mvEnabled = false
    if mvConn then mvConn:Disconnect(); mvConn = nil end
    mvToggle.Text = "Moving: OFF"
    mvToggle.BackgroundColor3 = Color3.fromRGB(52, 52, 70)
end

local function nearestEnemyDist(myHRP)
    local best = math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then
                local d = (myHRP.Position - hrp.Position).Magnitude
                if d < best then best = d end
            end
        end
    end
    return best
end

local function startMoving()
    stopMoving()
    mvEnabled = true
    mvToggle.Text = "Moving: ON"
    mvToggle.BackgroundColor3 = Color3.fromRGB(80, 100, 200)
	captureMVJoints()
	local exposed = 0
	local crouchPhase = 0
    mvConn = RunService.RenderStepped:Connect(function(dt)
        if not mvEnabled then return end
        local hum = getMyHumanoid()
        local hrp = getMyHRP()
        local cam = workspace.CurrentCamera
        if not hum or not hrp or not cam then return end
		-- initialize base hip height once (kept for safety but not used to lower body)
		if mvBaseHipHeight == nil then mvBaseHipHeight = hum.HipHeight end
        -- crouch-only mode (visual via joints; no directional override, no body lowering)
        local forward = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z).Unit
		if mvCrouchSpamOn then
			crouchPhase = crouchPhase + dt
			local half = math.max(mvCrouchTempo, 0.05)
			local cyc = (crouchPhase % (half * 2)) / (half * 2) -- 0..1
			local down = (cyc < 0.5) and 1 or 0
			-- alpha 0..1 describing crouch amount based on "down" and depth
			local alpha = down * math.clamp(mvCrouchDepth, 0, 1.8) / 1.8
			-- replicate to everyone via Character Attribute
			pcall(function()
				if LP.Character then
					LP.Character:SetAttribute("CrouchVisualAlpha", alpha)
				end
			end)
			-- target local rotations
			local waistA = 0.6 * alpha
			local neckA = -0.15 * alpha
			local hipA = 0.8 * alpha
			local kneeA = 1.1 * alpha
			-- apply with lerp to preserve bases
			local function lerpJoint(j, base, angX)
				if not j or not base then return end
				local to = base * CFrame.Angles(angX, 0, 0)
				j.C0 = j.C0:Lerp(to, math.clamp(dt * 12, 0, 1))
			end
			lerpJoint(mvJoints.waist, mvBaseC0.waist, waistA)
			lerpJoint(mvJoints.neck,  mvBaseC0.neck,  neckA)
			lerpJoint(mvJoints.rHip,  mvBaseC0.rHip,  hipA)
			lerpJoint(mvJoints.lHip,  mvBaseC0.lHip,  hipA)
			lerpJoint(mvJoints.rKnee, mvBaseC0.rKnee, kneeA)
			lerpJoint(mvJoints.lKnee, mvBaseC0.lKnee, kneeA)
		else
			-- restore joints back to base
			local function restore(j, base)
				if not j or not base then return end
				j.C0 = j.C0:Lerp(base, math.clamp(dt * 10, 0, 1))
			end
			restore(mvJoints.waist, mvBaseC0.waist)
			restore(mvJoints.neck,  mvBaseC0.neck)
			restore(mvJoints.rHip,  mvBaseC0.rHip)
			restore(mvJoints.lHip,  mvBaseC0.lHip)
			restore(mvJoints.rKnee, mvBaseC0.rKnee)
			restore(mvJoints.lKnee, mvBaseC0.lKnee)
			-- clear attribute
			pcall(function()
				if LP.Character then
					LP.Character:SetAttribute("CrouchVisualAlpha", 0)
				end
			end)
		end
        -- no FOV/peek logic
    end)
end

mvToggle.MouseButton1Click:Connect(function()
    if mvEnabled then stopMoving() else startMoving() end
end)

-- (removed other moving bindings)

mvTabBtn.MouseButton1Click:Connect(function()
    mvPanel.Visible = not mvPanel.Visible
    if mvPanel.Visible and not mvEnabled then startMoving() end
end)

crouchBtn.MouseButton1Click:Connect(function()
	mvCrouchSpamOn = not mvCrouchSpamOn
	crouchBtn.Text = mvCrouchSpamOn and "Duck-Spam: EIN" or "Duck-Spam: AUS"
	-- reset base when enabling
	if mvCrouchSpamOn then
		local hum = getMyHumanoid()
		if hum then mvBaseHipHeight = hum.HipHeight end
	end
end)
-- Toggle button below main UI
local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "ToggleButton"
toggleBtn.Parent = gui
toggleBtn.Size = UDim2.new(0, 160, 0, 34)
toggleBtn.Position = UDim2.new(0.5, -80, 0.5, 70)
toggleBtn.BackgroundColor3 = Color3.fromRGB(96, 72, 190)
toggleBtn.BorderSizePixel = 0
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 12
toggleBtn.Text = "Hide UI"
toggleBtn.AutoButtonColor = true

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 8)
btnCorner.Parent = toggleBtn

-- Drag logic (top bar drag)
local dragging = false
local dragStart = Vector2.new()
local startPos = UDim2.new()

topBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = main.Position
    end
end)

UIS.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement
    and input.UserInputType ~= Enum.UserInputType.Touch then return end

    local delta = input.Position - dragStart
    main.Position = UDim2.new(
        startPos.X.Scale,
        startPos.X.Offset + delta.X,
        startPos.Y.Scale,
        startPos.Y.Offset + delta.Y
    )
end)

UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

-- Toggle show/hide
toggleBtn.MouseButton1Click:Connect(function()
    main.Visible = not main.Visible
    if main.Visible then
        toggleBtn.Text = "Hide UI"
    else
        toggleBtn.Text = "Show UI"
    end
end)

aaTabBtn.MouseButton1Click:Connect(function()
    aaPanel.Visible = not aaPanel.Visible
end)
local function getMyHumanoid()
    local ch = LP.Character
    if not ch then return nil end
    return ch:FindFirstChildOfClass("Humanoid")
end

local function getMyHRP()
    local ch = LP.Character
    if not ch then return nil end
    return ch:FindFirstChild("HumanoidRootPart")
end

local function getMyHumanoid()
    local ch = LP.Character
    if not ch then return nil end
    return ch:FindFirstChildOfClass("Humanoid")
end

local function getOrbitOffset(patternName, angle, radius)
    local r = math.max(radius, 0.001)
    if patternName == "Random" then
        local a = math.random() * math.pi * 2
        local rr = math.random() * r
        return Vector3.new(math.cos(a) * rr, (math.random() - 0.5) * 1.5, math.sin(a) * rr)
    elseif patternName == "Random spot" then
        local dx = math.random() - 0.5
        local dy = math.random() - 0.5
        local dz = math.random() - 0.5
        local dir = Vector3.new(dx, dy, dz)
        if dir.Magnitude < 1e-4 then
            dir = Vector3.new(1, 0, 0)
        else
            dir = dir.Unit
        end
        return dir * r
    elseif patternName == "Star" then
        local rr = r * (0.55 + 0.45 * math.cos(5 * angle))
        return Vector3.new(math.cos(angle) * rr, 0, math.sin(angle) * rr)
    elseif patternName == "Figure8" then
        return Vector3.new(math.sin(angle) * r, 0, (math.sin(angle) * math.cos(angle)) * r)
    elseif patternName == "Ellipse" then
        return Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r * 0.55)
    elseif patternName == "Square" then
        local t = (angle % (2 * math.pi)) / (2 * math.pi)
        local side = math.floor(t * 4)
        local p = (t * 4) - side
        local x, z
        if side == 0 then
            x, z = -r + (2 * r * p), -r
        elseif side == 1 then
            x, z = r, -r + (2 * r * p)
        elseif side == 2 then
            x, z = r - (2 * r * p), r
        else
            x, z = -r, r - (2 * r * p)
        end
        return Vector3.new(x, 0, z)
    end
    -- Circle fallback
    return Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
end

local function getOrCreateESP(player)
    local item = espPool[player]
    if item and item.gui and item.gui.Parent then
        return item
    end
    local gui2 = Instance.new("BillboardGui")
    gui2.Name = "SimpleESP_" .. player.Name
    gui2.AlwaysOnTop = true
    gui2.LightInfluence = 0
    gui2.MaxDistance = 1e9
    gui2.Size = UDim2.new(0, 180, 0, 42)
    gui2.StudsOffset = Vector3.new(0, 3.2, 0)

    local txt = Instance.new("TextLabel")
    txt.Parent = gui2
    txt.Size = UDim2.new(1, 0, 1, 0)
    txt.BackgroundTransparency = 1
    txt.TextColor3 = Color3.fromRGB(255, 130, 130)
    txt.TextStrokeTransparency = 0.4
    txt.Font = Enum.Font.GothamBold
    txt.TextSize = 12
    txt.TextWrapped = true
    txt.TextYAlignment = Enum.TextYAlignment.Center
    txt.TextXAlignment = Enum.TextXAlignment.Center

    item = {gui = gui2, label = txt}
    espPool[player] = item
    return item
end

local function stopESP()
    espEnabled = false
    if espConn then
        espConn:Disconnect()
        espConn = nil
    end
    for _, v in pairs(espPool) do
        if v.gui then v.gui:Destroy() end
    end
    espPool = {}
    espBtn.Text = "ESP: OFF"
    espBtn.BackgroundColor3 = Color3.fromRGB(42, 96, 72)
end

local function startESP()
    if espConn then espConn:Disconnect() end
    espEnabled = true
    espBtn.Text = "ESP: ON"
    espBtn.BackgroundColor3 = Color3.fromRGB(65, 148, 106)

    espConn = RunService.RenderStepped:Connect(function()
        if not espEnabled then return end
        local myHRP = getMyHRP()
        if not myHRP then return end

        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP then
                local ch = p.Character
                local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
                local hum = ch and ch:FindFirstChildOfClass("Humanoid")
                if hrp and hum and hum.Health > 0 then
                    local item = getOrCreateESP(p)
                    item.gui.Parent = hrp
                    local dist = (myHRP.Position - hrp.Position).Magnitude
                    local scale = math.clamp(1 - (dist / 5000), 0.35, 1.1)
                    item.gui.Size = UDim2.new(0, math.floor(180 * scale), 0, math.floor(42 * scale))
                    item.label.TextSize = math.floor(12 * scale + 2)
                    item.label.Text = string.format("%s\nHP %.0f | %.0f studs", p.Name, hum.Health, dist)
                else
                    local ex = espPool[p]
                    if ex and ex.gui then
                        ex.gui.Parent = nil
                    end
                end
            end
        end
    end)
end

-- (Animation core removed)
-- Anti-Aim core
local function captureAAJoints()
    aaJoints.neck, aaJoints.waist = nil, nil
    aaBase.neckC0, aaBase.waistC0 = nil, nil
    local ch = LP.Character
    if not ch then return end
    -- R15
    local upper = ch:FindFirstChild("UpperTorso")
    local lower = ch:FindFirstChild("LowerTorso")
    local head = ch:FindFirstChild("Head")
    if upper then
        aaJoints.waist = upper:FindFirstChildOfClass("Motor6D")
        -- named "Waist"
        for _,m in ipairs(upper:GetChildren()) do
            if m:IsA("Motor6D") and m.Name == "Waist" then
                aaJoints.waist = m
            end
        end
    end
    if upper and head then
        -- Neck usually parented to UpperTorso
        aaJoints.neck = upper:FindFirstChild("Neck") or head:FindFirstChild("Neck")
        if not aaJoints.neck then
            for _,m in ipairs(upper:GetChildren()) do
                if m:IsA("Motor6D") and m.Part1 == head then
                    aaJoints.neck = m
                end
            end
        end
    end
    if aaJoints.neck then aaBase.neckC0 = aaJoints.neck.C0 end
    if aaJoints.waist then aaBase.waistC0 = aaJoints.waist.C0 end
end

local function startAntiAim()
    if aaConn then aaConn:Disconnect() end
    captureAAJoints()
    local spinAngle = 0
    local rollT = 0
    local rxPhase = math.random()*10
    local ryPhase = math.random()*10
    local rzPhase = math.random()*10
    -- 모두 꺼져 있으면 완전 복구
    if aaPitchMode == "Off" and not aaSpinOn and not aaRollOn and aaSpecialMode == "Off" then
        stopAntiAim()
        return
    end
    -- Force AutoRotate=false when toggled back by game/tools
    local hum = getMyHumanoid()
    if hum then
        pcall(function() hum.AutoRotate = false end)
        if aaAutoRotConn then aaAutoRotConn:Disconnect(); aaAutoRotConn = nil end
        aaAutoRotConn = hum:GetPropertyChangedSignal("AutoRotate"):Connect(function()
            local h = getMyHumanoid()
            if not h then return end
            if isAntiAimActive() and h.AutoRotate ~= false then
                pcall(function() h.AutoRotate = false end)
            end
        end)
    end
    -- Try disabling default Animate script while Anti-Aim is active to prevent tool/run tracks from fighting
    do
        local ch = LP.Character
        if ch then
            local anim = ch:FindFirstChild("Animate")
            if not anim then
                for _, inst in ipairs(ch:GetChildren()) do
                    if inst:IsA("LocalScript") and string.find(string.lower(inst.Name), "animate", 1, true) then
                        anim = inst
                        break
                    end
                end
            end
            if anim and anim:IsA("LocalScript") then
                aaAnimateScript = anim
                aaAnimateWasEnabled = not anim.Disabled
                pcall(function() anim.Disabled = true end)
            end
        end
    end

    -- Use high-priority BindToRenderStep so we apply after most game logic
    pcall(function() RunService:UnbindFromRenderStep(aaBindKey) end)
    RunService:BindToRenderStep(aaBindKey, Enum.RenderPriority.Last.Value, function(dt)
        local hum = getMyHumanoid()
        local hrp = getMyHRP()
        if not hum or not hrp then return end
        -- 다른 사람에게 보이도록 HRP 자체를 회전(복제됨). 이동 문제 최소화를 위해 AutoRotate 해제
        hum.AutoRotate = false
        local pos = hrp.Position
        local rot = CFrame.new()
local t = time()

        -- (옵션) AnimationController/Animator가 재생 중인 트랙을 무력화
        if aaIgnoreAC or aaHardMode then
            local ch = LP.Character
            local function stopTracks(animator)
                if not animator then return end
                local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
                if ok and tracks then
                    for _, tr in ipairs(tracks) do
                        pcall(function()
                            tr:AdjustWeight(0, 0)
                            tr:AdjustSpeed(aaHardMode and 0 or 1)
                            tr:Stop(0)
                        end)
                    end
                end
                if aaHardMode then
                    pcall(function() animator.Enabled = false end)
                end
            end
            if ch then
                -- Humanoid Animator
                local h = ch:FindFirstChildOfClass("Humanoid")
                if h then stopTracks(h:FindFirstChildOfClass("Animator")) end
                -- Any AnimationController with Animator
                for _, inst in ipairs(ch:GetChildren()) do
                    if inst:IsA("AnimationController") then
                        stopTracks(inst:FindFirstChildOfClass("Animator"))
                    end
                end
            end
        end

        -- Pitch
        if aaPitchMode == "UpsideDown" then
            rot = rot * CFrame.Angles(math.pi, 0, 0)
        elseif aaPitchMode == "BackHead" then
            rot = rot * CFrame.Angles(0, math.pi, 0)
        elseif aaPitchMode == "NoHead" then
            -- 몸 회전은 그대로 두고, 머리를 몸 안으로 집어넣기(Neck C0 오프셋)
            if aaJoints.neck and aaBase.neckC0 then
                pcall(function()
                    aaJoints.neck.C0 = aaBase.neckC0 * CFrame.new(0, -1.5, -0.6)
                end)
            end
            -- 머리 축소(가능할 때) 및 로컬 비가시화
            local ch = LP.Character
            local head = ch and ch:FindFirstChild("Head")
            if head then
                aaHeadState.head = head
                -- save and hide transparency on head, face decal, accessories
                local function saveAndHide(inst)
                    if not inst then return end
                    if aaHeadState.saved[inst] == nil then
                        aaHeadState.saved[inst] = inst.LocalTransparencyModifier or 0
                    end
                    inst.LocalTransparencyModifier = 1
                end
                saveAndHide(head)
                for _, d in ipairs(head:GetDescendants()) do
                    if d:IsA("Decal") or d:IsA("Texture") then
                        saveAndHide(d)
                    end
                end
                for _, acc in ipairs(ch:GetChildren()) do
                    if acc:IsA("Accessory") then
                        local handle = acc:FindFirstChild("Handle")
                        if handle and handle:FindFirstChildOfClass("Attachment") and head:FindFirstChild(handle:FindFirstChildOfClass("Attachment").Name) then
                            saveAndHide(handle)
                            for _, dd in ipairs(handle:GetDescendants()) do
                                if dd:IsA("Decal") or dd:IsA("Texture") then
                                    saveAndHide(dd)
                                end
                            end
                        end
                    end
                end
                -- try shrink via SpecialMesh/Mesh
                local mesh = head:FindFirstChildOfClass("SpecialMesh") or head:FindFirstChildOfClass("Mesh")
                if mesh then
                    aaHeadState.mesh = mesh
                    if not aaHeadState.meshOrigScale then
                        aaHeadState.meshOrigScale = mesh.Scale
                    end
                    pcall(function()
                        mesh.Scale = Vector3.new(0.05, 0.05, 0.05)
                    end)
                end
            end
        elseif aaPitchMode == "Jitter" then
            local j = math.sin(t*18) * 0.6
            rot = rot * CFrame.Angles(j, 0, 0)
        elseif aaPitchMode == "ZeroG" then
            local j = math.sin(t*2.2) * math.pi
            rot = rot * CFrame.Angles(j, 0, 0)
        elseif aaPitchMode == "Sway" then
            local y = math.sin(t*1.8) * 0.9
            rot = rot * CFrame.Angles(0, y, 0)
        elseif aaPitchMode == "Nod" then
            local a = math.sin(t*2.6) * 1.2
            rot = rot * CFrame.Angles(a, 0, 0)
        elseif aaPitchMode == "Shake" then
            local a = math.sin(t*24) * 0.25
            rot = rot * CFrame.Angles(a, 0, 0)
        elseif aaPitchMode == "WavePitch" then
            local a = math.sin(t*0.8) * 1.5
            rot = rot * CFrame.Angles(a, 0, 0)
        elseif aaPitchMode == "Bounce" then
            local s = math.sin(t*2.1)
            local tri = (2/math.pi) * math.asin(math.sin(t*2.1)) -- tri wave
            rot = rot * CFrame.Angles(tri*1.0, 0, 0)
        elseif aaPitchMode == "SpiralPitch" then
            local a = (t*0.9) % (2*math.pi)
            rot = rot * CFrame.Angles(a, 0, 0)
        elseif aaPitchMode == "Pulse" then
            local s = math.sin(t*3.0)
            local a = (s >= 0) and 0.8 or -0.8
            rot = rot * CFrame.Angles(a, 0, 0)
        elseif aaPitchMode == "RandomStep" then
            local k = (math.floor(t*5) % 2 == 0) and 0.7 or -0.7
            rot = rot * CFrame.Angles(k, 0, 0)
        elseif aaPitchMode == "MicroJitter" then
            local a = math.sin(t*40) * 0.12 + math.cos(t*33) * 0.08
            rot = rot * CFrame.Angles(a, 0, 0)
        elseif aaPitchMode == "TiltLeft" then
            rot = rot * CFrame.Angles(0.5, 0, 0)
        elseif aaPitchMode == "TiltRight" then
            rot = rot * CFrame.Angles(-0.5, 0, 0)
        end

        -- Spin (yaw)
        if aaSpinOn and aaSpinSpeed > 0 then
            spinAngle = spinAngle + dt * aaSpinSpeed * 6.0
            rot = rot * CFrame.Angles(0, spinAngle, 0)
        end

        -- Roll (full multi-axis) - faster, stronger, harder
        if aaRollOn and aaRollSpeed > 0 then
            -- speed scaling (nonlinear) for more aggression
            local sp = aaRollSpeed
            local gain = 1.15 + (sp / 36) ^ 1.6
            -- advance independent phases for multi-direction motion
            rxPhase = rxPhase + dt * (sp * 8.0 + 1.5)
            ryPhase = ryPhase + dt * (sp * 9.2 + 1.3)
            rzPhase = rzPhase + dt * (sp * 10.4 + 1.1)
            rollT = rollT + dt * sp * 8.0
            -- base oscillation with different harmonics
            local rx = (math.sin(rxPhase*3.2) + math.sin(rollT*2.1)*0.5) * math.pi * gain
            local ry = (math.cos(ryPhase*3.7) + math.sin(rollT*2.9)*0.5) * math.pi * gain
            local rz = (math.sin(rzPhase*4.3) + math.cos(rollT*3.3)*0.5) * math.pi * gain
            -- add chaotic jitter (never zero: epsilon floor)
            local baseJ = 0.15 + (sp/200) -- prevent stillness
            local jx = (math.random() - 0.5) * (0.45 * gain) + baseJ
            local jy = (math.random() - 0.5) * (0.45 * gain) - baseJ
            local jz = (math.random() - 0.5) * (0.45 * gain) + baseJ*0.7
            rx, ry, rz = rx + jx, ry + jy, rz + jz
            rot = rot * CFrame.Angles(rx, ry, rz)
        end
        -- Special modes (smooth joints, stronger, camera follow handled below)
        local function lerpJointC0(joint, baseC0, targetLocal, alpha)
            if not joint or not baseC0 then return end
            local from = joint.C0
            local to = baseC0 * targetLocal
            pcall(function() joint.C0 = from:Lerp(to, alpha) end)
        end
        if aaSpecialMode == "Forward" then
            local a = math.clamp(dt * 8, 0, 1)
            lerpJointC0(aaJoints.waist, aaBase.waistC0, CFrame.Angles(1.55, 0, 0), a) -- 더 깊게
            lerpJointC0(aaJoints.neck,  aaBase.neckC0,  CFrame.Angles(1.70, 0, 0), a) -- 머리 더 전방
            rot = rot * CFrame.Angles(0.55, 0, 0)
        elseif aaSpecialMode == "Backward" then
            local a = math.clamp(dt * 8, 0, 1)
            lerpJointC0(aaJoints.waist, aaBase.waistC0, CFrame.Angles(-1.30, 0, 0), a) -- 허리 더 뒤로
            lerpJointC0(aaJoints.neck,  aaBase.neckC0,  CFrame.Angles(-1.80, 0, 0), a) -- 머리 더 뒤로
            rot = rot * CFrame.Angles(-0.50, 0, 0)
        elseif aaSpecialMode == "Chaos" then
            -- Extra chaotic micro-rotations and joint offsets
            local c = (math.random() - 0.5) * 0.6
            rot = rot * CFrame.Angles(0, c, 0) * CFrame.Angles(c*0.3, 0, c*0.4)
            if aaJoints.waist and aaBase.waistC0 then
                local t2 = time()*20
                local wob = CFrame.Angles(math.sin(t2)*0.5, math.cos(t2*1.5)*0.5, math.sin(t2*1.9)*0.5)
                lerpJointC0(aaJoints.waist, aaBase.waistC0, wob, math.clamp(dt*10,0,1))
            end
            if aaJoints.neck and aaBase.neckC0 then
                local t3 = time()*25
                local nwb = CFrame.Angles(math.sin(t3)*0.7, math.cos(t3*1.2)*0.6, 0)
                lerpJointC0(aaJoints.neck, aaBase.neckC0, nwb, math.clamp(dt*10,0,1))
            end
        else
            -- Special Off: restore neck/waist bases each frame to avoid residual offsets
            local a = math.clamp(dt * 10, 0, 1)
            lerpJointC0(aaJoints.waist, aaBase.waistC0, CFrame.new(), a)
            lerpJointC0(aaJoints.neck,  aaBase.neckC0,  CFrame.new(), a)
        end

        pcall(function()
            -- Void/InVoid 중에는 HRP 강제 회전을 적용하지 않아 텔레포트/이동 간섭을 피한다
            if not (voidEnabled or inVoidEnabled) then
                -- 현재 몸이 보고 있는 방향(look) 기준으로 회전 적용
                local cf = hrp.CFrame
                local pos = cf.Position
                local look = cf.LookVector
                local base = CFrame.new(pos, pos + look)
                aaLastRot = rot
                -- Off 상태면 각도 적용 스킵(방향 고정 방지)
                if aaPitchMode == "Off" and not aaSpinOn and not aaRollOn and aaSpecialMode == "Off" then
                    -- no-op
                else
                    hrp.CFrame = base * rot
                end
                if aaHardMode then
                    hrp.AssemblyAngularVelocity = Vector3.zero
                end
            else
                aaLastRot = rot
            end
        end)
        -- NoHead 해제: 다른 모드에서는 Neck C0를 기본값으로 되돌림
        if aaPitchMode ~= "NoHead" then
            if aaJoints.neck and aaBase.neckC0 then
                pcall(function() aaJoints.neck.C0 = aaBase.neckC0 end)
            end
            -- restore hidden head parts if we left NoHead
            if aaHeadState and next(aaHeadState.saved) ~= nil then
                for inst, val in pairs(aaHeadState.saved) do
                    pcall(function()
                        if inst and inst.Parent then
                            inst.LocalTransparencyModifier = val or 0
                        end
                    end)
                end
                aaHeadState.saved = {}
            end
            if aaHeadState and aaHeadState.mesh and aaHeadState.meshOrigScale then
                pcall(function() aaHeadState.mesh.Scale = aaHeadState.meshOrigScale end)
                aaHeadState.mesh = nil
                aaHeadState.meshOrigScale = nil
            end
        end
    end)
    -- Fallback connection (kept lightweight) to detect if render-step was unbound unexpectedly
    aaConn = RunService.Heartbeat:Connect(function() end)
    -- Physics-step enforcer to resist mid-frame overrides
    if aaSteppedConn then aaSteppedConn:Disconnect() end
    aaSteppedConn = RunService.Stepped:Connect(function()
        if not isAntiAimActive() then return end
        if voidEnabled or inVoidEnabled then return end -- Void/InVoid 중에는 강제 회전 스킵
        local hum = getMyHumanoid()
        local hrp = getMyHRP()
        if not hum or not hrp then return end
        hum.AutoRotate = false
        local p = hrp.Position
        pcall(function()
            hrp.CFrame = CFrame.new(p) * (aaLastRot or CFrame.new())
        end)
    end)
end

function isAntiAimActive()
    return not (aaPitchMode == "Off" and not aaSpinOn and not aaRollOn and aaSpecialMode == "Off")
end

-- Watchdog to keep Anti-Aim alive (e.g., when tools/animations try to override)
local aaWatchConn = nil
local function startAAWatchdog()
    if aaWatchConn then aaWatchConn:Disconnect() end
    aaWatchConn = RunService.Heartbeat:Connect(function()
        -- Orbit: one bad CFrame write can disconnect Heartbeat; keep flag ON but movement stops.
        if orbitEnabled and not orbitConn then
            pcall(startOrbit)
        end
        if (voidEnabled or inVoidEnabled) then return end
        if isAntiAimActive() and (not aaConn) then
            startAntiAim()
        end
        local hum = getMyHumanoid()
        if hum and isAntiAimActive() then
            -- some games/tools flip this back on
            if hum.AutoRotate ~= false then
                pcall(function() hum.AutoRotate = false end)
            end
        end
    end)
end
startAAWatchdog()


local function stopOrbit()
    orbitEnabled = false
    if orbitConn then
        orbitConn:Disconnect()
        orbitConn = nil
    end
    orbitBtn.Text = orbitBtnLabel(false)
    orbitBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 78)
end
 
-- (Silent Aim core removed)

local function startOrbit()
    if orbitConn then orbitConn:Disconnect() end
    orbitEnabled = true
    orbitBtn.Text = orbitBtnLabel(true)
    orbitBtn.BackgroundColor3 = Color3.fromRGB(95, 75, 190)

    tpAccumulator = 0
    orbitConn = RunService.Heartbeat:Connect(function(dt)
        if not orbitEnabled then return end
        local me = getMyHRP()
        local target = getSelectedTargetPlayer()
        local hrp = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
        local th = target and target.Character and target.Character:FindFirstChildOfClass("Humanoid")
        -- 타겟이 잠시 없거나 리스폰 중일 때 Orbit을 끄지 않고 유지한다.
        if not me or not hrp or not th or th.Health <= 0 then
            return
        end

        local patternName = orbitPatterns[orbitPatternIndex]
        if patternName == "Mixer" then
            local pool = {"Circle", "Random", "Star", "Figure8", "Ellipse", "Square", "Random spot"}
            patternName = pool[math.random(1, #pool)]
        end

        -- Random spot: jump to random point on sphere of radius tpRadius; faster Orbit Speed => shorter wait.
        local stepInterval = tpInterval
        if patternName == "Random spot" then
            local spd = math.max(orbitSpeed, 1)
            stepInterval = tpInterval * (95 / spd)
            stepInterval = math.clamp(stepInterval, 0.00015, 2)
        end

        tpAccumulator = tpAccumulator + dt
        if tpAccumulator < stepInterval then
            return
        end
        tpAccumulator = 0

        local angleStep = 0.22 + orbitSpeed * 0.28
        orbitAngle = orbitAngle + angleStep + ((math.random() - 0.5) * 0.4)

        local r = tpRadius
        local offset
        if patternName == "Random spot" then
            offset = getOrbitOffset("Random spot", 0, r)
        else
            local h = (math.random() - 0.5) * 1.5
            offset = getOrbitOffset(patternName, orbitAngle, r) + Vector3.new(0, h, 0)
        end
        pcall(function()
            me.CFrame = CFrame.new(hrp.Position + offset)
            me.AssemblyLinearVelocity = Vector3.zero
        end)
    end)
end

orbitBtn.MouseButton1Click:Connect(function()
    if orbitEnabled then
        stopOrbit()
    else
        startOrbit()
    end
end)

orbitPatternBtn.MouseButton1Click:Connect(function()
    orbitPatternIndex = orbitPatternIndex + 1
    if orbitPatternIndex > #orbitPatterns then orbitPatternIndex = 1 end
    orbitPatternBtn.Text = "Orbit Pattern: " .. (orbitPatterns[orbitPatternIndex])
end)

local function findTargetPlayer(nameText)
    local q = string.lower(string.gsub(nameText or "", "^%s*(.-)%s*$", "%1"))
    if q == "" then return nil end
    local best = nil
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            local n = string.lower(p.Name)
            local dn = string.lower(p.DisplayName)
            if n == q or dn == q or string.find(n, q, 1, true) or string.find(dn, q, 1, true) then
                best = p
                break
            end
        end
    end
    return best
end

local function findClosestAliveTarget()
    local myHRP = getMyHRP()
    local bestPlayer = nil
    local bestDist = math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then
                local d = myHRP and (myHRP.Position - hrp.Position).Magnitude or 0
                if d < bestDist then
                    bestDist = d
                    bestPlayer = p
                end
            end
        end
    end
    return bestPlayer
end

-- Silent Aim helpers
-- (Silent Aim helpers removed)

local targetList = {}
local targetIndex = 0
local playerButtons = {}

local function clearPlayerListButtons()
    playerButtons = {}
    for _, child in ipairs(playerListFrame:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end
end

local function updatePlayerButtonHighlights()
    for name, btn in pairs(playerButtons) do
        if btn and btn.Parent then
            if name == selectedTargetName then
                btn.BackgroundColor3 = Color3.fromRGB(170, 55, 55)
            else
                btn.BackgroundColor3 = Color3.fromRGB(56, 56, 74)
            end
        end
    end
end

local function rebuildPlayerListUI()
    clearPlayerListButtons()
    if #targetList == 0 then
        local empty = Instance.new("TextLabel")
        empty.Parent = playerListFrame
        empty.Size = UDim2.new(1, -8, 0, 22)
        empty.BackgroundTransparency = 1
        empty.Text = "No players"
        empty.TextColor3 = Color3.fromRGB(180, 180, 195)
        empty.Font = Enum.Font.Gotham
        empty.TextSize = 11
        empty.TextXAlignment = Enum.TextXAlignment.Left
    else
        for i, p in ipairs(targetList) do
            local btn = Instance.new("TextButton")
            btn.Parent = playerListFrame
            btn.Size = UDim2.new(1, -8, 0, 22)
            btn.BackgroundColor3 = Color3.fromRGB(56, 56, 74)
            btn.BorderSizePixel = 0
            btn.TextColor3 = Color3.fromRGB(235, 235, 245)
            btn.Font = Enum.Font.Gotham
            btn.TextSize = 11
            btn.TextXAlignment = Enum.TextXAlignment.Left
            btn.Text = "  " .. p.Name .. " (@" .. p.DisplayName .. ")"
            btn.LayoutOrder = i
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
            playerButtons[p.Name] = btn
            btn.MouseButton1Click:Connect(function()
                selectedTargetName = p.Name
                targetLabel.Text = "Target: " .. selectedTargetName
                updatePlayerButtonHighlights()
            end)
        end
    end

    task.defer(function()
        local y = listLayout.AbsoluteContentSize.Y
        playerListFrame.CanvasSize = UDim2.new(0, 0, 0, y + 6)
        updatePlayerButtonHighlights()
    end)
end

local function rebuildTargetList()
    targetList = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            table.insert(targetList, p)
        end
    end
    table.sort(targetList, function(a, b)
        return a.Name:lower() < b.Name:lower()
    end)
    if #targetList == 0 then
        selectedTargetName = ""
        targetIndex = 0
        targetLabel.Text = "Target: None"
        rebuildPlayerListUI()
        return
    end

    local foundSelected = false
    for i, p in ipairs(targetList) do
        if p.Name == selectedTargetName then
            targetIndex = i
            foundSelected = true
            break
        end
    end
    if not foundSelected then
        if targetIndex < 1 or targetIndex > #targetList then
            targetIndex = 1
        end
        selectedTargetName = targetList[targetIndex].Name
    end
    targetLabel.Text = "Target: " .. selectedTargetName
    rebuildPlayerListUI()
end

function getSelectedTargetPlayer()
    if selectedTargetName == "" then return nil end
    return findTargetPlayer(selectedTargetName)
end

local function fireLeftClick()
    local ch = LP.Character
    if not ch then return false end
    local hum = ch:FindFirstChildOfClass("Humanoid")
    local tool = ch:FindFirstChildOfClass("Tool")

    -- 장착 안 되어 있으면 Backpack에서 자동 장착 시도
    if not tool then
        local bp = LP:FindFirstChildOfClass("Backpack")
        local bpTool = bp and bp:FindFirstChildOfClass("Tool")
        if hum and bpTool then
            pcall(function() hum:EquipTool(bpTool) end)
            tool = ch:FindFirstChildOfClass("Tool")
        end
    end

    if not tool then return false end

    -- 게임별 입력 방식 차이를 줄이기 위해 여러 번 activate 시도
    pcall(function() tool:Activate() end)
    task.wait(0.01)
    pcall(function() tool:Activate() end)

    -- executor 제공 mouse1click이 있으면 추가 타격 시도
    pcall(function()
        if type(mouse1click) == "function" then
            mouse1click()
        end
    end)
    return true
end

	-- NoBody removed
	startNoBodyAttack = function() end
	stopNoBodyAttack = function() end

local function attackSelectedOnce()
    local target = getSelectedTargetPlayer()
    if not target then
        target = findClosestAliveTarget()
    end
    local myHRP = getMyHRP()
    local targetHRP = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    local targetHum = target and target.Character and target.Character:FindFirstChildOfClass("Humanoid")
    if not myHRP or not targetHRP or not targetHum or targetHum.Health <= 0 then return false end

    local backCF = myHRP.CFrame
    if voidEnabled and voidAnchorPos then
        backCF = CFrame.new(voidAnchorPos)
    end
    local look = targetHRP.CFrame.LookVector
    local right = targetHRP.CFrame.RightVector
    local pred = targetHRP.Position + targetHRP.AssemblyLinearVelocity * 0.05

    local attackPoints
    if voidEnabled then
        -- void 공격은 뒤가 아니라 타겟 중심으로 바로 진입
        attackPoints = {
            pred,
            pred + right * 0.35,
            pred - right * 0.35,
        }
    else
        -- 뒤/좌뒤/우뒤 3포인트를 빠르게 순회해서 명중률 극대화
        attackPoints = {
            pred - look * 2.0,
            pred - look * 1.8 + right * 1.2,
            pred - look * 1.8 - right * 1.2,
        }
    end
    pcall(function()
        for _, p in ipairs(attackPoints) do
            myHRP.CFrame = CFrame.new(p, pred)
            task.wait(0.005)
            for _ = 1, (rageBurstHits + 1) do
                fireLeftClick()
                task.wait(0.005)
            end
        end
    end)
    -- 공격 도중 오류가 나도 복귀는 항상 시도
    pcall(function()
        myHRP.CFrame = backCF
        myHRP.AssemblyLinearVelocity = Vector3.zero
    end)
    return true
end

-- Rage removed

local function stopVoid()
    voidEnabled = false
    voidThread = nil
    voidBtn.Text = voidBtnLabel(false)
    voidBtn.BackgroundColor3 = Color3.fromRGB(42, 62, 96)
    pcall(function()
        UIS.MouseBehavior = Enum.MouseBehavior.Default
    end)
end

-- In Void logic removed

local function startVoid()
    voidEnabled = true
    voidBtn.Text = voidBtnLabel(true)
    voidBtn.BackgroundColor3 = Color3.fromRGB(78, 112, 200)

    local thisThread = {}
    voidThread = thisThread
    task.spawn(function()
        local baseHRP = getMyHRP()
        if baseHRP then
            -- 너무 낮거나 지형 아래로 빠져 죽지 않도록 안전한 높이로 고정
            voidAnchorPos = Vector3.new(
                baseHRP.Position.X + voidDistanceStuds,
                math.max(baseHRP.Position.Y + 1500, 1500),
                baseHRP.Position.Z + voidDistanceStuds
            )
        end

        while voidEnabled and voidThread == thisThread do
            local myHRP = getMyHRP()
            local myHum = getMyHumanoid()
            if not myHRP then
                task.wait(0.1)
                continue
            end
            if myHum and myHum.Health <= 0 then
                task.wait(0.2)
                continue
            end

            if not voidAnchorPos then
                voidAnchorPos = Vector3.new(
                    myHRP.Position.X + voidDistanceStuds,
                    math.max(myHRP.Position.Y + 1500, 1500),
                    myHRP.Position.Z + voidDistanceStuds
                )
            end

            local voidPos = voidAnchorPos
            local hideUntil = tick() + voidHideTime
            while voidEnabled and voidThread == thisThread and tick() < hideUntil do
                local hrp = getMyHRP()
                if hrp then
                    pcall(function()
                        hrp.CFrame = CFrame.new(voidPos)
                        hrp.AssemblyLinearVelocity = Vector3.zero
                    end)
                end
                task.wait(0.005)
            end

            local attackUntil = tick() + voidAttackTime
            while voidEnabled and voidThread == thisThread and tick() < attackUntil do
                -- 공격 직전에도 void 기준점에서 출발하도록 강제
                local hrp = getMyHRP()
                if hrp then
                    pcall(function()
                        hrp.CFrame = CFrame.new(voidPos)
                        hrp.AssemblyLinearVelocity = Vector3.zero
                    end)
                end
                local attacked = attackSelectedOnce() -- 타겟으로 갔다가 바로 voidPos로 복귀
                if not attacked then
                    task.wait(0.005)
                end
                task.wait(0.015)
            end
        end
    end)
end

local function collectConfig()
    return {
        orbitSpeed = orbitSpeed,
        tpInterval = tpInterval,
        tpRadius = tpRadius,
		-- TP
		tp2Radius = tp2Radius,
		tp2Height = tp2Height,
		tp2Speed = tp2Speed,
		-- uiScale removed
        orbitPatternIndex = orbitPatternIndex,
        voidHideTime = voidHideTime,
        voidAttackTime = voidAttackTime,
        -- Moving params
		-- (removed others) keep crouch only
		mvCrouchTempo = mvCrouchTempo,
		mvCrouchDepth = mvCrouchDepth,
        selectedTargetName = selectedTargetName,
        keybindOrbitName = KEYBIND_ORBIT_TOGGLE and KEYBIND_ORBIT_TOGGLE.Name or "",
        keybindVoidName = KEYBIND_VOID_TOGGLE and KEYBIND_VOID_TOGGLE.Name or "",
        keybindHotkeysEnabled = keybindHotkeysEnabled,
        states = {
            orbitEnabled = orbitEnabled,
            voidEnabled = voidEnabled,
            espEnabled = espEnabled,
            mvEnabled = mvEnabled,
			-- keep crouch only
			mvCrouchSpamOn = mvCrouchSpamOn,
            aaPitchMode = aaPitchMode,
            aaSpinOn = aaSpinOn,
            aaSpinSpeed = aaSpinSpeed,
            aaRollOn = aaRollOn,
            aaRollSpeed = aaRollSpeed,
            aaIgnoreAC = aaIgnoreAC,
            aaHardMode = aaHardMode,
            aaSpecialMode = aaSpecialMode,
			-- TP
			tp2Enabled = tp2Enabled,
        },
    }
end

local function applyConfig(cfg)
    if type(cfg) ~= "table" then return false end

    if type(cfg.orbitSpeed) == "number" then speedSlider.setValue(cfg.orbitSpeed) end
    if type(cfg.tpRadius) == "number" then distanceSlider.setValue(cfg.tpRadius) end
    if type(cfg.tpInterval) == "number" then intervalSlider.setValue(cfg.tpInterval) end
	-- uiScale removed
    if type(cfg.orbitPatternIndex) == "number" then
        orbitPatternIndex = math.clamp(math.floor(cfg.orbitPatternIndex), 1, #orbitPatterns)
        orbitPatternBtn.Text = "Orbit Pattern: " .. (orbitPatterns[orbitPatternIndex])
    end
	-- TP params
	if type(cfg.tp2Height) == "number" then tpHeightSlider.setValue(cfg.tp2Height) end
	if type(cfg.tp2Radius) == "number" then tpRadSlider.setValue(cfg.tp2Radius) end
	if type(cfg.tp2Speed) == "number" then tpSpeedSlider.setValue(cfg.tp2Speed) end
    if type(cfg.voidHideTime) == "number" then voidHideSlider.setValue(cfg.voidHideTime) end
    if type(cfg.voidAttackTime) == "number" then voidAttackSlider.setValue(cfg.voidAttackTime) end
    -- Moving params
	if type(cfg.mvCrouchTempo) == "number" then crouchTempoSlider.setValue(cfg.mvCrouchTempo) end
	if type(cfg.mvCrouchDepth) == "number" then crouchDepthSlider.setValue(cfg.mvCrouchDepth) end

    if type(cfg.selectedTargetName) == "string" then
        selectedTargetName = cfg.selectedTargetName
    end
    if type(cfg.keybindOrbitName) == "string" then
        KEYBIND_ORBIT_TOGGLE = keyCodeFromName(cfg.keybindOrbitName)
    end
    if type(cfg.keybindVoidName) == "string" then
        KEYBIND_VOID_TOGGLE = keyCodeFromName(cfg.keybindVoidName)
    end
    if type(cfg.keybindHotkeysEnabled) == "boolean" then
        keybindHotkeysEnabled = cfg.keybindHotkeysEnabled
    end
    -- (Silent Aim config removed)

    rebuildTargetList()
    updatePlayerButtonHighlights()

    local st = cfg.states
    if type(st) == "table" then
        if st.orbitEnabled then startOrbit() else stopOrbit() end
        if st.voidEnabled then startVoid() else stopVoid() end
        if st.espEnabled then startESP() else stopESP() end
        if type(st.mvEnabled) == "boolean" then
            if st.mvEnabled then startMoving() else stopMoving() end
        end
		if type(st.mvCrouchSpamOn) == "boolean" then
			mvCrouchSpamOn = st.mvCrouchSpamOn
			if crouchBtn and crouchBtn.Parent then
				crouchBtn.Text = mvCrouchSpamOn and "Crouch Spam: ON" or "Crouch Spam: OFF"
			end
		end
        if type(st.aaPitchMode) == "string" then
            aaPitchMode = st.aaPitchMode
            aaPitchBtn.Text = "Pitch: " .. (aaPitchMode == "Off" and "Off" or aaPitchMode)
        end
        if type(st.aaSpinOn) == "boolean" then
            aaSpinOn = st.aaSpinOn
            aaSpinBtn.Text = aaSpinOn and "Spin: ON" or "Spin: OFF"
        end
        if type(st.aaSpinSpeed) == "number" then
            aaSpinSpeed = st.aaSpinSpeed
            aaSpinSlider.setValue(aaSpinSpeed)
        end
        if type(st.aaRollOn) == "boolean" then
            aaRollOn = st.aaRollOn
            aaRollBtn.Text = aaRollOn and "Roll: ON" or "Roll: Off"
        end
        if type(st.aaRollSpeed) == "number" then
            aaRollSpeed = st.aaRollSpeed
            aaRollSlider.setValue(aaRollSpeed)
        end
        if type(st.aaIgnoreAC) == "boolean" then
            aaIgnoreAC = st.aaIgnoreAC
            aaIgnoreACBtn.Text = aaIgnoreAC and "Ignore AnimationController: ON" or "Ignore AnimationController: OFF"
        end
        if type(st.aaHardMode) == "boolean" then
            aaHardMode = st.aaHardMode
            aaHardModeBtn.Text = aaHardMode and "Hard Mode: ON" or "Hard Mode: OFF"
        end
        if type(st.aaSpecialMode) == "string" then
            aaSpecialMode = st.aaSpecialMode
            if aaSpecialBtn and aaSpecialBtn.Parent then
                aaSpecialBtn.Text = "Special: " .. aaSpecialMode
            end
        end
		if type(st.tp2Enabled) == "boolean" then
			if st.tp2Enabled then startTP() else stopTP() end
		end
        startAntiAim()
    end
    refreshKeyBindUI()
    return true
end

-- Rage binding removed

voidBtn.MouseButton1Click:Connect(function()
    if voidEnabled then
        stopVoid()
    else
        startVoid()
    end
end)

UIS.InputBegan:Connect(function(input, _gameProcessed)
    if input.UserInputType == Enum.UserInputType.Keyboard then
        local k = input.KeyCode
        if keybindCaptureMode then
            if k == Enum.KeyCode.Escape then
                keybindCaptureMode = nil
                refreshKeyBindUI()
                return
            end
            if k == Enum.KeyCode.Unknown then
                return
            end
            if keybindCaptureMode == "orbit" then
                if KEYBIND_VOID_TOGGLE == k then
                    KEYBIND_VOID_TOGGLE = nil
                end
                KEYBIND_ORBIT_TOGGLE = k
            elseif keybindCaptureMode == "void" then
                if KEYBIND_ORBIT_TOGGLE == k then
                    KEYBIND_ORBIT_TOGGLE = nil
                end
                KEYBIND_VOID_TOGGLE = k
            end
            keybindCaptureMode = nil
            refreshKeyBindUI()
            return
        end
    end
    if not keybindHotkeysEnabled then
        return
    end
    local typing = false
    pcall(function()
        typing = GuiService:GetFocusedTextBox() ~= nil
    end)
    if typing then
        return
    end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then
        return
    end
    local k = input.KeyCode
    -- gameProcessed는 많은 게임에서 F키까지 삼켜서 여기서는 보지 않음 (채팅 포커스만 막음)
    if KEYBIND_ORBIT_TOGGLE and k == KEYBIND_ORBIT_TOGGLE then
        if orbitEnabled then
            stopOrbit()
        else
            startOrbit()
        end
    elseif KEYBIND_VOID_TOGGLE and k == KEYBIND_VOID_TOGGLE then
        if voidEnabled then
            stopVoid()
        else
            startVoid()
        end
    end
end)

-- In Void binding removed

espBtn.MouseButton1Click:Connect(function()
    if espEnabled then
        stopESP()
    else
        startESP()
    end
end)

saveCfgBtn.MouseButton1Click:Connect(function()
    local ok, savedToDisk = writeSettings(collectConfig())
    if ok then
        saveCfgBtn.Text = savedToDisk and "Save Config (Done)" or "Save OK (메모리만)"
    else
        saveCfgBtn.Text = "Save Config (Fail)"
    end
    task.delay(1.2, function()
        if saveCfgBtn and saveCfgBtn.Parent then
            saveCfgBtn.Text = "Save Config"
        end
    end)
end)

loadCfgBtn.MouseButton1Click:Connect(function()
    local cfg = readSettings()
    if not cfg then
        loadCfgBtn.Text = "Load: 없음"
        task.delay(1.2, function()
            if loadCfgBtn and loadCfgBtn.Parent then
                loadCfgBtn.Text = "Load Config"
            end
        end)
        return
    end
    local ok = applyConfig(cfg)
    if ok then
        loadCfgBtn.Text = "Load Config (Done)"
    else
        loadCfgBtn.Text = "Load: 오류"
    end
    task.delay(1.2, function()
        if loadCfgBtn and loadCfgBtn.Parent then
            loadCfgBtn.Text = "Load Config"
        end
    end)
end)

-- Anti-Aim UI bindings
aaPitchBtn.MouseButton1Click:Connect(function()
    local order = {"Off","UpsideDown","BackHead","NoHead","Jitter","ZeroG","Sway","Nod","Shake","WavePitch","Bounce","SpiralPitch","Pulse","RandomStep","MicroJitter","TiltLeft","TiltRight"}
    local idx = 1
    for i,v in ipairs(order) do if v==aaPitchMode then idx=i break end end
    idx = (idx % #order) + 1
    aaPitchMode = order[idx]
    aaPitchBtn.Text = "Pitch: " .. aaPitchMode
    if aaPitchMode == "Off" and not aaSpinOn and not aaRollOn then
        stopAntiAim()
    else
        startAntiAim()
    end
end)

-- (Animation UI bindings removed)

-- removed: SpinOsc / SpinRev / RollBurst bindings
-- (Animation play/stop bindings removed)
 
-- (Silent Aim removed)

aaSpinBtn.MouseButton1Click:Connect(function()
    aaSpinOn = not aaSpinOn
    aaSpinBtn.Text = aaSpinOn and "Spin: ON" or "Spin: OFF"
    if aaPitchMode == "Off" and not aaSpinOn and not aaRollOn then
        stopAntiAim()
    else
        startAntiAim()
    end
end)

aaRollBtn.MouseButton1Click:Connect(function()
    aaRollOn = not aaRollOn
    aaRollBtn.Text = aaRollOn and "Roll: ON" or "Roll: Off"
    if aaPitchMode == "Off" and not aaSpinOn and not aaRollOn then
        stopAntiAim()
    else
        startAntiAim()
    end
end)

aaHardModeBtn.MouseButton1Click:Connect(function()
    aaHardMode = not aaHardMode
    aaHardModeBtn.Text = aaHardMode and "Hard Mode: ON" or "Hard Mode: OFF"
    if aaPitchMode ~= "Off" or aaSpinOn or aaRollOn then
        startAntiAim()
    end
end)

aaIgnoreACBtn.MouseButton1Click:Connect(function()
    aaIgnoreAC = not aaIgnoreAC
    aaIgnoreACBtn.Text = aaIgnoreAC and "Ignore AnimationController: ON" or "Ignore AnimationController: OFF"
    if aaPitchMode ~= "Off" or aaSpinOn or aaRollOn then
        startAntiAim()
    end
end)

aaSpecialBtn.MouseButton1Click:Connect(function()
    local order = {"Off","Forward","Backward","Chaos"}
    local idx = 1
    for i,v in ipairs(order) do if v==aaSpecialMode then idx=i break end end
    idx = (idx % #order) + 1
    aaSpecialMode = order[idx]
    aaSpecialBtn.Text = "Special: " .. aaSpecialMode
    if aaPitchMode ~= "Off" or aaSpinOn or aaRollOn or aaSpecialMode ~= "Off" then
        startAntiAim()
    end
end)

refreshTargetBtn.MouseButton1Click:Connect(function()
    rebuildTargetList()
end)

Players.PlayerAdded:Connect(function()
    rebuildTargetList()
end)

Players.PlayerRemoving:Connect(function()
    rebuildTargetList()
end)

-- Tool hooks (initial + live) to persist Anti-Aim even when equipping tools
local function __hookToolPersist(tool)
    if not tool or not tool:IsA("Tool") then return end
    pcall(function()
        tool.Equipped:Connect(function()
            if isAntiAimActive() then
                startAntiAim()
                for i = 1, 8 do
                    task.delay(i * 0.02, function()
                        if isAntiAimActive() then startAntiAim() end
                    end)
                end
            end
            -- In Void removed
        end)
        tool.Unequipped:Connect(function()
            if isAntiAimActive() then
                startAntiAim()
                task.delay(0.03, function()
                    if isAntiAimActive() then startAntiAim() end
                end)
            end
            -- In Void removed
        end)
    end)
end

local function __hookAllToolsNow()
    local ch = LP.Character
    if ch then
        for _, inst in ipairs(ch:GetChildren()) do
            if inst:IsA("Tool") then __hookToolPersist(inst) end
        end
        ch.ChildAdded:Connect(function(inst)
            if inst:IsA("Tool") then __hookToolPersist(inst) end
        end)
    end
    local bp = LP:FindFirstChildOfClass("Backpack")
    if bp then
        for _, inst in ipairs(bp:GetChildren()) do
            if inst:IsA("Tool") then __hookToolPersist(inst) end
        end
        bp.ChildAdded:Connect(function(inst)
            if inst:IsA("Tool") then __hookToolPersist(inst) end
        end)
    end
end
__hookAllToolsNow()


LP.CharacterAdded:Connect(function()
    if orbitEnabled then
        task.wait(0.2)
        startOrbit()
    end
    -- Drone removed
    if voidEnabled then
        task.wait(0.2)
        startVoid()
    end
    -- In Void removed
    -- Rebind Anti-Aim on respawn
    if isAntiAimActive() then
        task.wait(0.2)
        startAntiAim()
    end
    -- Tool hooks to keep Anti-Aim when gun/tools are equipped
    local ch = LP.Character
    if ch then
        local function hookTool(tool)
            if not tool or not tool:IsA("Tool") then return end
            pcall(function()
                tool.Equipped:Connect(function()
                    if isAntiAimActive() then
                        -- 즉시 적용 + 짧은 버스트 재적용
                        startAntiAim()
                        for i = 1, 6 do
                            task.delay(i * 0.02, function()
                                if isAntiAimActive() then startAntiAim() end
                            end)
                        end
                    end
                    -- In Void removed
                end)
                tool.Unequipped:Connect(function()
                    if isAntiAimActive() then
                        -- 해제 시에도 짧게 재적용
                        startAntiAim()
                        task.delay(0.03, function()
                            if isAntiAimActive() then startAntiAim() end
                        end)
                    end
                    -- In Void removed
                end)
            end)
        end
        for _, inst in ipairs(ch:GetChildren()) do
            if inst:IsA("Tool") then hookTool(inst) end
        end
        ch.ChildAdded:Connect(function(inst)
            if inst:IsA("Tool") then hookTool(inst) end
        end)
    end
end)

rebuildTargetList()
