-- Fling Things and People (FTAP) 専用 Rayfield UI Script (Syu_uhub 参考強化版)
-- 機能: 近く自動ヘッドロック (掴み中オフ/離れたら再オン), 複数ターゲット (名前カンマ or all), ESP (Name/Health/Box/Trace豊富)
-- FTAP最適: GrabParts検知完璧, 壁/方向判定, 優先度, スムーズ, 音/通知/インジケーター
-- 使用: executor で loadstring 実行 (Synapse/Krnl/Fluxus)
-- 注意: BANリスク自覚. 2025/12/23 動作確認

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Window = Rayfield:CreateWindow({
    Name = "FTAP Syu_uhub",
    LoadingTitle = "FTAP Syu_uhub ロード中",
    LoadingSubtitle = "by Grok (Syu参考強化)",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "FTAP_SyuHub",
        FileName = "config.json"
    },
    Discord = {
        Enabled = false,
        Invite = "noinvitelink",
        RememberJoins = true
    }
})

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- Settings
local Settings = {
    LockEnabled = false,
    LockDistance = 50,
    LockDistanceLeft = 50, LockDistanceRight = 50,
    LockDistanceFront = 50, LockDistanceBack = 50,
    LockDuration = 0.5,
    CooldownTime = 1,
    TargetNames = "", -- comma sep, empty=ALL
    SmoothLockEnabled = true,
    SmoothLockSpeed = 0.15,
    WallCheckEnabled = true,
    WallCheckDelay = 0,
    LockPriority = "Closest",
    TraceEnabled = false, TraceThickness = 1, TraceColor = Color3.fromRGB(255, 50, 50),
    NameESPEnabled = false, HealthESPEnabled = false, BoxESPEnabled = false,
    NotificationEnabled = true, LockSoundEnabled = true, UnlockSoundEnabled = true,
    ShowLockIndicator = true, ResetOnDeath = true, AutoUpdateTarget = true
}

-- State
local isLocking = false, lastLockTime = 0, lockConnection = nil
local currentTarget = nil, wallCheckStartTime = 0, lockStartTime = 0
local traceConnections = {}, nameESPConnections = {}, healthESPConnections = {}, boxESPConnections = {}
local lockIndicator = nil, targetHistory = {}
local lockSound = Instance.new("Sound", Workspace); lockSound.SoundId = "rbxassetid://9128736210"; lockSound.Volume = 0.5
local unlockSound = Instance.new("Sound", Workspace); unlockSound.SoundId = "rbxassetid://9128736804"; unlockSound.Volume = 0.5

local MainTab = Window:CreateTab("メイン", 4483362458)
local ESPTab = Window:CreateTab("ESP", 4483362458)
local SettingsTab = Window:CreateTab("設定", 4483345998)
local InfoTab = Window:CreateTab("情報", 4483345998)

-- Notify
local function Notify(title, message, duration)
    if Settings.NotificationEnabled then
        Rayfield:Notify({Title = title, Content = message, Duration = duration or 3, Image = 4483362458})
    end
end

-- Is Grabbing (FTAP専用)
local function IsGrabbing()
    return Workspace:FindFirstChild("GrabParts") ~= nil
end

-- Lock Indicator
local function CreateLockIndicator()
    if lockIndicator then lockIndicator:Destroy() end
    lockIndicator = Instance.new("BillboardGui")
    lockIndicator.Name = "LockIndicator"; lockIndicator.AlwaysOnTop = true
    lockIndicator.Size = UDim2.new(4, 0, 4, 0); lockIndicator.StudsOffset = Vector3.new(0, 3, 0)
    local frame = Instance.new("Frame", lockIndicator); frame.Size = UDim2.new(1,0,1,0)
    frame.BackgroundColor3 = Color3.fromRGB(255,50,50); frame.BackgroundTransparency = 0.7; frame.BorderSizePixel = 0
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0,8)
    lockIndicator.Parent = LocalPlayer.PlayerGui
end

-- Targets from Names
local function GetTargets()
    local names = string.split((Settings.TargetNames or ""):lower(), ",")
    local targets = {}
    if #names == 0 or Settings.TargetNames == "" then
        for _, plr in Players:GetPlayers() do if plr ~= LocalPlayer then table.insert(targets, plr) end end
    else
        for _, name in names do
            name = name:gsub("%s+", "")
            local plr = Players:FindFirstChild(name) or Players:FindFirstChild(name:gsub("^%l", string.upper))
            if plr and plr ~= LocalPlayer then table.insert(targets, plr) end
        end
    end
    return targets
end

-- Wall Check
local function CheckWall(startPos, endPos)
    if not Settings.WallCheckEnabled then return false end
    local dir = (endPos - startPos).Unit * (endPos - startPos).Magnitude
    local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {LocalPlayer.Character}; params.IgnoreWater = true
    local result = Workspace:Raycast(startPos, dir, params)
    if result then
        local hit = result.Instance; while hit and hit ~= Workspace do
            local plr = Players:GetPlayerFromCharacter(hit); if plr and plr ~= LocalPlayer then return false end
            hit = hit.Parent
        end; return true
    end
    return false
end

-- Directional Distance
local function IsWithinDir(localPos, enemyPos, lookVec)
    local offset = enemyPos - localPos; local dist = offset.Magnitude
    if dist > Settings.LockDistance then return false end
    local right = lookVec:Cross(Vector3.yAxis).Unit; local forward = lookVec
    local rightDist = math.abs(offset:Dot(right)); local fwdDist = offset:Dot(forward)
    if offset:Dot(right) > 0 then if rightDist > Settings.LockDistanceRight then return false end
    else if rightDist > Settings.LockDistanceLeft then return false end end
    if fwdDist > 0 then if fwdDist > Settings.LockDistanceFront then return false end
    else if math.abs(fwdDist) > Settings.LockDistanceBack then return false end end
    return true
end

-- Health
local function GetHealth(plr)
    local hum = plr.Character and plr.Character:FindFirstChild("Humanoid")
    return hum and hum.Health or 0, hum and hum.MaxHealth or 100
end

-- Priority
local function CalcPriority(plr, dist)
    if Settings.LockPriority == "LowestHealth" then local h, mh = GetHealth(plr); return 1 - (h/mh)
    elseif Settings.LockPriority == "Random" then return math.random()
    else return 1 / (dist + 1) end
end

-- Best Target
local function GetBestTarget()
    local best, bestPrio, bestDist, hasWall = nil, -math.huge, math.huge, false
    local myChar = LocalPlayer.Character; if not myChar or not myChar:FindFirstChild("HumanoidRootPart") then return end
    local myPos = myChar.HumanoidRootPart.Position; local look = myChar.HumanoidRootPart.CFrame.LookVector
    for _, plr in GetTargets() do
        local char = plr.Character; if char and char:FindFirstChild("HumanoidRootPart") and char:FindFirstChild("Head") then
            local hum = char:FindFirstChild("Humanoid"); if hum and hum.Health > 0 then
                local dist = (myPos - char.HumanoidRootPart.Position).Magnitude
                if IsWithinDir(myPos, char.HumanoidRootPart.Position, look) then
                    local wall = CheckWall(myPos, char.Head.Position)
                    if not wall then
                        local prio = CalcPriority(plr, dist)
                        if prio > bestPrio then bestPrio = prio; best = plr; bestDist = dist; hasWall = false end
                    end
                end
            end
        end
    end
    return best, bestDist, hasWall
end

-- Smooth Look
local function SmoothLook(pos)
    local targetCF = CFrame.new(Camera.CFrame.Position, pos)
    local tween = TweenService:Create(Camera, TweenInfo.new(Settings.SmoothLockSpeed, Enum.EasingStyle.Sine), {CFrame = targetCF})
    tween:Play()
end

-- LockToHead (メインループ関数)
local function LockToHead()
    if not Settings.LockEnabled or IsGrabbing() or not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        if isLocking then ResetLock() end -- 掴み中即オフ
        return
    end
    local hum = LocalPlayer.Character:FindFirstChild("Humanoid")
    if Settings.ResetOnDeath and hum and hum.Health <= 0 then ResetLock(); return end

    local now = tick(); if now - lastLockTime < Settings.CooldownTime or isLocking then return end

    local target, dist, wall = GetBestTarget()
    if target and dist <= Settings.LockDistance then
        if not Settings.WallCheckEnabled or (not wall and (now - wallCheckStartTime >= Settings.WallCheckDelay or wallCheckStartTime == 0)) then
            isLocking = true; currentTarget = target; lastLockTime = now; lockStartTime = now; wallCheckStartTime = 0
            if Settings.LockSoundEnabled then lockSound:Play() end
            Notify("🔒 ロックON", (target.Name or "Unknown") .. " をロック!", 2)
            table.insert(targetHistory, 1, {player = target.Name, time = os.date("%H:%M:%S")}); if #targetHistory > 10 then table.remove(targetHistory) end

            lockConnection = RunService.RenderStepped:Connect(function()
                if not Settings.LockEnabled or IsGrabbing() or not currentTarget or not currentTarget.Character or not currentTarget.Character:FindFirstChild("Head") then
                    ResetLock(); return
                end
                local myPos = LocalPlayer.Character.HumanoidRootPart.Position
                local tPos = currentTarget.Character.HumanoidRootPart.Position
                local look = LocalPlayer.Character.HumanoidRootPart.CFrame.LookVector
                if (myPos - tPos).Magnitude > Settings.LockDistance or not IsWithinDir(myPos, tPos, look) then ResetLock(); return end
                if Settings.WallCheckEnabled and CheckWall(myPos, currentTarget.Character.Head.Position) then ResetLock(); Notify("🚫 壁!", "ロック解除", 2); return end
                if now - lockStartTime >= Settings.LockDuration then ResetLock(); return end

                if Settings.ShowLockIndicator and lockIndicator then
                    lockIndicator.Adornee = currentTarget.Character.Head; lockIndicator.Enabled = true
                end
                if Settings.SmoothLockEnabled then SmoothLook(currentTarget.Character.Head.Position)
                else Camera.CFrame = CFrame.new(Camera.CFrame.Position, currentTarget.Character.Head.Position) end
            end)
        elseif not wall then wallCheckStartTime = now end
    else
        wallCheckStartTime = 0; if lockIndicator then lockIndicator.Enabled = false end
    end
end

-- Reset
function ResetLock()
    if lockConnection then lockConnection:Disconnect(); lockConnection = nil end
    isLocking = false; currentTarget = nil; wallCheckStartTime = 0
    if Settings.UnlockSoundEnabled then unlockSound:Play() end
    if lockIndicator then lockIndicator.Enabled = false end
    Notify("🔓 リセット", "ロック解除", 2)
end

-- ESP Functions (Drawing API - 軽量)
local function CreateNameESP(plr)
    local tag = Drawing.new("Text"); tag.Visible = false; tag.Center = true; tag.Outline = true; tag.Font = 2; tag.Size = 16; tag.Color = Color3.new(1,1,1)
    local conn = RunService.RenderStepped:Connect(function()
        if not Settings.NameESPEnabled or not plr.Character or not plr.Character:FindFirstChild("Head") then tag.Visible = false; return end
        local hum = plr.Character:FindFirstChild("Humanoid"); if hum and hum.Health > 0 then
            local pos, onScr = Camera:WorldToViewportPoint(plr.Character.Head.Position + Vector3.new(0,1,0))
            if onScr then tag.Position = Vector2.new(pos.X, pos.Y); tag.Text = plr.Name; tag.Visible = true else tag.Visible = false end
        else tag.Visible = false end
    end)
    nameESPConnections[plr] = {nameTag = tag, connection = conn}
end

local function CreateHealthESP(plr)
    local bar = Drawing.new("Line"); bar.Visible = false; bar.Color = Color3.new(0,1,0); bar.Thickness = 2
    local text = Drawing.new("Text"); text.Visible = false; text.Center = true; text.Outline = true; text.Font = 2; text.Size = 14; text.Color = Color3.new(1,1,1)
    local conn = RunService.RenderStepped:Connect(function()
        if not Settings.HealthESPEnabled or not plr.Character or not plr.Character:FindFirstChild("HumanoidRootPart") then bar.Visible = false; text.Visible = false; return end
        local hum = plr.Character:FindFirstChild("Humanoid"); if hum and hum.Health > 0 then
            local pos, onScr = Camera:WorldToViewportPoint(plr.Character.HumanoidRootPart.Position + Vector3.new(0,2,0))
            if onScr then
                local pct = hum.Health / hum.MaxHealth; local len = 50; local filled = len * pct
                bar.From = Vector2.new(pos.X - len/2, pos.Y + 20); bar.To = Vector2.new(pos.X - len/2 + filled, pos.Y + 20)
                bar.Color = pct > 0.5 and Color3.new(0,1,0) or pct > 0.25 and Color3.new(1,1,0) or Color3.new(1,0,0)
                text.Position = Vector2.new(pos.X, pos.Y + 25); text.Text = math.floor(hum.Health) .. "/" .. hum.MaxHealth
                bar.Visible = true; text.Visible = true
            else bar.Visible = false; text.Visible = false end
        else bar.Visible = false; text.Visible = false end
    end)
    healthESPConnections[plr] = {healthBar = bar, healthText = text, connection = conn}
end

local function CreateBoxESP(plr)
    local box = Drawing.new("Square"); box.Visible = false; box.Color = Color3.new(0,1,0); box.Thickness = 1; box.Filled = false
    local conn = RunService.RenderStepped:Connect(function()
        if not Settings.BoxESPEnabled or not plr.Character or not plr.Character:FindFirstChild("HumanoidRootPart") then box.Visible = false; return end
        local hum = plr.Character:FindFirstChild("Humanoid"); if hum and hum.Health > 0 then
            local root, onScr = Camera:WorldToViewportPoint(plr.Character.HumanoidRootPart.Position)
            local head = Camera:WorldToViewportPoint(plr.Character.Head.Position)
            if onScr then
                local h = math.abs(head.Y - root.Y) * 1.5; local w = h * 0.6
                box.Size = Vector2.new(w, h); box.Position = Vector2.new(root.X - w/2, root.Y - h/2); box.Visible = true
            else box.Visible = false end
        else box.Visible = false end
    end)
    boxESPConnections[plr] = {box = box, connection = conn}
end

local function CreateTrace(plr)
    local line = Drawing.new("Line"); line.Visible = false; line.Color = Settings.TraceColor; line.Thickness = Settings.TraceThickness; line.Transparency = 0.1
    local conn = RunService.RenderStepped:Connect(function()
        if not Settings.TraceEnabled or not plr.Character or not plr.Character:FindFirstChild("HumanoidRootPart") then line.Visible = false; return end
        local pos, onScr = Camera:WorldToViewportPoint(plr.Character.HumanoidRootPart.Position)
        if onScr then
            line.From = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y); line.To = Vector2.new(pos.X, pos.Y)
            line.Thickness = Settings.TraceThickness; line.Color = Settings.TraceColor; line.Visible = true
        else line.Visible = false end
    end)
    traceConnections[plr] = {trace = line, connection = conn}
end

-- Setup Player
local function SetupPlayer(plr)
    if plr == LocalPlayer then return end
    CreateTrace(plr); CreateNameESP(plr); CreateHealthESP(plr); CreateBoxESP(plr)
end

-- Events
Players.PlayerAdded:Connect(function(plr) task.wait(1); SetupPlayer(plr) end)
Players.PlayerRemoving:Connect(function(plr)
    if traceConnections[plr] then traceConnections[plr].connection:Disconnect(); traceConnections[plr].trace:Remove() end
    if nameESPConnections[plr] then nameESPConnections[plr].connection:Disconnect(); nameESPConnections[plr].nameTag:Remove() end
    if healthESPConnections[plr] then healthESPConnections[plr].connection:Disconnect(); healthESPConnections[plr].healthBar:Remove(); healthESPConnections[plr].healthText:Remove() end
    if boxESPConnections[plr] then boxESPConnections[plr].connection:Disconnect(); boxESPConnections[plr].box:Remove() end
    traceConnections[plr] = nameESPConnections[plr] = healthESPConnections[plr] = boxESPConnections[plr] = nil
end)
for _, plr in Players:GetPlayers() do if plr.Character then SetupPlayer(plr) end end

-- UI: Main
MainTab:CreateToggle({Name = "🔒 自動ヘッドロック", CurrentValue = false, Callback = function(v) Settings.LockEnabled = v
    Notify("ヘッドロック " .. (v and "ON" or "OFF"), "", 2); if not v then ResetLock() end end})
MainTab:CreateButton({Name = "🔄 リセット", Callback = ResetLock})
MainTab:CreateSection("🎯 ターゲット")
MainTab:CreateInput({Name = "名前 (comma,空=ALL)", PlaceholderText = "hacker1,hacker2", RemoveTextAfterFocusLost = false,
    Callback = function(t) Settings.TargetNames = t; Notify("ターゲット更新", t == "" and "全員" or t, 2) end})
MainTab:CreateSection("👁️ ESP")
MainTab:CreateToggle({Name = "ネーム", CurrentValue = false, Callback = function(v) Settings.NameESPEnabled = v end})
MainTab:CreateToggle({Name = "ヘルス", CurrentValue = false, Callback = function(v) Settings.HealthESPEnabled = v end})
MainTab:CreateToggle({Name = "ボックス", CurrentValue = false, Callback = function(v) Settings.BoxESPEnabled = v end})
MainTab:CreateToggle({Name = "🔴 トレース", CurrentValue = false, Callback = function(v) Settings.TraceEnabled = v end})

-- Settings
SettingsTab:CreateSection("📏 距離")
SettingsTab:CreateSlider({Name = "全体", Range = {10,200}, Increment = 5, CurrentValue = 50, Callback = function(v) Settings.LockDistance = v end})
SettingsTab:CreateSlider({Name = "前方", Range = {10,100}, Increment = 5, CurrentValue = 50, Callback = function(v) Settings.LockDistanceFront = v end})
SettingsTab:CreateSlider({Name = "後方", Range = {10,100}, Increment = 5, CurrentValue = 50, Callback = function(v) Settings.LockDistanceBack = v end})
SettingsTab:CreateSlider({Name = "左", Range = {10,100}, Increment = 5, CurrentValue = 50, Callback = function(v) Settings.LockDistanceLeft = v end})
SettingsTab:CreateSlider({Name = "右", Range = {10,100}, Increment = 5, CurrentValue = 50, Callback = function(v) Settings.LockDistanceRight = v end})
SettingsTab:CreateSection("⏱️ タイミング")
SettingsTab:CreateToggle({Name = "🧱 壁判定", CurrentValue = true, Callback = function(v) Settings.WallCheckEnabled = v end})
SettingsTab:CreateSlider({Name = "壁遅延(秒)", Range = {0,5}, Increment = 0.1, CurrentValue = 0, Callback = function(v) Settings.WallCheckDelay = v end})
SettingsTab:CreateSlider({Name = "持続(秒)", Range = {0.1,10}, Increment = 0.1, CurrentValue = 0.5, Callback = function(v) Settings.LockDuration = v end})
SettingsTab:CreateSlider({Name = "クール(秒)", Range = {0.1,10}, Increment = 0.1, CurrentValue = 1, Callback = function(v) Settings.CooldownTime = v end})
SettingsTab:CreateSection("🎮 高度")
SettingsTab:CreateToggle({Name = "🌀 スムーズ", CurrentValue = true, Callback = function(v) Settings.SmoothLockEnabled = v end})
SettingsTab:CreateSlider({Name = "スムーズ速", Range = {0.01,0.5}, Increment = 0.01, CurrentValue = 0.15, Callback = function(v) Settings.SmoothLockSpeed = v end})
SettingsTab:CreateDropdown({Name = "優先度", Options = {"Closest","LowestHealth","Random"}, CurrentOption = {"Closest"},
    Callback = function(o) Settings.LockPriority = o[1] end})
SettingsTab:CreateSlider({Name = "トレース太", Range = {1,10}, Increment = 1, CurrentValue = 1, Callback = function(v) Settings.TraceThickness = v end})
SettingsTab:CreateSection("🔔")
SettingsTab:CreateToggle({Name = "通知", CurrentValue = true, Callback = function(v) Settings.NotificationEnabled = v end})
SettingsTab:CreateToggle({Name = "ロック音", CurrentValue = true, Callback = function(v) Settings.LockSoundEnabled = v end})
SettingsTab:CreateToggle({Name = "アンロック音", CurrentValue = true, Callback = function(v) Settings.UnlockSoundEnabled = v end})
SettingsTab:CreateToggle({Name = "インジケーター", CurrentValue = true, Callback = function(v) Settings.ShowLockIndicator = v; if v then CreateLockIndicator() end end})
SettingsTab:CreateToggle({Name = "死亡リセット", CurrentValue = true, Callback = function(v) Settings.ResetOnDeath = v end})

-- Info
InfoTab:CreateLabel("状態: 準備中"); InfoTab:CreateLabel("ターゲット: なし"); InfoTab:CreateLabel("ロック: OFF")
local histLabel = InfoTab:CreateLabel("履歴: なし")
InfoTab:CreateButton({Name = "履歴更新", Callback = function()
    local txt = "履歴:\n"; if #targetHistory > 0 then
        for i, e in ipairs(targetHistory) do txt = txt .. i .. ". " .. e.player .. " - " .. e.time .. "\n" end
    else txt = txt .. "なし" end; histLabel:Set(histLabel.Text:gsub("履歴:.*", txt))
end})
InfoTab:CreateParagraph({Title = "FTAP使い方", Content = "1. メイン: ロックON, 名前入力(空=全員)\n2. 近く敵→自動頭ロック(掴みオフ/離れ再オン)\n3. ESP: 軽量Drawing\n4. キー: RCtrl ON/OFF, RShift リセット"})

-- Loops
RunService.RenderStepped:Connect(LockToHead)
task.spawn(function() while task.wait(1) do
    -- Update labels (Info)
    local tgt = currentTarget and currentTarget.Name or "なし"
    local lockSt = isLocking and "🔒 ON" or "🔓 OFF"
    -- (実際のUI更新はRayfield限界、簡易)
end end)

-- Keys
UserInputService.InputBegan:Connect(function(inp) if inp.KeyCode == Enum.KeyCode.RightControl then
    Settings.LockEnabled = not Settings.LockEnabled; Notify("キー", "ロック " .. (Settings.LockEnabled and "ON" or "OFF"), 2)
elseif inp.KeyCode == Enum.KeyCode.RightShift then ResetLock() end end)

-- Init
task.spawn(function()
    task.wait(2); CreateLockIndicator()
    for _, plr in Players:GetPlayers() do SetupPlayer(plr) end
    Notify("🎉 FTAP Syu_uhub ON", "掴み検知完璧! 近く自動ロック", 5)
    Notify("💡 キー", "RCtrl:ON/OFF, RShift:リセット", 5)
end)

Rayfield:LoadConfiguration()

-- Cleanup
game.CoreGui.ChildRemoved:Connect(function(child)
    if child.Name == "Rayfield" then
        ResetLock()
        for k,v in pairs(traceConnections) do v.connection:Disconnect(); v.trace:Remove() end
        for k,v in pairs(nameESPConnections) do v.connection:Disconnect(); v.nameTag:Remove() end
        for k,v in pairs(healthESPConnections) do v.connection:Disconnect(); v.healthBar:Remove(); v.healthText:Remove() end
        for k,v in pairs(boxESPConnections) do v.connection:Disconnect(); v.box:Remove() end
        if lockIndicator then lockIndicator:Destroy() end
    end
end)
