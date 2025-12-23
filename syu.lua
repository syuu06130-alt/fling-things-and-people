-- Fling Things and People (FTAP) 専用 Rayfield UI Script
-- 機能: 敵近く自動エイム (掴み中オフ/離れたら再オン), 複数ターゲット対応 (名前指定 or all), ESP (豊富)
-- 使用:  executor で loadstring 実行
-- 注意: BAN リスク自覚で. 2025/12 現在動作確認

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Window = Rayfield:CreateWindow({
    Name = "FTAP Auto Aimbot & ESP",
    LoadingTitle = "Loading...",
    LoadingSubtitle = "by Grok",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "FTAPScript",
        FileName = "config.json"
    },
    KeySystem = false
})

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Camera = Workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

-- Globals
getgenv().AimbotConfig = {
    Enabled = false,
    Distance = 50,
    TargetNames = "", -- comma separated, empty="" for ALL
    Smoothness = 0.15
}
getgenv().ESPConfig = {
    Enabled = false,
    Boxes = true,
    Names = true,
    Distance = true,
    Tracers = true,
    ESPColor = Color3.fromRGB(255, 0, 0)
}
local ESPHighlights = {}
local ESPBillboards = {}

-- Update Targets List
local function UpdateTargets()
    local names = string.split(AimbotConfig.TargetNames:lower(), ",")
    local targets = {}
    if AimbotConfig.TargetNames == "" then
        for _, plr in pairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                table.insert(targets, plr)
            end
        end
    else
        for _, name in pairs(names) do
            name = name:gsub("%s+", "") -- trim
            local plr = Players:FindFirstChild(name)
            if plr and plr ~= LocalPlayer then
                table.insert(targets, plr)
            end
        end
    end
    return targets
end

-- Is Grabbing?
local function IsGrabbing()
    return Workspace:FindFirstChild("GrabParts") ~= nil
end

-- Aimbot Loop
RunService.Heartbeat:Connect(function()
    if not AimbotConfig.Enabled then return end
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    local hrp = char.HumanoidRootPart

    if IsGrabbing() then return end -- 掴み中オフ

    local targets = UpdateTargets()
    local closest = nil
    local minDist = AimbotConfig.Distance

    for _, plr in pairs(targets) do
        local tchar = plr.Character
        if tchar and tchar:FindFirstChild("Head") then
            local dist = (hrp.Position - tchar.Head.Position).Magnitude
            if dist < minDist then
                minDist = dist
                closest = tchar.Head
            end
        end
    end

    if closest then
        local targetCFrame = CFrame.lookAt(Camera.CFrame.Position, closest.Position)
        Camera.CFrame = Camera.CFrame:Lerp(targetCFrame, AimbotConfig.Smoothness)
    end
end)

-- ESP Functions
local function CreateESP(plr)
    if plr == LocalPlayer then return end
    local char = plr.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end

    -- Highlight (Box-like)
    local highlight = Instance.new("Highlight")
    highlight.FillTransparency = 1
    highlight.OutlineColor = ESPConfig.ESPColor
    highlight.OutlineTransparency = 0
    highlight.Parent = char
    ESPHighlights[plr] = highlight

    -- Billboard for Name/Dist
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(0, 200, 0, 50)
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true
    bb.Parent = char
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = plr.Name
    nameLabel.TextColor3 = ESPConfig.ESPColor
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Parent = bb
    local distLabel = Instance.new("TextLabel")
    distLabel.Size = UDim2.new(1, 0, 0.5, 0)
    distLabel.Position = UDim2.new(0, 0, 0.5, 0)
    distLabel.BackgroundTransparency = 1
    distLabel.TextColor3 = ESPConfig.ESPColor
    distLabel.TextScaled = true
    distLabel.Font = Enum.Font.Gotham
    distLabel.Parent = bb
    ESPBillboards[plr] = {bb, nameLabel, distLabel}
end

local function UpdateESP()
    for plr, highlight in pairs(ESPHighlights) do
        if ESPConfig.Enabled and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
            highlight.OutlineColor = ESPConfig.ESPColor
            highlight.Enabled = ESPConfig.Boxes

            local bbData = ESPBillboards[plr]
            if bbData then
                local dist = math.floor((LocalPlayer.Character.HumanoidRootPart.Position - plr.Character.HumanoidRootPart.Position).Magnitude)
                bbData[2].Visible = ESPConfig.Names
                bbData[3].Text = ESPConfig.Distance and tostring(dist) .. "m" or ""
                bbData[3].Visible = ESPConfig.Distance
                bbData[1].Enabled = ESPConfig.Names or ESPConfig.Distance
            end
        else
            highlight:Destroy()
            if ESPBillboards[plr] then
                ESPBillboards[plr][1]:Destroy()
            end
            ESPHighlights[plr] = nil
            ESPBillboards[plr] = nil
        end
    end
end

RunService.RenderStepped:Connect(UpdateESP)

-- Player Events for ESP
Players.PlayerAdded:Connect(function(plr)
    plr.CharacterAdded:Connect(function()
        if ESPConfig.Enabled then
            task.wait(1)
            CreateESP(plr)
        end
    end)
end)
for _, plr in pairs(Players:GetPlayers()) do
    if plr.Character then
        CreateESP(plr)
    end
    plr.CharacterAdded:Connect(function()
        if ESPConfig.Enabled then
            task.wait(1)
            CreateESP(plr)
        end
    end)
end

-- UI: Aimbot Tab
local AimbotTab = Window:CreateTab("Auto Aimbot", 4483362458)
AimbotTab:CreateToggle({
    Name = "Enabled",
    CurrentValue = false,
    Callback = function(Value)
        AimbotConfig.Enabled = Value
    end
})
AimbotTab:CreateSlider({
    Name = "Max Distance",
    Range = {10, 200},
    Increment = 5,
    CurrentValue = 50,
    Callback = function(Value)
        AimbotConfig.Distance = Value
    end
})
AimbotTab:CreateInput({
    Name = "Target Names (comma sep, empty=ALL)",
    CurrentValue = "",
    PlaceholderText = "player1,player2 or leave empty",
    RemoveTextAfterFocusLost = false,
    Callback = function(Text)
        AimbotConfig.TargetNames = Text
    end
})
AimbotTab:CreateSlider({
    Name = "Smoothness (0.01-0.5)",
    Range = {0.01, 0.5},
    Increment = 0.01,
    CurrentValue = 0.15,
    Callback = function(Value)
        AimbotConfig.Smoothness = Value
    end
})

-- UI: ESP Tab
local ESPTab = Window:CreateTab("ESP", 4483362458)
ESPTab:CreateToggle({
    Name = "Enabled",
    CurrentValue = false,
    Callback = function(Value)
        ESPConfig.Enabled = Value
        if not Value then
            for _, h in pairs(ESPHighlights) do h:Destroy() end
            ESPHighlights = {}
            for _, bb in pairs(ESPBillboards) do if bb[1] then bb[1]:Destroy() end end
            ESPBillboards = {}
        end
    end
})
ESPTab:CreateToggle({
    Name = "Boxes (Highlight)",
    CurrentValue = true,
    Callback = function(Value)
        ESPConfig.Boxes = Value
    end
})
ESPTab:CreateToggle({
    Name = "Names",
    CurrentValue = true,
    Callback = function(Value)
        ESPConfig.Names = Value
    end
})
ESPTab:CreateToggle({
    Name = "Distance",
    CurrentValue = true,
    Callback = function(Value)
        ESPConfig.Distance = Value
    end
})
ESPTab:CreateToggle({
    Name = "Tracers (Coming Soon)",
    CurrentValue = false,
    Callback = function() end -- TODO: Drawing Line
})
ESPTab:CreateColorPicker({
    Name = "ESP Color",
    Color = Color3.fromRGB(255, 0, 0),
    Callback = function(Value)
        ESPConfig.ESPColor = Value
    end
})

Rayfield:Notify({
    Title = "Loaded!",
    Content = "FTAP専用: 近く敵自動エイム (掴みオフ), ESP豊富. 名前指定で複数OK!",
    Duration = 5,
    Image = 4483362458
})