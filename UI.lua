local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local UI = {}

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
    local gui = Instance.new("ScreenGui")
    gui.Name = "RaidBossControllerUI"
    gui.ResetOnSpawn = false
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

    local frame = Instance.new("Frame")
    frame.Name = "Main"
    frame.Size = UDim2.new(0, 300, 0, 170)
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

    local info = Instance.new("TextLabel")
    info.Size = UDim2.new(1, -12, 0, 46)
    info.Position = UDim2.new(0, 6, 0, 110)
    info.BackgroundTransparency = 1
    info.TextWrapped = true
    info.TextXAlignment = Enum.TextXAlignment.Left
    info.TextYAlignment = Enum.TextYAlignment.Top
    info.Font = Enum.Font.SourceSans
    info.TextSize = 16
    info.TextColor3 = Color3.fromRGB(220,220,220)
    info.Text = "Priority: Raids ก่อน\nถ้า raid จบแล้วอยู่ช่วง boss window จะไป BossFight"
    info.Parent = frame

    return gui
end

return UI