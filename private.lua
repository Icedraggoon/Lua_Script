-- Ice Lua (clean single file)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local env = getgenv and getgenv() or _G
if env.__IceLuaRuntime and type(env.__IceLuaRuntime.cleanup) == "function" then
    pcall(env.__IceLuaRuntime.cleanup)
end

local runtime = { conns = {}, cleanup = nil }
env.__IceLuaRuntime = runtime

local function addConn(c)
    table.insert(runtime.conns, c)
    return c
end

local function loadVoidUi()
    local okHttp, source = pcall(function()
        return game:HttpGet("https://raw.githubusercontent.com/raphaelmaboi/ui-libraries/refs/heads/main/VoidUi/source.lua")
    end)
    if not okHttp then error("VoidUi download failed: " .. tostring(source)) end
    local chunk, err = loadstring(source)
    if not chunk then error("VoidUi loadstring failed: " .. tostring(err)) end
    local okRun, lib = pcall(chunk)
    if not okRun or type(lib) ~= "table" then error("VoidUi runtime failed") end
    return lib
end

local library = loadVoidUi()

local state = {
    target = "Closest",
    orbitEnabled = false,
    orbitPattern = "Random spot",
    orbitKey = Enum.KeyCode.F6,
    voidEnabled = false,
    voidSpamEnabled = false,
    voidDistance = 200000000,
    voidKey = Enum.KeyCode.F7,
    aaEnabled = false,
    aaPitchMode = "Off",
    aaSpinOn = false,
    aaSpinSpeed = 12,
    aaRollOn = false,
    aaRollSpeed = 20,
    aaSpecialMode = "Off",
    aaIgnoreAC = false,
    aaHardMode = false,
    aaKey = Enum.KeyCode.F8,
}

local KEYSYS_API_URL = "https://lua-key-server-production.up.railway.app/verify"
local keyAuthed = false

local ROOT_FOLDER = "Ice Lua"
local CONFIG_FOLDER = ROOT_FOLDER .. "/config"
local KEY_FOLDER = ROOT_FOLDER .. "/KEY"
local KEY_FILE = KEY_FOLDER .. "/key.txt"

local ORBIT_DIST_MIN = 1000000
local ORBIT_DIST_MAX = 7000000
local ORBIT_STEP = 0.01
local VOID_SPAM_RADIUS = 800000000
local VOID_SPAM_DROP_STUDS = 1000000000
local VOID_SPAM_ANGULAR_SPEED = 25

local orbitConn, orbitAcc = nil, 0
local voidConn, voidAnchor, voidReturn = nil, nil, nil
local voidSpamConn, voidSpamAngle = nil, 0
local voidSpamCenterX, voidSpamCenterZ = 0, 0
local voidSpamTarget = nil
local aaConn, aaBindKey = nil, "ICE_AA_" .. tostring(LocalPlayer.UserId)
local aaJoints = { neck = nil, waist = nil }
local aaBase = { neckC0 = nil, waistC0 = nil }
local aaHeadSaved = {}

local targetDropdown, targetLabel, distLabel
local orbitToggle, voidToggle, voidSpamToggle, aaToggle
local orbitKeybind, voidKeybind, aaKeybind
local voidDistanceSlider, aaSpinSlider, aaRollSlider
local aaPitchLabel, aaSpinLabel, aaRollLabel, aaSpecialLabel, aaTornadoLabel, aaIgnoreLabel, aaHardLabel
local configDropdown, configStatus
local configNameHintLabel
local keyStatusLabel
local activeConfig = nil
local manualPrivateKey = ""
local manualConfigName = ""
local setManualConfigName

local bannerGui, bannerText
local keyInputGui, keyInputBoxNative, keyInputStatusNative
local configInputGui, configInputBoxNative
local mobileToggleGui

local function getMyHRP()
    local ch = LocalPlayer.Character
    return ch and ch:FindFirstChild("HumanoidRootPart") or nil
end

local function getMyHumanoid()
    local ch = LocalPlayer.Character
    return ch and ch:FindFirstChildOfClass("Humanoid") or nil
end

local function getAliveTargetHRP(player)
    if not player then return nil end
    local ch = player.Character
    if not ch then return nil end
    local hrp = ch:FindFirstChild("HumanoidRootPart")
    local hum = ch:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return nil end
    return hrp
end

local function findClosestTarget()
    local my = getMyHRP()
    local best, bestD = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local hrp = getAliveTargetHRP(p)
            if hrp then
                local d = my and (my.Position - hrp.Position).Magnitude or 0
                if d < bestD then bestD, best = d, p end
            end
        end
    end
    return best
end

local function findByNameLoose(text)
    local q = string.lower(string.gsub(text or "", "^%s*(.-)%s*$", "%1"))
    if q == "" then return nil end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local n, dn = string.lower(p.Name), string.lower(p.DisplayName)
            if n == q or dn == q or string.find(n, q, 1, true) or string.find(dn, q, 1, true) then
                return p
            end
        end
    end
    return nil
end

local function getSelectedTargetPlayer()
    if state.target == "Closest" then return findClosestTarget() end
    return findByNameLoose(state.target) or findClosestTarget()
end

local function collectTargetValues()
    local out = { "Closest" }
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then table.insert(out, p.Name) end
    end
    table.sort(out, function(a, b)
        if a == "Closest" then return true end
        if b == "Closest" then return false end
        return a:lower() < b:lower()
    end)
    return out
end

local function refreshTargetList(preserve)
    if not targetDropdown then return end
    local values = collectTargetValues()
    local cur = preserve and state.target or "Closest"
    if not table.find(values, cur) then cur = "Closest" end
    targetDropdown:Refresh(values)
    targetDropdown:Set(cur)
end

local function setBanner(text)
    pcall(function()
        if not bannerGui or not bannerGui.Parent then
            local parent = (gethui and gethui()) or game:GetService("CoreGui")
            local old = parent:FindFirstChild("IceLuaTopBanner")
            if old then old:Destroy() end
            bannerGui = Instance.new("ScreenGui")
            bannerGui.Name = "IceLuaTopBanner"
            bannerGui.ResetOnSpawn = false
            bannerGui.IgnoreGuiInset = true
            bannerGui.Parent = parent
            bannerText = Instance.new("TextLabel")
            bannerText.AnchorPoint = Vector2.new(0.5, 0)
            bannerText.Position = UDim2.new(0.5, 0, 0, 8)
            bannerText.Size = UDim2.new(0, 920, 0, 44)
            bannerText.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
            bannerText.BackgroundTransparency = 0.2
            bannerText.BorderSizePixel = 0
            bannerText.Font = Enum.Font.GothamBold
            bannerText.TextSize = 24
            bannerText.TextColor3 = Color3.fromRGB(255, 255, 255)
            bannerText.TextStrokeTransparency = 0.55
            bannerText.Parent = bannerGui
            Instance.new("UICorner", bannerText).CornerRadius = UDim.new(0, 10)
        end
        bannerText.Text = text
    end)
end

local function getSafeGuiParent()
    local ok, parent = pcall(function()
        if gethui then
            local h = gethui()
            if h then return h end
        end
        return game:GetService("CoreGui")
    end)
    if ok and parent then
        return parent
    end
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pg then
        return pg
    end
    return LocalPlayer:WaitForChild("PlayerGui")
end

-- keys.txt style "ICE-XXXX / note" → key only
local function normalizeKeyInput(s)
    if type(s) ~= "string" then return "" end
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    s = string.gsub(s, "%s+/.+$", "")
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
end

local function keyFileApiReady()
    return type(isfolder) == "function" and type(makefolder) == "function"
        and type(isfile) == "function" and type(readfile) == "function"
        and type(writefile) == "function"
end

local function ensureKeyFolder()
    if not keyFileApiReady() then return false, "filesystem API missing" end
    if not isfolder(ROOT_FOLDER) then makefolder(ROOT_FOLDER) end
    if not isfolder(KEY_FOLDER) then makefolder(KEY_FOLDER) end
    return true
end

local function savePrivateKeyToFile(raw)
    local clean = normalizeKeyInput(raw)
    if clean == "" then return false, "empty key" end
    local ok, err = ensureKeyFolder()
    if not ok then return false, err end
    local okw, werr = pcall(function()
        writefile(KEY_FILE, clean)
    end)
    if not okw then return false, tostring(werr) end
    return true
end

local function loadPrivateKeyFromFile()
    if not keyFileApiReady() then return nil end
    local ok, _ = ensureKeyFolder()
    if not ok then return nil end
    if not isfile(KEY_FILE) then return nil end
    local okr, text = pcall(function()
        return readfile(KEY_FILE)
    end)
    if not okr then return nil end
    local clean = normalizeKeyInput(text)
    if clean == "" then return nil end
    return clean
end

local function getBestHWID()
    local id = nil
    pcall(function()
        if type(gethwid) == "function" then
            local v = gethwid()
            if type(v) == "string" and v ~= "" then id = v end
        end
    end)
    if id then return id end
    pcall(function()
        if type(get_hwid) == "function" then
            local v = get_hwid()
            if type(v) == "string" and v ~= "" then id = v end
        end
    end)
    if id then return id end
    pcall(function()
        if type(syn) == "table" and type(syn.gethwid) == "function" then
            local v = syn.gethwid()
            if type(v) == "string" and v ~= "" then id = v end
        end
    end)
    if id then return id end
    local ex = "unknown"
    pcall(function()
        if type(identifyexecutor) == "function" then
            ex = tostring(identifyexecutor())
        end
    end)
    return string.format("fallback-%s-%s", tostring(LocalPlayer.UserId), ex)
end

local function getVerifyRequestFnList()
    local list = {}
    local function add(fn)
        if type(fn) ~= "function" then return end
        for _, f in ipairs(list) do
            if f == fn then return end
        end
        table.insert(list, fn)
    end
    if type(http_request) == "function" then add(http_request) end
    if type(syn) == "table" and type(syn.request) == "function" then add(syn.request) end
    if type(fluxus) == "table" and type(fluxus.request) == "function" then add(fluxus.request) end
    if type(request) == "function" then add(request) end
    if type(krnl_request) == "function" then add(krnl_request) end
    return list
end

local function verifyKeyWithServer(keyText)
    keyText = normalizeKeyInput(keyText)
    if type(keyText) ~= "string" or keyText == "" then
        return false, "Enter a key."
    end
    if type(KEYSYS_API_URL) ~= "string" or KEYSYS_API_URL == "" then
        return false, "KEYSYS_API_URL missing."
    end

    local reqList = getVerifyRequestFnList()
    if #reqList == 0 then
        return false, "Executor has no HTTP request API."
    end

    local body = {
        key = keyText,
        hwid = getBestHWID(),
        userId = LocalPlayer.UserId,
        placeId = game.PlaceId,
        gameId = game.GameId,
    }

    local payloadOk, payload = pcall(function()
        return HttpService:JSONEncode(body)
    end)
    if not payloadOk or type(payload) ~= "string" then
        return false, "Failed to build request."
    end

    local headerVariants = {
        { ["Content-Type"] = "application/json", ["Accept"] = "application/json" },
        {
            ["Content-Type"] = "application/json",
            ["Accept"] = "application/json",
            ["Expect"] = "",
            ["Connection"] = "close",
        },
        {
            ["Content-Type"] = "application/json",
            ["Accept"] = "application/json",
            ["Connection"] = "close",
            ["Proxy-Connection"] = "close",
        },
    }

    local lastStatus = 0
    local lastParsed = nil

    local function applyResponse(resp)
        if type(resp) ~= "table" then return end
        local status = tonumber(resp.StatusCode) or tonumber(resp.Status) or 0
        local text = resp.Body or resp.body or ""
        lastStatus = status
        lastParsed = nil
        if type(text) == "string" and text ~= "" then
            pcall(function()
                lastParsed = HttpService:JSONDecode(text)
            end)
        end
    end

    for _, reqFn in ipairs(reqList) do
        for _, hdr in ipairs(headerVariants) do
            local opts = {
                Url = KEYSYS_API_URL,
                Method = "POST",
                Headers = hdr,
                Body = payload,
            }
            local ok, resp = pcall(function()
                return reqFn(opts)
            end)
            if ok and type(resp) == "table" then
                applyResponse(resp)

                if lastStatus == 502 or lastStatus == 503 or lastStatus == 504 then
                    task.wait(0.5)
                    local ok2, resp2 = pcall(function()
                        return reqFn(opts)
                    end)
                    if ok2 and type(resp2) == "table" then
                        applyResponse(resp2)
                    end
                end

                if lastStatus >= 200 and lastStatus < 300 then
                    if type(lastParsed) == "table" then
                        if lastParsed.ok == true or lastParsed.success == true or lastParsed.allowed == true then
                            return true, tostring(lastParsed.message or "OK")
                        end
                        return false, tostring(lastParsed.message or "Denied")
                    end
                    return true, "OK"
                end

                if lastStatus ~= 407 and lastStatus ~= 417 then
                    break
                end
            end
        end
        if lastStatus ~= 407 and lastStatus ~= 417 then
            break
        end
    end

    if lastStatus == 417 then
        local hwidGet = getBestHWID()
        local sepChar = string.find(KEYSYS_API_URL, "?", 1, true) and "&" or "?"
        local getUrl = KEYSYS_API_URL
            .. sepChar
            .. "key="
            .. HttpService:UrlEncode(keyText)
            .. "&hwid="
            .. HttpService:UrlEncode(hwidGet)
            .. "&userId="
            .. HttpService:UrlEncode(tostring(LocalPlayer.UserId))
            .. "&placeId="
            .. HttpService:UrlEncode(tostring(game.PlaceId))
            .. "&gameId="
            .. HttpService:UrlEncode(tostring(game.GameId))
        local getHdr = {
            ["Accept"] = "application/json",
            ["Connection"] = "close",
        }
        for _, reqFn in ipairs(reqList) do
            local okg, respg = pcall(function()
                return reqFn({
                    Url = getUrl,
                    Method = "GET",
                    Headers = getHdr,
                })
            end)
            if okg and type(respg) == "table" then
                applyResponse(respg)
                if lastStatus == 502 or lastStatus == 503 or lastStatus == 504 then
                    task.wait(0.5)
                    local ok2, resp2 = pcall(function()
                        return reqFn({
                            Url = getUrl,
                            Method = "GET",
                            Headers = getHdr,
                        })
                    end)
                    if ok2 and type(resp2) == "table" then
                        applyResponse(resp2)
                    end
                end
                if lastStatus >= 200 and lastStatus < 300 then
                    if type(lastParsed) == "table" then
                        if lastParsed.ok == true or lastParsed.success == true or lastParsed.allowed == true then
                            return true, tostring(lastParsed.message or "OK")
                        end
                        return false, tostring(lastParsed.message or "Denied")
                    end
                    return true, "OK"
                end
            end
        end
    end

    if type(lastParsed) == "table" and type(lastParsed.message) == "string" and lastParsed.message ~= "" then
        return false, lastParsed.message
    end
    if lastStatus == 407 then
        return false, "HTTP 407: proxy blocked"
    end
    if lastStatus == 417 then
        return false, "HTTP 417: POST Expect conflict"
    end
    return false, "Auth failed (" .. tostring(lastStatus) .. ")"
end

local function setKeyStatus(text)
    if keyStatusLabel then
        keyStatusLabel:Set(text)
    end
    if keyInputStatusNative and keyInputStatusNative.Parent then
        keyInputStatusNative.Text = text
    end
end

local function applyPrivateKey(raw)
    local ok, msg = verifyKeyWithServer(raw)
    if ok then
        keyAuthed = true
        manualPrivateKey = normalizeKeyInput(raw)
        if library and library.flags then
            library.flags.private_key_input = manualPrivateKey
        end
        if keyInputBoxNative and keyInputBoxNative.Parent then
            keyInputBoxNative.Text = manualPrivateKey
        end
        pcall(function()
            savePrivateKeyToFile(manualPrivateKey)
        end)
        setKeyStatus("Key Status: AUTHORIZED")
        pcall(function()
            if keyInputGui and keyInputGui.Parent then
                keyInputGui:Destroy()
            end
        end)
        keyInputGui, keyInputBoxNative, keyInputStatusNative = nil, nil, nil
        return true
    end
    keyAuthed = false
    setKeyStatus("Key Status: " .. tostring(msg or "INVALID / LOCKED"))
    if state.orbitEnabled then setOrbitEnabled(false) end
    if state.voidEnabled then setVoidEnabled(false) end
    if state.aaEnabled then setAAEnabled(false) end
    return false
end

local function createPersistentKeyInputUI()
    local parent = getSafeGuiParent()
    local old = parent:FindFirstChild("IceLuaKeyInputPanel")
    if old then old:Destroy() end

    keyInputGui = Instance.new("ScreenGui")
    keyInputGui.Name = "IceLuaKeyInputPanel"
    keyInputGui.ResetOnSpawn = false
    keyInputGui.IgnoreGuiInset = true
    keyInputGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    keyInputGui.DisplayOrder = 999999
    keyInputGui.Parent = parent

    local frame = Instance.new("Frame")
    frame.Name = "Panel"
    frame.AnchorPoint = Vector2.new(0.5, 0)
    frame.Position = UDim2.new(0.5, 0, 0, 62)
    frame.Size = UDim2.new(0, 520, 0, 96)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
    frame.BackgroundTransparency = 0.15
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.ZIndex = 100
    frame.Parent = keyInputGui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.new(0, 12, 0, 6)
    title.Size = UDim2.new(1, -24, 0, 18)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "Ice Lua Private Key"
    title.ZIndex = 101
    title.Parent = frame

    keyInputBoxNative = Instance.new("TextBox")
    keyInputBoxNative.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
    keyInputBoxNative.BorderSizePixel = 0
    keyInputBoxNative.Position = UDim2.new(0, 12, 0, 30)
    keyInputBoxNative.Size = UDim2.new(1, -24, 0, 30)
    keyInputBoxNative.Font = Enum.Font.Gotham
    keyInputBoxNative.TextSize = 14
    keyInputBoxNative.TextColor3 = Color3.fromRGB(245, 245, 245)
    keyInputBoxNative.PlaceholderText = "Type private key here and press Enter"
    keyInputBoxNative.ClearTextOnFocus = false
    keyInputBoxNative.Text = ""
    keyInputBoxNative.ZIndex = 101
    keyInputBoxNative.Parent = frame
    Instance.new("UICorner", keyInputBoxNative).CornerRadius = UDim.new(0, 8)

    local verifyBtn = Instance.new("TextButton")
    verifyBtn.BackgroundColor3 = Color3.fromRGB(45, 78, 120)
    verifyBtn.BorderSizePixel = 0
    verifyBtn.Position = UDim2.new(0, 12, 0, 64)
    verifyBtn.Size = UDim2.new(0, 120, 0, 24)
    verifyBtn.Font = Enum.Font.GothamBold
    verifyBtn.TextSize = 12
    verifyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    verifyBtn.Text = "Verify"
    verifyBtn.ZIndex = 101
    verifyBtn.Parent = frame
    Instance.new("UICorner", verifyBtn).CornerRadius = UDim.new(0, 6)

    local lockBtn = Instance.new("TextButton")
    lockBtn.BackgroundColor3 = Color3.fromRGB(105, 52, 52)
    lockBtn.BorderSizePixel = 0
    lockBtn.Position = UDim2.new(0, 138, 0, 64)
    lockBtn.Size = UDim2.new(0, 100, 0, 24)
    lockBtn.Font = Enum.Font.GothamBold
    lockBtn.TextSize = 12
    lockBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    lockBtn.Text = "Lock"
    lockBtn.ZIndex = 101
    lockBtn.Parent = frame
    Instance.new("UICorner", lockBtn).CornerRadius = UDim.new(0, 6)

    keyInputStatusNative = Instance.new("TextLabel")
    keyInputStatusNative.BackgroundTransparency = 1
    keyInputStatusNative.Position = UDim2.new(0, 246, 0, 64)
    keyInputStatusNative.Size = UDim2.new(1, -258, 0, 24)
    keyInputStatusNative.Font = Enum.Font.Gotham
    keyInputStatusNative.TextSize = 12
    keyInputStatusNative.TextColor3 = Color3.fromRGB(210, 210, 220)
    keyInputStatusNative.TextXAlignment = Enum.TextXAlignment.Left
    keyInputStatusNative.Text = "Key Status: LOCKED"
    keyInputStatusNative.ZIndex = 101
    keyInputStatusNative.Parent = frame

    verifyBtn.MouseButton1Click:Connect(function()
        local raw = keyInputBoxNative.Text or ""
        manualPrivateKey = raw
        library.flags.private_key_input = raw
        applyPrivateKey(raw)
    end)

    keyInputBoxNative.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            local raw = keyInputBoxNative.Text or ""
            manualPrivateKey = raw
            library.flags.private_key_input = raw
            applyPrivateKey(raw)
        end
    end)

    keyInputBoxNative.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            keyInputBoxNative:CaptureFocus()
        end
    end)

    task.defer(function()
        if keyInputBoxNative and keyInputBoxNative.Parent then
            keyInputBoxNative:CaptureFocus()
        end
    end)

    lockBtn.MouseButton1Click:Connect(function()
        keyAuthed = false
        setKeyStatus("Key Status: LOCKED")
        if state.orbitEnabled then setOrbitEnabled(false) end
        if state.voidEnabled then setVoidEnabled(false) end
        if state.voidSpamEnabled then setVoidSpamEnabled(false) end
        if state.aaEnabled then setAAEnabled(false) end
    end)
end

local function createMobileToggleButton()
    local parent = getSafeGuiParent()
    local old = parent:FindFirstChild("IceLuaMobileToggle")
    if old then old:Destroy() end

    mobileToggleGui = Instance.new("ScreenGui")
    mobileToggleGui.Name = "IceLuaMobileToggle"
    mobileToggleGui.ResetOnSpawn = false
    mobileToggleGui.IgnoreGuiInset = true
    mobileToggleGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    mobileToggleGui.DisplayOrder = 999998
    mobileToggleGui.Parent = parent

    local btn = Instance.new("TextButton")
    btn.Name = "Toggle"
    btn.AnchorPoint = Vector2.new(0, 0)
    btn.Position = UDim2.new(0, 12, 0, 12)
    btn.Size = UDim2.new(0, 108, 0, 36)
    btn.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
    btn.BackgroundTransparency = 0.12
    btn.BorderSizePixel = 0
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 13
    btn.TextColor3 = Color3.fromRGB(240, 240, 250)
    btn.Text = "UI Toggle"
    btn.ZIndex = 102
    btn.Parent = mobileToggleGui
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

    btn.MouseButton1Click:Connect(function()
        pcall(function() library:Close() end)
    end)
end

local function createPersistentConfigInputUI()
    local parent = getSafeGuiParent()
    local old = parent:FindFirstChild("IceLuaConfigInputPanel")
    if old then old:Destroy() end

    configInputGui = Instance.new("ScreenGui")
    configInputGui.Name = "IceLuaConfigInputPanel"
    configInputGui.ResetOnSpawn = false
    configInputGui.IgnoreGuiInset = true
    configInputGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    configInputGui.DisplayOrder = 999997
    configInputGui.Parent = parent

    local frame = Instance.new("Frame")
    frame.Name = "Panel"
    frame.AnchorPoint = Vector2.new(0.5, 0)
    frame.Position = UDim2.new(0.5, 0, 0, 166)
    frame.Size = UDim2.new(0, 520, 0, 66)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
    frame.BackgroundTransparency = 0.15
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.ZIndex = 100
    frame.Parent = configInputGui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.new(0, 12, 0, 6)
    title.Size = UDim2.new(1, -24, 0, 16)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 13
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "Ice Lua Config Name"
    title.ZIndex = 101
    title.Parent = frame

    configInputBoxNative = Instance.new("TextBox")
    configInputBoxNative.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
    configInputBoxNative.BorderSizePixel = 0
    configInputBoxNative.Position = UDim2.new(0, 12, 0, 26)
    configInputBoxNative.Size = UDim2.new(1, -126, 0, 30)
    configInputBoxNative.Font = Enum.Font.Gotham
    configInputBoxNative.TextSize = 14
    configInputBoxNative.TextColor3 = Color3.fromRGB(245, 245, 245)
    configInputBoxNative.PlaceholderText = "Type config name and press Enter"
    configInputBoxNative.ClearTextOnFocus = false
    configInputBoxNative.Text = tostring(manualConfigName)
    configInputBoxNative.ZIndex = 101
    configInputBoxNative.Parent = frame
    Instance.new("UICorner", configInputBoxNative).CornerRadius = UDim.new(0, 8)

    local applyBtn = Instance.new("TextButton")
    applyBtn.BackgroundColor3 = Color3.fromRGB(45, 78, 120)
    applyBtn.BorderSizePixel = 0
    applyBtn.Position = UDim2.new(1, -108, 0, 26)
    applyBtn.Size = UDim2.new(0, 96, 0, 30)
    applyBtn.Font = Enum.Font.GothamBold
    applyBtn.TextSize = 12
    applyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    applyBtn.Text = "Apply Name"
    applyBtn.ZIndex = 101
    applyBtn.Parent = frame
    Instance.new("UICorner", applyBtn).CornerRadius = UDim.new(0, 8)

    local function applyNow()
        local clean = setManualConfigName(configInputBoxNative.Text or "")
        if configStatus then
            configStatus:Set("Status: name set -> " .. clean)
        end
    end

    applyBtn.MouseButton1Click:Connect(applyNow)
    configInputBoxNative.FocusLost:Connect(function(enterPressed)
        if enterPressed then applyNow() end
    end)
    configInputBoxNative.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            configInputBoxNative:CaptureFocus()
        end
    end)
end

local stopOrbit, stopVoid, stopVoidSpam, stopAA, setVoidSpamEnabled

local function startOrbit()
    if orbitConn then orbitConn:Disconnect() end
    state.orbitEnabled = true
    orbitAcc = 0
    orbitConn = RunService.Heartbeat:Connect(function(dt)
        if not state.orbitEnabled then return end
        orbitAcc = orbitAcc + dt
        if orbitAcc < ORBIT_STEP then return end
        orbitAcc = 0

        local me = getMyHRP()
        local t = getSelectedTargetPlayer()
        local thrp = getAliveTargetHRP(t)
        if not me or not thrp then return end

        local offset
        if state.orbitPattern == "Up" then
            offset = Vector3.new(0, math.random(ORBIT_DIST_MIN, ORBIT_DIST_MAX), 0)
        else
            local r = math.random(ORBIT_DIST_MIN, ORBIT_DIST_MAX)
            local yaw = math.random() * math.pi * 2
            offset = Vector3.new(math.cos(yaw) * r, 0, math.sin(yaw) * r)
        end
        pcall(function()
            me.CFrame = CFrame.new(thrp.Position + offset)
            me.AssemblyLinearVelocity = Vector3.zero
        end)
    end)
    addConn(orbitConn)
end

stopOrbit = function()
    state.orbitEnabled = false
    if orbitConn then orbitConn:Disconnect(); orbitConn = nil end
end

local function setOrbitEnabled(v)
    if v and not keyAuthed then
        if orbitToggle then orbitToggle:Toggle(false) end
        if keyStatusLabel then keyStatusLabel:Set("Key Status: INVALID / LOCKED") end
        return
    end
    if v then
        if state.voidEnabled then
            stopVoid()
            if voidToggle then voidToggle:Toggle(false) end
        end
        if state.voidSpamEnabled then
            stopVoidSpam()
            if voidSpamToggle then voidSpamToggle:Toggle(false) end
        end
        startOrbit()
    else
        stopOrbit()
    end
end

local function buildVoidAnchor(origin)
    local useX = math.random() < 0.5
    local sx = (math.random() < 0.5) and -1 or 1
    local sz = (math.random() < 0.5) and -1 or 1
    local ox = useX and (state.voidDistance * sx) or 0
    local oz = useX and 0 or (state.voidDistance * sz)
    return Vector3.new(origin.X + ox, math.max(origin.Y + 1500, 1500), origin.Z + oz)
end

local function startVoid()
    if voidConn then voidConn:Disconnect() end
    state.voidEnabled = true
    local my = getMyHRP()
    if my then
        voidReturn = my.CFrame
        voidAnchor = buildVoidAnchor(my.Position)
    end
    voidConn = RunService.Heartbeat:Connect(function()
        if not state.voidEnabled then return end
        local hrp = getMyHRP()
        if not hrp then return end
        if not voidAnchor then voidAnchor = buildVoidAnchor(hrp.Position) end
        pcall(function()
            hrp.CFrame = CFrame.new(voidAnchor)
            hrp.AssemblyLinearVelocity = Vector3.zero
        end)
    end)
    addConn(voidConn)
end

stopVoid = function()
    state.voidEnabled = false
    if voidConn then voidConn:Disconnect(); voidConn = nil end
    local hrp = getMyHRP()
    if hrp and voidReturn then
        pcall(function()
            hrp.CFrame = voidReturn
            hrp.AssemblyLinearVelocity = Vector3.zero
        end)
    end
    voidAnchor, voidReturn = nil, nil
end

local function startVoidSpam()
    if voidSpamConn then voidSpamConn:Disconnect() end
    state.voidSpamEnabled = true
    voidSpamAngle = 0
    voidSpamTarget = getSelectedTargetPlayer()
    local targetRoot = getAliveTargetHRP(voidSpamTarget)
    if not targetRoot then
        state.voidSpamEnabled = false
        voidSpamTarget = nil
        return
    end
    voidSpamCenterX, voidSpamCenterZ = targetRoot.Position.X, targetRoot.Position.Z
    voidSpamConn = RunService.Heartbeat:Connect(function(dt)
        if not state.voidSpamEnabled then return end
        local currentTarget = voidSpamTarget
        local root = getAliveTargetHRP(currentTarget)
        if not root then
            currentTarget = getSelectedTargetPlayer()
            voidSpamTarget = currentTarget
            root = getAliveTargetHRP(currentTarget)
            if root then
                voidSpamCenterX, voidSpamCenterZ = root.Position.X, root.Position.Z
            else
                return
            end
        end
        voidSpamAngle = voidSpamAngle + (VOID_SPAM_ANGULAR_SPEED * dt)

        local offsetX = math.cos(voidSpamAngle) * VOID_SPAM_RADIUS
        local offsetZ = math.sin(voidSpamAngle) * VOID_SPAM_RADIUS

        pcall(function()
            root.CFrame = CFrame.new(
                voidSpamCenterX + offsetX,
                root.Position.Y - VOID_SPAM_DROP_STUDS,
                voidSpamCenterZ + offsetZ
            )
        end)
    end)
    addConn(voidSpamConn)
end

stopVoidSpam = function()
    state.voidSpamEnabled = false
    voidSpamTarget = nil
    if voidSpamConn then voidSpamConn:Disconnect(); voidSpamConn = nil end
end

local function setVoidEnabled(v)
    if v and not keyAuthed then
        if voidToggle then voidToggle:Toggle(false) end
        if keyStatusLabel then keyStatusLabel:Set("Key Status: INVALID / LOCKED") end
        return
    end
    if v then
        if state.orbitEnabled then
            stopOrbit()
            if orbitToggle then orbitToggle:Toggle(false) end
        end
        if state.voidSpamEnabled then
            stopVoidSpam()
            if voidSpamToggle then voidSpamToggle:Toggle(false) end
        end
        startVoid()
    else
        stopVoid()
    end
end

setVoidSpamEnabled = function(v)
    if v and not keyAuthed then
        if voidSpamToggle then voidSpamToggle:Toggle(false) end
        if keyStatusLabel then keyStatusLabel:Set("Key Status: INVALID / LOCKED") end
        return
    end
    if v then
        if state.orbitEnabled then
            stopOrbit()
            if orbitToggle then orbitToggle:Toggle(false) end
        end
        if state.voidEnabled then
            stopVoid()
            if voidToggle then voidToggle:Toggle(false) end
        end
        startVoidSpam()
    else
        stopVoidSpam()
    end
end

local AA_PITCH_MODES = {
    "Off","UpsideDown","BackHead","NoHead","Jitter","ZeroG","Sway","Nod","Shake",
    "WavePitch","Bounce","SpiralPitch","Pulse","RandomStep","MicroJitter","TiltLeft","TiltRight",
}
local AA_SPECIAL_MODES = { "Off", "Forward", "Backward", "Chaos", "Tornado" }

local function nextMode(list, cur)
    local idx = table.find(list, cur) or 1
    idx = idx + 1
    if idx > #list then idx = 1 end
    return list[idx]
end

local function updateAALabels()
    if aaPitchLabel then aaPitchLabel:Set("Pitch: " .. state.aaPitchMode) end
    if aaSpinLabel then aaSpinLabel:Set(state.aaSpinOn and "Spin: ON" or "Spin: OFF") end
    if aaRollLabel then aaRollLabel:Set(state.aaRollOn and "Roll: ON" or "Roll: OFF") end
    if aaSpecialLabel then aaSpecialLabel:Set("Special: " .. state.aaSpecialMode) end
    if aaTornadoLabel then aaTornadoLabel:Set((state.aaSpecialMode == "Tornado") and "Tornado Mode: ON" or "Tornado Mode: OFF") end
    if aaIgnoreLabel then aaIgnoreLabel:Set(state.aaIgnoreAC and "Ignore AnimationController: ON" or "Ignore AnimationController: OFF") end
    if aaHardLabel then aaHardLabel:Set(state.aaHardMode and "Hard Mode: ON" or "Hard Mode: OFF") end
end

local function captureAAJoints()
    aaJoints.neck, aaJoints.waist = nil, nil
    aaBase.neckC0, aaBase.waistC0 = nil, nil
    local ch = LocalPlayer.Character
    if not ch then return end
    local upper = ch:FindFirstChild("UpperTorso")
    local head = ch:FindFirstChild("Head")
    if upper then
        for _, m in ipairs(upper:GetChildren()) do
            if m:IsA("Motor6D") and m.Name == "Waist" then
                aaJoints.waist = m
                break
            end
        end
        if not aaJoints.waist then aaJoints.waist = upper:FindFirstChildOfClass("Motor6D") end
    end
    if upper and head then
        aaJoints.neck = upper:FindFirstChild("Neck") or head:FindFirstChild("Neck")
        if not aaJoints.neck then
            for _, m in ipairs(upper:GetChildren()) do
                if m:IsA("Motor6D") and m.Part1 == head then aaJoints.neck = m break end
            end
        end
    end
    if aaJoints.neck then aaBase.neckC0 = aaJoints.neck.C0 end
    if aaJoints.waist then aaBase.waistC0 = aaJoints.waist.C0 end
end

local function restoreNoHead()
    for inst, val in pairs(aaHeadSaved) do
        pcall(function()
            if inst and inst.Parent then inst.LocalTransparencyModifier = val or 0 end
        end)
    end
    aaHeadSaved = {}
end

local function startAA()
    if aaConn then aaConn:Disconnect(); aaConn = nil end
    pcall(function() RunService:UnbindFromRenderStep(aaBindKey) end)
    captureAAJoints()
    local spinAngle, rollT = 0, 0
    local rx, ry, rz = math.random() * 10, math.random() * 10, math.random() * 10

    aaConn = RunService.RenderStepped:Connect(function() end)
    addConn(aaConn)

    RunService:BindToRenderStep(aaBindKey, Enum.RenderPriority.Last.Value, function(dt)
        if not state.aaEnabled then return end
        local hum = getMyHumanoid()
        local hrp = getMyHRP()
        if not hum or not hrp then return end
        hum.AutoRotate = false

        local rot = CFrame.new()
        local t = time()

        if state.aaPitchMode == "UpsideDown" then
            rot = rot * CFrame.Angles(math.pi, 0, 0)
        elseif state.aaPitchMode == "BackHead" then
            rot = rot * CFrame.Angles(0, math.pi, 0)
        elseif state.aaPitchMode == "NoHead" then
            if aaJoints.neck and aaBase.neckC0 then
                pcall(function() aaJoints.neck.C0 = aaBase.neckC0 * CFrame.new(0, -1.5, -0.6) end)
            end
            local ch = LocalPlayer.Character
            local head = ch and ch:FindFirstChild("Head")
            if head then
                if aaHeadSaved[head] == nil then aaHeadSaved[head] = head.LocalTransparencyModifier or 0 end
                head.LocalTransparencyModifier = 1
            end
        elseif state.aaPitchMode == "Jitter" then
            rot = rot * CFrame.Angles(math.sin(t * 18) * 0.6, 0, 0)
        elseif state.aaPitchMode == "ZeroG" then
            rot = rot * CFrame.Angles(math.sin(t * 2.2) * math.pi, 0, 0)
        elseif state.aaPitchMode == "Sway" then
            rot = rot * CFrame.Angles(0, math.sin(t * 1.8) * 0.9, 0)
        elseif state.aaPitchMode == "Nod" then
            rot = rot * CFrame.Angles(math.sin(t * 2.6) * 1.2, 0, 0)
        elseif state.aaPitchMode == "Shake" then
            rot = rot * CFrame.Angles(math.sin(t * 24) * 0.25, 0, 0)
        elseif state.aaPitchMode == "WavePitch" then
            rot = rot * CFrame.Angles(math.sin(t * 0.8) * 1.5, 0, 0)
        elseif state.aaPitchMode == "Bounce" then
            local tri = (2 / math.pi) * math.asin(math.sin(t * 2.1))
            rot = rot * CFrame.Angles(tri, 0, 0)
        elseif state.aaPitchMode == "SpiralPitch" then
            rot = rot * CFrame.Angles((t * 0.9) % (2 * math.pi), 0, 0)
        elseif state.aaPitchMode == "Pulse" then
            rot = rot * CFrame.Angles((math.sin(t * 3) >= 0) and 0.8 or -0.8, 0, 0)
        elseif state.aaPitchMode == "RandomStep" then
            rot = rot * CFrame.Angles((math.floor(t * 5) % 2 == 0) and 0.7 or -0.7, 0, 0)
        elseif state.aaPitchMode == "MicroJitter" then
            rot = rot * CFrame.Angles(math.sin(t * 40) * 0.12 + math.cos(t * 33) * 0.08, 0, 0)
        elseif state.aaPitchMode == "TiltLeft" then
            rot = rot * CFrame.Angles(0.5, 0, 0)
        elseif state.aaPitchMode == "TiltRight" then
            rot = rot * CFrame.Angles(-0.5, 0, 0)
        else
            if aaJoints.neck and aaBase.neckC0 then pcall(function() aaJoints.neck.C0 = aaBase.neckC0 end) end
            restoreNoHead()
        end

        if state.aaSpinOn and state.aaSpinSpeed > 0 then
            spinAngle = spinAngle + dt * state.aaSpinSpeed * 6
            rot = rot * CFrame.Angles(0, spinAngle, 0)
        end

        if state.aaRollOn and state.aaRollSpeed > 0 then
            local sp = state.aaRollSpeed
            local gain = 1.15 + (sp / 36) ^ 1.6
            rx = rx + dt * (sp * 8 + 1.5)
            ry = ry + dt * (sp * 9.2 + 1.3)
            rz = rz + dt * (sp * 10.4 + 1.1)
            rollT = rollT + dt * sp * 8
            local arx = (math.sin(rx * 3.2) + math.sin(rollT * 2.1) * 0.5) * math.pi * gain
            local ary = (math.cos(ry * 3.7) + math.sin(rollT * 2.9) * 0.5) * math.pi * gain
            local arz = (math.sin(rz * 4.3) + math.cos(rollT * 3.3) * 0.5) * math.pi * gain
            rot = rot * CFrame.Angles(arx, ary, arz)
        end

        if state.aaSpecialMode == "Forward" then
            rot = rot * CFrame.Angles(0.55, 0, 0)
        elseif state.aaSpecialMode == "Backward" then
            rot = rot * CFrame.Angles(-0.5, 0, 0)
        elseif state.aaSpecialMode == "Chaos" then
            local c = (math.random() - 0.5) * 0.6
            rot = rot * CFrame.Angles(0, c, 0) * CFrame.Angles(c * 0.3, 0, c * 0.4)
        elseif state.aaSpecialMode == "Tornado" then
            local sw = math.sin(t * 16) * 0.25
            spinAngle = spinAngle + dt * math.max(state.aaSpinSpeed, 18) * 2.8
            rot = rot * CFrame.Angles(0.35 + sw, spinAngle, math.sin(t * 10) * 0.18)
        end

        local base = CFrame.new(hrp.Position, hrp.Position + hrp.CFrame.LookVector)
        if not (state.aaPitchMode == "Off" and not state.aaSpinOn and not state.aaRollOn and state.aaSpecialMode == "Off") then
            hrp.CFrame = base * rot
        end
        if state.aaHardMode then hrp.AssemblyAngularVelocity = Vector3.zero end
    end)
end

stopAA = function()
    state.aaEnabled = false
    if aaConn then aaConn:Disconnect(); aaConn = nil end
    pcall(function() RunService:UnbindFromRenderStep(aaBindKey) end)
    local hum = getMyHumanoid()
    if hum then pcall(function() hum.AutoRotate = true end) end
    if aaJoints.neck and aaBase.neckC0 then pcall(function() aaJoints.neck.C0 = aaBase.neckC0 end) end
    if aaJoints.waist and aaBase.waistC0 then pcall(function() aaJoints.waist.C0 = aaBase.waistC0 end) end
    restoreNoHead()
end

local function restartAAIfNeeded()
    if state.aaEnabled then startAA() end
end

local function setAAEnabled(v)
    if v and not keyAuthed then
        if aaToggle then aaToggle:Toggle(false) end
        if keyStatusLabel then keyStatusLabel:Set("Key Status: INVALID / LOCKED") end
        return
    end
    state.aaEnabled = v
    if v then startAA() else stopAA() end
end

-- config helpers
local function fsReady()
    return type(isfolder) == "function" and type(makefolder) == "function"
        and type(listfiles) == "function" and type(isfile) == "function"
        and type(readfile) == "function" and type(writefile) == "function"
end

local function ensureFolders()
    if not fsReady() then return false, "filesystem API missing" end
    if not isfolder(ROOT_FOLDER) then makefolder(ROOT_FOLDER) end
    if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end
    return true
end

local function sanitizeName(name)
    local s = string.gsub(name or "", "^%s*(.-)%s*$", "%1")
    return string.gsub(s, "[\\/:*?\"<>|]", "_")
end

setManualConfigName = function(raw)
    local clean = sanitizeName(tostring(raw or ""))
    clean = string.gsub(clean, "^%s*(.-)%s*$", "%1")
    manualConfigName = clean
    if configNameHintLabel then
        if clean == "" then
            configNameHintLabel:Set("Config name: (empty)")
        else
            configNameHintLabel:Set("Config name: " .. clean)
        end
    end
    if library and library.flags then
        library.flags.cfg_name = clean
    end
    if configInputBoxNative and configInputBoxNative.Parent then
        configInputBoxNative.Text = clean
    end
    return clean
end

local function cfgPath(name) return CONFIG_FOLDER .. "/" .. name .. ".json" end
local function readConfigObjectByPath(path)
    if type(path) ~= "string" then return nil end
    if not string.match(path, "%.json$") then return nil end
    if not isfile(path) then return nil end
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(readfile(path))
    end)
    if not ok or type(decoded) ~= "table" then return nil end
    if type(decoded.data) ~= "table" then return nil end
    return decoded
end

local function keyName(key) return (typeof(key) == "EnumItem" and key.Name) or tostring(key) end
local function keyByName(name)
    if type(name) ~= "string" then return nil end
    for _, kc in ipairs(Enum.KeyCode:GetEnumItems()) do if kc.Name == name then return kc end end
    return nil
end

local function gatherConfig()
    return {
        target = state.target,
        orbitEnabled = state.orbitEnabled,
        orbitPattern = state.orbitPattern,
        orbitKey = keyName(state.orbitKey),
        voidEnabled = state.voidEnabled,
        voidSpamEnabled = state.voidSpamEnabled,
        voidDistance = state.voidDistance,
        voidKey = keyName(state.voidKey),
        aaEnabled = state.aaEnabled,
        aaPitchMode = state.aaPitchMode,
        aaSpinOn = state.aaSpinOn,
        aaSpinSpeed = state.aaSpinSpeed,
        aaRollOn = state.aaRollOn,
        aaRollSpeed = state.aaRollSpeed,
        aaSpecialMode = state.aaSpecialMode,
        aaIgnoreAC = state.aaIgnoreAC,
        aaHardMode = state.aaHardMode,
        aaKey = keyName(state.aaKey),
    }
end

local function applyConfig(cfg)
    if type(cfg) ~= "table" then return false end
    if type(cfg.target) == "string" then state.target = cfg.target end
    if targetDropdown then targetDropdown:Set(state.target) end
    if type(cfg.orbitPattern) == "string" then state.orbitPattern = cfg.orbitPattern end
    if type(cfg.orbitKey) == "string" then local k = keyByName(cfg.orbitKey); if k and orbitKeybind then orbitKeybind:Set(k) end end
    if type(cfg.voidKey) == "string" then local k = keyByName(cfg.voidKey); if k and voidKeybind then voidKeybind:Set(k) end end
    if type(cfg.aaKey) == "string" then local k = keyByName(cfg.aaKey); if k and aaKeybind then aaKeybind:Set(k) end end
    if type(cfg.voidDistance) == "number" and voidDistanceSlider then voidDistanceSlider:Set(cfg.voidDistance) end
    if type(cfg.voidSpamEnabled) == "boolean" and voidSpamToggle then voidSpamToggle:Toggle(cfg.voidSpamEnabled) end
    if type(cfg.aaSpinSpeed) == "number" and aaSpinSlider then aaSpinSlider:Set(cfg.aaSpinSpeed) end
    if type(cfg.aaRollSpeed) == "number" and aaRollSlider then aaRollSlider:Set(cfg.aaRollSpeed) end
    if type(cfg.aaPitchMode) == "string" then state.aaPitchMode = cfg.aaPitchMode end
    if type(cfg.aaSpinOn) == "boolean" then state.aaSpinOn = cfg.aaSpinOn end
    if type(cfg.aaRollOn) == "boolean" then state.aaRollOn = cfg.aaRollOn end
    if type(cfg.aaSpecialMode) == "string" then state.aaSpecialMode = cfg.aaSpecialMode end
    if type(cfg.aaIgnoreAC) == "boolean" then state.aaIgnoreAC = cfg.aaIgnoreAC end
    if type(cfg.aaHardMode) == "boolean" then state.aaHardMode = cfg.aaHardMode end
    if type(cfg.orbitEnabled) == "boolean" and orbitToggle then orbitToggle:Toggle(cfg.orbitEnabled) end
    if type(cfg.voidEnabled) == "boolean" and voidToggle then voidToggle:Toggle(cfg.voidEnabled) end
    if type(cfg.aaEnabled) == "boolean" and aaToggle then aaToggle:Toggle(cfg.aaEnabled) end
    updateAALabels()
    restartAAIfNeeded()
    return true
end

local function listConfigNames()
    local ok, err = ensureFolders()
    if not ok then return {}, err end
    local out = {}
    for _, p in ipairs(listfiles(CONFIG_FOLDER)) do
        local f = string.match(p, "([^/\\]+)$") or p
        local n = string.match(f, "^(.-)%.json$")
        if n and n ~= "" and readConfigObjectByPath(p) then
            table.insert(out, n)
        end
    end
    table.sort(out, function(a, b) return a:lower() < b:lower() end)
    return out
end

local function refreshConfigList(preserve)
    if not configDropdown then return end
    local names = listConfigNames()
    local cur = preserve and activeConfig or nil
    if cur and not table.find(names, cur) then cur = nil end
    configDropdown:Refresh(names)
    if #names > 0 then
        cur = cur or names[1]
        configDropdown:Set(cur)
        activeConfig = cur
    else
        activeConfig = nil
    end
end

local function createConfig(nameRaw)
    local name = sanitizeName(nameRaw)
    name = string.gsub(name, "^%s*(.-)%s*$", "%1")
    if name == "" then return false, "empty name" end
    local ok, err = ensureFolders()
    if not ok then return false, err end
    local payload = HttpService:JSONEncode({ version = 1, name = name, data = gatherConfig() })
    local okw, werr = pcall(function()
        writefile(cfgPath(name), payload)
    end)
    if not okw then return false, tostring(werr) end
    activeConfig = name
    refreshConfigList(true)
    return true
end

local function loadSelectedConfig()
    if not activeConfig then return false, "no selected config" end
    local p = cfgPath(activeConfig)
    local decoded = readConfigObjectByPath(p)
    if not decoded then return false, "invalid config json" end
    return applyConfig(decoded.data or {})
end

local function saveSelectedConfig()
    if not activeConfig then return false, "no selected config" end
    local ok, err = ensureFolders()
    if not ok then return false, err end
    writefile(cfgPath(activeConfig), HttpService:JSONEncode({ version = 1, name = activeConfig, data = gatherConfig() }))
    return true
end

local function deleteSelectedConfig()
    if not activeConfig then return false, "no selected config" end
    local ok, err = ensureFolders()
    if not ok then return false, err end

    local p = cfgPath(activeConfig)
    if not isfile(p) then return false, "file missing" end

    local delFn = delfile or deletefile
    if type(delFn) ~= "function" then
        return false, "delete API missing"
    end

    local okd, derr = pcall(function()
        delFn(p)
    end)
    if not okd then return false, tostring(derr) end
    refreshConfigList(true)
    return true
end

-- UI
local window = library:Load({
    name = "Ice Lua",
    sizex = 860,
    sizey = 680,
    theme = "Default",
    folder = "IceLuaUI",
    extension = "cfg",
})

local orbitTab = window:Tab("Orbit")
local voidTab = window:Tab("Void")
local aaTab = window:Tab("Anti Aim") or window:Tab("AntiAim") or window:Tab("AA") or orbitTab
local settingsTab = window:Tab("Settings")

local orbitTarget = orbitTab:Section({ name = "Target", side = "left" })
local orbitSec = orbitTab:Section({ name = "Orbit", side = "right" })

targetDropdown = orbitTarget:Dropdown({
    name = "Target Player",
    content = collectTargetValues(),
    default = "Closest",
    flag = "target_player",
    callback = function(v) state.target = v or "Closest" end,
})
orbitTarget:Button({ name = "Refresh Player List", callback = function() refreshTargetList(true) end })
targetLabel = orbitTarget:Label("Target: none")
distLabel = orbitTarget:Label("Distance: --")

orbitToggle = orbitSec:Toggle({
    name = "Enable Orbit",
    default = false,
    flag = "orbit_enabled",
    callback = function(v) setOrbitEnabled(v) end,
})
orbitSec:Dropdown({
    name = "Pattern",
    content = { "Random spot", "Up" },
    default = "Random spot",
    flag = "orbit_pattern",
    callback = function(v) state.orbitPattern = v or "Random spot" end,
})
orbitKeybind = orbitSec:Keybind({
    name = "Orbit Toggle Key",
    default = state.orbitKey,
    flag = "orbit_key",
    callback = function(key, fromsetting)
        if key then state.orbitKey = key end
        if not fromsetting and orbitToggle then orbitToggle:Toggle(not state.orbitEnabled) end
    end,
})

local voidSec = voidTab:Section({ name = "Void", side = "left" })
voidToggle = voidSec:Toggle({
    name = "Enable Void",
    default = false,
    flag = "void_enabled",
    callback = function(v) setVoidEnabled(v) end,
})
voidSpamToggle = voidSec:Toggle({
    name = "Enable Void Spam",
    default = false,
    flag = "void_spam_enabled",
    callback = function(v) setVoidSpamEnabled(v) end,
})
voidDistanceSlider = voidSec:Slider({
    name = "Void Distance",
    min = 1000, max = 200000000, float = 1,
    default = state.voidDistance,
    text = "[value] studs",
    flag = "void_distance",
    callback = function(v) state.voidDistance = v end,
})
voidKeybind = voidSec:Keybind({
    name = "Void Toggle Key",
    default = state.voidKey,
    flag = "void_key",
    callback = function(key, fromsetting)
        if key then state.voidKey = key end
        if not fromsetting and voidToggle then voidToggle:Toggle(not state.voidEnabled) end
    end,
})

local aaSec = aaTab:Section({ name = "Anti Aim", side = "left" })
aaToggle = aaSec:Toggle({
    name = "Enable Anti Aim",
    default = false,
    flag = "aa_enabled",
    callback = function(v) setAAEnabled(v) end,
})
aaPitchLabel = aaSec:Label("Pitch: Off")
aaSec:Button({
    name = "Next Pitch Mode",
    callback = function()
        state.aaPitchMode = nextMode(AA_PITCH_MODES, state.aaPitchMode)
        updateAALabels()
        restartAAIfNeeded()
    end,
})
aaSpinLabel = aaSec:Label("Spin: OFF")
aaSec:Button({
    name = "Toggle Spin",
    callback = function()
        state.aaSpinOn = not state.aaSpinOn
        updateAALabels()
        restartAAIfNeeded()
    end,
})
aaSpinSlider = aaSec:Slider({
    name = "Spin Speed",
    min = 1, max = 50, float = 1,
    default = state.aaSpinSpeed,
    text = "[value]",
    flag = "aa_spin",
    callback = function(v) state.aaSpinSpeed = v; restartAAIfNeeded() end,
})
aaRollLabel = aaSec:Label("Roll: OFF")
aaSec:Button({
    name = "Toggle Roll",
    callback = function()
        state.aaRollOn = not state.aaRollOn
        updateAALabels()
        restartAAIfNeeded()
    end,
})
aaRollSlider = aaSec:Slider({
    name = "Roll Speed",
    min = 0, max = 200, float = 1,
    default = state.aaRollSpeed,
    text = "[value]",
    flag = "aa_roll_speed",
    callback = function(v) state.aaRollSpeed = v; restartAAIfNeeded() end,
})
aaSpecialLabel = aaSec:Label("Special: Off")
aaSec:Button({
    name = "Next Special Mode",
    callback = function()
        state.aaSpecialMode = nextMode(AA_SPECIAL_MODES, state.aaSpecialMode)
        updateAALabels()
        restartAAIfNeeded()
    end,
})
aaTornadoLabel = aaSec:Label("Tornado Mode: OFF")
aaSec:Button({
    name = "Toggle Tornado",
    callback = function()
        state.aaSpecialMode = (state.aaSpecialMode == "Tornado") and "Off" or "Tornado"
        updateAALabels()
        restartAAIfNeeded()
    end,
})
aaHardLabel = aaSec:Label("Hard Mode: OFF")
aaSec:Button({
    name = "Toggle Hard Mode",
    callback = function()
        state.aaHardMode = not state.aaHardMode
        updateAALabels()
        restartAAIfNeeded()
    end,
})
aaIgnoreLabel = aaSec:Label("Ignore AnimationController: OFF")
aaSec:Button({
    name = "Toggle Ignore AnimationController",
    callback = function()
        state.aaIgnoreAC = not state.aaIgnoreAC
        updateAALabels()
        restartAAIfNeeded()
    end,
})
aaKeybind = aaSec:Keybind({
    name = "Anti Aim Toggle Key",
    default = state.aaKey,
    flag = "aa_key",
    callback = function(key, fromsetting)
        if key then state.aaKey = key end
        if not fromsetting and aaToggle then aaToggle:Toggle(not state.aaEnabled) end
    end,
})
updateAALabels()

local menuSec = settingsTab:Section({ name = "Menu", side = "left" })
local cfgSec = settingsTab:Section({ name = "Config", side = "right" })
local keySec = settingsTab:Section({ name = "Key System", side = "left" })

keyStatusLabel = keySec:Label("Key Status: LOCKED")
keySec:Label("Private key required")
keySec:Label("Saved key path: workspace/" .. KEY_FOLDER)
keySec:Box({
    default = "",
    placeholder = "Type private key here",
    flag = "private_key_input",
    callback = function() end,
})
keySec:Button({
    name = "Focus Native Key Input",
    callback = function()
        if keyInputBoxNative and keyInputBoxNative.Parent then
            keyInputBoxNative:CaptureFocus()
        end
    end,
})
keySec:Button({
    name = "Verify Key",
    callback = function()
        local raw = library.flags.private_key_input or manualPrivateKey or ""
        applyPrivateKey(raw)
    end,
})
keySec:Button({
    name = "Load Saved Key",
    callback = function()
        local saved = loadPrivateKeyFromFile()
        if not saved then
            setKeyStatus("Key Status: no saved key")
            return
        end
        manualPrivateKey = saved
        if library and library.flags then
            library.flags.private_key_input = saved
        end
        if keyInputBoxNative and keyInputBoxNative.Parent then
            keyInputBoxNative.Text = saved
        end
        applyPrivateKey(saved)
    end,
})
keySec:Button({
    name = "Lock Script",
    callback = function()
        keyAuthed = false
        setKeyStatus("Key Status: LOCKED")
        if state.orbitEnabled then setOrbitEnabled(false) end
        if state.voidEnabled then setVoidEnabled(false) end
        if state.voidSpamEnabled then setVoidSpamEnabled(false) end
        if state.aaEnabled then setAAEnabled(false) end
    end,
})

menuSec:Keybind({
    name = "Toggle UI",
    default = Enum.KeyCode.RightShift,
    flag = "ui_toggle",
    callback = function(_, fromsetting) if not fromsetting then library:Close() end end,
})
menuSec:Button({ name = "Unload", callback = function() runtime.cleanup() end })

configNameHintLabel = cfgSec:Label("Config name")
cfgSec:Box({
    name = "Config name",
    default = "",
    placeholder = "type config name",
    flag = "cfg_name",
    callback = function(v)
        setManualConfigName(v)
    end,
})
configDropdown = cfgSec:Dropdown({
    name = "Config List",
    content = {},
    default = nil,
    flag = "cfg_list",
    callback = function(v)
        activeConfig = v
    end,
})
cfgSec:Button({
    name = "Create Config",
    callback = function()
        if not keyAuthed then
            configStatus:Set("Status: key required")
            return
        end
        local typed = manualConfigName
        if type(typed) ~= "string" then typed = "" end
        typed = string.gsub(typed, "^%s*(.-)%s*$", "%1")
        if typed == "" and type(library.flags.cfg_name) == "string" then
            typed = string.gsub(library.flags.cfg_name, "^%s*(.-)%s*$", "%1")
        end
        typed = setManualConfigName(typed)
        if typed == "" then
            configStatus:Set("Status: type config name first")
            return
        end
        local ok, err = createConfig(typed)
        if ok then configStatus:Set("Status: saved -> " .. tostring(activeConfig))
        else configStatus:Set("Status: create failed (" .. tostring(err) .. ")") end
    end,
})
cfgSec:Button({
    name = "Save Config",
    callback = function()
        if not keyAuthed then
            configStatus:Set("Status: key required")
            return
        end
        local ok, err = saveSelectedConfig()
        if ok then configStatus:Set("Status: saved -> " .. tostring(activeConfig))
        else configStatus:Set("Status: save failed (" .. tostring(err) .. ")") end
    end,
})
cfgSec:Button({
    name = "Load Config",
    callback = function()
        if not keyAuthed then
            configStatus:Set("Status: key required")
            return
        end
        local ok, err = loadSelectedConfig()
        if ok then configStatus:Set("Status: loaded -> " .. tostring(activeConfig))
        else configStatus:Set("Status: load failed (" .. tostring(err) .. ")") end
    end,
})
cfgSec:Button({
    name = "Del Config",
    callback = function()
        if not keyAuthed then
            configStatus:Set("Status: key required")
            return
        end
        local deleting = tostring(activeConfig or "")
        local ok, err = deleteSelectedConfig()
        if ok then
            configStatus:Set("Status: deleted -> " .. deleting)
        else
            configStatus:Set("Status: delete failed (" .. tostring(err) .. ")")
        end
    end,
})
cfgSec:Button({
    name = "Refresh List",
    callback = function()
        refreshConfigList(true)
        configStatus:Set("Status: list refreshed")
    end,
})
configStatus = cfgSec:Label("Status: ready")
cfgSec:Label("Path: workspace/" .. CONFIG_FOLDER)

local wm = library:Watermark("Ice Lua")
wm:Hide()
refreshTargetList(false)
task.defer(function()
    refreshTargetList(true)
    task.delay(1.0, function() refreshTargetList(true) end)
    task.delay(3.0, function() refreshTargetList(true) end)
end)
refreshConfigList(false)
setManualConfigName(manualConfigName)
createPersistentKeyInputUI()
task.defer(function()
    local saved = loadPrivateKeyFromFile()
    if not saved then return end
    manualPrivateKey = saved
    if library and library.flags then
        library.flags.private_key_input = saved
    end
    if keyInputBoxNative and keyInputBoxNative.Parent then
        keyInputBoxNative.Text = saved
    end
    applyPrivateKey(saved)
end)
pcall(function()
    local parent = getSafeGuiParent()
    local old = parent:FindFirstChild("IceLuaConfigInputPanel")
    if old then old:Destroy() end
end)
createMobileToggleButton()

addConn(Players.PlayerAdded:Connect(function() refreshTargetList(true) end))
addConn(Players.PlayerRemoving:Connect(function() refreshTargetList(true) end))

addConn(RunService.Heartbeat:Connect(function(dt)
    runtime._acc = (runtime._acc or 0) + dt
    if runtime._acc < 0.12 then return end
    runtime._acc = 0
    local target = getSelectedTargetPlayer()
    local my = getMyHRP()
    local thrp = getAliveTargetHRP(target)
    if not keyAuthed then
        targetLabel:Set("Target: --")
        distLabel:Set("Distance: --")
        setBanner("Ice Lua | LOCKED | Enter private key")
    elseif my and target and thrp then
        local d = (my.Position - thrp.Position).Magnitude
        targetLabel:Set("Target: " .. target.Name)
        distLabel:Set(string.format("Distance: %.1f studs", d))
        setBanner(string.format("%s | Orbit:%s Void:%s AA:%s | Target:%s | Dist:%.1f",
            "Ice Lua",
            state.orbitEnabled and "ON" or "OFF",
            state.voidEnabled and "ON" or "OFF",
            state.aaEnabled and "ON" or "OFF",
            target.Name,
            d))
    elseif target then
        targetLabel:Set("Target: " .. target.Name .. " (dead/respawn)")
        distLabel:Set("Distance: --")
        setBanner(string.format("%s | Orbit:%s Void:%s AA:%s | Target:%s | Dist:--",
            "Ice Lua",
            state.orbitEnabled and "ON" or "OFF",
            state.voidEnabled and "ON" or "OFF",
            state.aaEnabled and "ON" or "OFF",
            target.Name))
    else
        targetLabel:Set("Target: none")
        distLabel:Set("Distance: --")
        setBanner(string.format("%s | Orbit:%s Void:%s AA:%s | Target:none | Dist:--",
            "Ice Lua",
            state.orbitEnabled and "ON" or "OFF",
            state.voidEnabled and "ON" or "OFF",
            state.aaEnabled and "ON" or "OFF"))
    end
end))

runtime.cleanup = function()
    pcall(stopOrbit)
    pcall(stopVoid)
    pcall(stopVoidSpam)
    pcall(stopAA)
    for _, c in ipairs(runtime.conns) do pcall(function() c:Disconnect() end) end
    runtime.conns = {}
    if bannerGui then pcall(function() bannerGui:Destroy() end) bannerGui, bannerText = nil, nil end
    if keyInputGui then pcall(function() keyInputGui:Destroy() end) keyInputGui, keyInputBoxNative, keyInputStatusNative = nil, nil, nil end
    if configInputGui then pcall(function() configInputGui:Destroy() end) configInputGui, configInputBoxNative = nil, nil end
    if mobileToggleGui then pcall(function() mobileToggleGui:Destroy() end) mobileToggleGui = nil end
    pcall(function() library:Unload() end)
    if env.__IceLuaRuntime == runtime then env.__IceLuaRuntime = nil end
end
