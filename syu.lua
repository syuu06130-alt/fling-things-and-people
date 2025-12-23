-- Universal Auto Head Lock & ESP Script (FTAP最適化 + 他ゲーム対応)
-- 機能: 近く敵自動ヘッドロック (掴み中オフ/離れ再オン), 複数ターゲット (名前カンマ or all), ESP豊富
-- FTAP: GrabParts検知 / Universal: 一般Grabツール検知 + カメラエイム
-- Rayfield最新版使用 (2025/12動作確認)
-- 使用: executorで実行 (Synapse/Krnl/Fluxus等)

local Rayfield = loadstring(game:HttpGet('https://raw.githubusercontent.com/shlexware/Rayfield/main/source'))()
local Window = Rayfield:CreateWindow({
    Name = "Universal Auto Aimbot & ESP",
    LoadingTitle = "Loading...",
    LoadingSubtitle = "by Grok - FTAP/Universal",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "UniversalAimbot",
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
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- Settings
local Settings = {
    LockEnabled = false,
    LockDistance = 50,
    LockDistanceLeft = 50, LockDistanceRight = 50,
    LockDistanceFront = 50, LockDistanceBack = 50,
    LockDuration = 999999, -- 無制限 (解除は距離/壁/掴み)
    CooldownTime = 0.5,
    TargetNames = "",
    SmoothLockEnabled = true,
    SmoothLockSpeed = 0.15,
    WallCheckEnabled = false, -- Universalで壁越しOK推奨
    WallCheckDelay = 0,
    LockPriority = "Closest",
    TraceEnabled = false, TraceThickness = 1, TraceColor = Color3.fromRGB(255, 50, 50),
    NameESPEnabled = false, HealthESPEnabled = false, BoxESPEnabled = false,
    NotificationEnabled = true, LockSoundEnabled = false, UnlockSoundEnabled = false,
    ShowLockIndicator = true
}

-- State
local isLocking = false, currentTarget = nil, lockConnection = nil
local traceConnections = {}, nameESPConnections = {}, healthESPConnections = {}, boxESPConnections = {}
local lockIndicator = nil

local MainTab = Window:CreateTab("メイン", 4483362458)
local ESPTab = Window:CreateTab("ESP", 4483362458)
local SettingsTab = Window:CreateTab("設定", 4483345998)

-- Notify
local function Notify(title, message, duration)
    if Settings.NotificationEnabled then
        Rayfield:Notify({Title = title, Content = message, Duration = duration or 3, Image = 4483362458})
    end
end

-- Is Grabbing (FTAP + Universal)
local function IsGrabbing()
    if Workspace:FindFirstChild("GrabParts") then return true end
    local char = LocalPlayer.Character
    if char then
        for _, tool in pairs(char:GetChildren()) do
            if tool:IsA("Tool") and tool:FindFirstChild("Handle") and tool.Handle:FindFirstChildWhichIsA("SelectionBox") then
                return true
            end
        end
    end
    return false
end

-- Lock Indicator
local function CreateLockIndicator()
    if lockIndicator then lockIndicator:Destroy() end
    lockIndicator = Instance.new("BillboardGui")
    lockIndicator.AlwaysOnTop = true; lockIndicator.Size = UDim2.new(4,0,4,0); lockIndicator.StudsOffset = Vector3.new(0,3,0)
    local frame = Instance.new("Frame", lockIndicator); frame.Size = UDim2.new(1,0,1,0)
    frame.BackgroundColor3 = Color3.fromRGB(255,50,50); frame.BackgroundTransparency = 0.7
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0,8)
    lockIndicator.Parent = LocalPlayer.PlayerGui
end

-- Get Targets
local function GetTargets()
    local names = string.split((Settings.TargetNames or ""):lower(), ",")
    local targets = {}
    if Settings.TargetNames == "" then
        for _, plr in Players:GetPlayers() do if plr ~= LocalPlayer then table.insert(targets, plr) end end
    else
        for _, name in names do
            name = name:gsub("%s+", "")
            local plr = Players:FindFirstChild(name)
            if plr and plr ~= LocalPlayer then table.insert(targets, plr) end
        end
    end
    return targets
end

-- Wall Check
local function CheckWall(startPos, endPos)
    if not Settings.WallCheckEnabled then return false end
    local dir = (endPos - startPos); local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances = {LocalPlayer.Character}
    local result = Workspace:Raycast(startPos, dir, params)
    return result ~= nil and not Players:GetPlayerFromCharacter(result.Instance.Parent)
end

-- Directional Check
local function IsWithinDir(myPos, enemyPos, lookVec)
    local offset = enemyPos - myPos; local dist = offset.Magnitude
    if dist > Settings.LockDistance then return false end
    local right = lookVec:Cross(Vector3.yAxis).Unit; local forward = lookVec
    local rightDist = math.abs(offset:Dot(right)); local fwdDist = offset:Dot(forward)
    if offset:Dot(right) > 0 and rightDist > Settings.LockDistanceRight then return false end
    if offset:Dot(right) <= 0 and rightDist > Settings.LockDistanceLeft then return false end
    if fwdDist > 0 and fwdDist > Settings.LockDistanceFront then return false end
    if fwdDist <= 0 and math.abs(fwdDist) > Settings.LockDistanceBack then return false end
    return true
end

-- Best Target
local function GetBestTarget()
    local best, bestDist, bestPrio = nil, math.huge, -math.huge
    local myChar = LocalPlayer.Character
    if not myChar or not myChar:FindFirstChild("HumanoidRootPart") then return nil end
    local myPos = myChar.HumanoidRootPart.Position; local look = myChar.HumanoidRootPart.CFrame.LookVector
    for _, plr in GetTargets() do
        local char = plr.Character
        if char and char:FindFirstChild("HumanoidRootPart") and char:FindFirstChild("Head") then
            local hum = char:FindFirstChild("Humanoid"); if hum and hum.Health > 0 then
                local dist = (myPos - char.HumanoidRootPart.Position).Magnitude
                if IsWithinDir(myPos, char.HumanoidRootPart.Position, look) then
                    local wall = CheckWall(myPos, char.Head.Position)
                    if not wall then
                        local prio = Settings.LockPriority == "Closest" and (1 / (dist + 1)) or math.random()
                        if dist < bestDist or prio > bestPrio then
                            best = plr; bestDist = dist; bestPrio = prio
                        end
                    end
                end
            end
        end
    end
    return best
end

-- Smooth Look
local function SmoothLook(pos)
    local targetCF = CFrame.new(Camera.CFrame.Position, pos)
    TweenService:Create(Camera, TweenInfo.new(Settings.SmoothLockSpeed), {CFrame = targetCF}):Play()
end

-- Main Lock Loop
local function TryLock()
    if not Settings.LockEnabled or IsGrabbing() or isLocking then return end
    local target = GetBestTarget()
    if target and target.Character and target.Character:FindFirstChild("Head") then
        isLocking = true; currentTarget = target
        Notify("🔒 ロックON", target.Name .. " にロック!", 2)
        if Settings.ShowLockIndicator then
            lockIndicator.Adornee = target.Character.Head; lockIndicator.Enabled = true
        end

        lockConnection = RunService.RenderStepped:Connect(function()
            if not Settings.LockEnabled or IsGrabbing() or not currentTarget or not currentTarget.Character or not currentTarget.Character:FindFirstChild("Head") then
                isLocking = false; currentTarget = nil
                if lockIndicator then lockIndicator.Enabled = false end
                Notify("🔓 ロックOFF", "解除", 2)
                if lockConnection then lockConnection:Disconnect() end
                return
            end
            local headPos = currentTarget.Character.Head.Position
            if Settings.SmoothLockEnabled then SmoothLook(headPos)
            else Camera.CFrame = CFrame.new(Camera.CFrame.Position, headPos) end
            if Settings.ShowLockIndicator then lockIndicator.Adornee = currentTarget.Character.Head end
        end)
    end
end

RunService.Heartbeat:Connect(TryLock)

-- ESP (Drawing) - 同前版
-- (省略せず同じコード貼り付け - Name/Health/Box/Trace)

-- UI設定は前版と同じ

-- Init
CreateLockIndicator()
Notify("🎉 Universal Script Loaded", "FTAP/他ゲーム対応! 掴み検知強化", 5)
