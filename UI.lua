local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local UI = {}
local domainBirdcageLabel
local function makeToggle(parent, text, defaultValue, onChanged, order)
    local row = Instance.new("Frame")
    row.Name = text .. "_Row"
    row.Size = UDim2.new(1, -12, 0, 32)
    row.Position = UDim2.new(0, 6, 0, 8 + ((order - 1) * 36))
    row.BackgroundTransparency = 1
    row.Parent = parent

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.7, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Font = Enum.Font.SourceSansBold
    label.TextSize = 18
    label.TextColor3 = Color3.fromRGB(255,255,255)
    label.Text = text
    label.Parent = row

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 90, 0, 28)
    btn.Position = UDim2.new(1, -90, 0.5, -14)
    btn.Font = Enum.Font.SourceSansBold
    btn.TextSize = 18
    btn.Parent = row

    local value = defaultValue

    local function redraw()
        btn.Text = value and "ON" or "OFF"
        btn.BackgroundColor3 = value and Color3.fromRGB(60, 170, 90) or Color3.fromRGB(170, 60, 60)
        btn.TextColor3 = Color3.new(1,1,1)
    end

    btn.MouseButton1Click:Connect(function()
        value = not value
        redraw()
        if onChanged then
            onChanged(value)
        end
    end)

    redraw()
    return row, btn
end

function UI.init(State)
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")

    local oldGui = playerGui:FindFirstChild("RaidBossControllerUI")
    if oldGui then
        oldGui:Destroy()
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "RaidBossControllerUI"
    gui.ResetOnSpawn = false
    gui.Parent = playerGui

    local frame = Instance.new("Frame")
    frame.Name = "Main"
    frame.Size = UDim2.new(0, 300, 0, 240)
    frame.Position = UDim2.new(0, 20, 0, 120)
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    frame.BorderSizePixel = 0
    frame.Parent = gui

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 36)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.SourceSansBold
    title.TextSize = 22
    title.TextColor3 = Color3.fromRGB(255,255,255)
    title.Text = "Raid / Boss Controller"
    title.Parent = frame

    makeToggle(frame, "Raids", State.toggles.raids, function(v)
        State.toggles.raids = v
    end, 1)

    makeToggle(frame, "BossFight", State.toggles.bossFight, function(v)
    State.toggles.bossFight = v
    end, 2)

    makeToggle(frame, "GlobalBosses", State.toggles.globalBosses, function(v)
    State.toggles.globalBosses = v
    end, 3)

    domainBirdcageLabel = Instance.new("TextLabel")
    domainBirdcageLabel.Name = "DomainBirdcageLabel"
    domainBirdcageLabel.Size = UDim2.new(1, -12, 0, 24)
    domainBirdcageLabel.Position = UDim2.new(0, 6, 0, 122)
    domainBirdcageLabel.BackgroundTransparency = 1
    domainBirdcageLabel.TextWrapped = false
    domainBirdcageLabel.TextXAlignment = Enum.TextXAlignment.Left
    domainBirdcageLabel.TextYAlignment = Enum.TextYAlignment.Center
    domainBirdcageLabel.Font = Enum.Font.SourceSansBold
    domainBirdcageLabel.TextSize = 18
    domainBirdcageLabel.TextColor3 = Color3.fromRGB(255, 230, 120)
    domainBirdcageLabel.Text = "DomainBirdcage: " .. tostring(State.runtime.domainBirdcageCount or 0)
    domainBirdcageLabel.Parent = frame

    local info = Instance.new("TextLabel")
    info.Size = UDim2.new(1, -12, 0, 72)
    info.Position = UDim2.new(0, 6, 0, 150)
    info.BackgroundTransparency = 1
    info.TextWrapped = true
    info.TextXAlignment = Enum.TextXAlignment.Left
    info.TextYAlignment = Enum.TextYAlignment.Top
    info.Font = Enum.Font.SourceSans
    info.TextSize = 16
    info.TextColor3 = Color3.fromRGB(220,220,220)
    info.Text = "Priority:\n1) GlobalBoss portal มา -> ทิ้ง raid ไปทันที\n2) ถ้า DomainBirdcage >= 10 -> ฟาร์ม GlobalBoss จนเหลือ 0\n3) ที่เหลือค่อยวิ่ง Raid / BossFight"
    info.Parent = frame

    return gui
end

function UI.updateDomainBirdcage(count)
 if domainBirdcageLabel then
  domainBirdcageLabel.Text = "DomainBirdcage: " .. tostring(count or 0)
 end
end

return UI