warn("### NewMap V1 ###")
if getgenv().VelvetRunning then
    getgenv().VelvetRunning = false
    task.wait(0.3)
end
getgenv().VelvetRunning = true
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local QUEST_NAME = "Velvet"

local NPC_POS = CFrame.new(
    9103.2793, 3112.6001, 4980.46582,
    -0.901375175, -0.0020259528, 0.433034271,
    5.95673919e-06, 0.999988973, 0.00469085202,
    -0.433039039, 0.00423079729, -0.90136528
)

local TALK_REMOTE = ReplicatedStorage
    :WaitForChild("Remotes")
    :WaitForChild("Misc")
    :WaitForChild("TalkingEvent")

local NAME_TO_CLONE = {
    Theodore = "Theodore Clone",
    Elizabeth = "Velvet Attendant Clone",
    Vergil = "Dark Slayer Clone",
    SpringFrieren = "Elf Mage Clone",
}

local function log(...)
    warn("[VELVET-QUEST]", ...)
end

local function getCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function getRoot()
    return getCharacter():WaitForChild("HumanoidRootPart")
end

local function getHumanoid()
    return getCharacter():FindFirstChildOfClass("Humanoid")
end

local function tp(cf)
    local root = getRoot()
    root.CFrame = cf
end

local function safeUnit(v, fallback)
    if v.Magnitude <= 0.001 then
        return fallback or Vector3.new(0, 0, 1)
    end
    return v.Unit
end

local function getQuestRoot()
    local pd = ReplicatedStorage:FindFirstChild("Players_Data")
    if not pd then return nil end

    local playerFolder = pd:FindFirstChild(LocalPlayer.Name)
    if not playerFolder then return nil end

    return playerFolder:FindFirstChild("Quest")
end

local function getVelvetQuest()
    local questRoot = getQuestRoot()
    return questRoot and questRoot:FindFirstChild(QUEST_NAME)
end

local function hasQuest()
    return getVelvetQuest() ~= nil
end

local function acceptQuest()
    log("quest missing -> go accept")

    tp(NPC_POS)
    task.wait(1)

    TALK_REMOTE:FireServer("Velvet")

    local started = tick()
    while tick() - started < 6 do
        if hasQuest() then
            log("quest accepted")
            return true
        end
        task.wait(0.2)
    end

    log("accept failed")
    return false
end

local function getCurrentQuestTarget()
    local q = getVelvetQuest()
    if not q then return nil end

    local groups = q:FindFirstChild("Defeat_Groups")
    if not groups then return nil end

    for _, g in ipairs(groups:GetChildren()) do
        local defeatNames = g:FindFirstChild("Defeat_Names")
        local numbers = g:FindFirstChild("Numbers")
        local maximum = g:FindFirstChild("Maximum")

        if defeatNames and numbers and maximum then
            local rawName = tostring(defeatNames.Value or "")
            local current = tonumber(numbers.Value) or 0
            local maxv = tonumber(maximum.Value) or 0

            if rawName ~= "" and current < maxv then
                log("TARGET:", rawName, current .. "/" .. maxv, "=>", NAME_TO_CLONE[rawName] or "unknown clone")
                return {
                    groupId = g.Name,
                    rawName = rawName, -- Theodore / Elizabeth / Vergil / SpringFrieren
                    cloneName = NAME_TO_CLONE[rawName],
                    current = current,
                    maximum = maxv,
                }
            end
        end
    end

    return nil
end

local function getServerRoot()
    local worlds = Workspace:FindFirstChild("Worlds")
    if not worlds then return nil end

    local targets = worlds:FindFirstChild("Targets")
    if not targets then return nil end

    return targets:FindFirstChild("Server")
end

local function isTargetModelName(modelName, rawQuestName)
    -- Theodore -> Theodore_1..8
    -- Elizabeth -> Elizabeth_1..7
    -- Vergil -> Vergil_1...
    -- SpringFrieren -> SpringFrieren_1...
    return modelName == rawQuestName or modelName:match("^" .. rawQuestName .. "_%d+$") ~= nil
end

local function getHumanoidFromModel(model)
    if not model or not model:IsA("Model") then return nil end
    return model:FindFirstChildOfClass("Humanoid")
end

local function getHRPFromModel(model)
    if not model or not model:IsA("Model") then return nil end
    return model:FindFirstChild("HumanoidRootPart")
end

local function getAllServerEnemies()
    local serverRoot = getServerRoot()
    local results = {}
    if not serverRoot then
        return results
    end

    -- สแกนทั้งลูกตรงๆของ Server ก่อน
    for _, obj in ipairs(serverRoot:GetChildren()) do
        if obj:IsA("Model") then
            local hum = getHumanoidFromModel(obj)
            local hrp = getHRPFromModel(obj)
            if hum and hrp then
                table.insert(results, {
                    model = obj,
                    humanoid = hum,
                    hrp = hrp,
                    name = obj.Name,
                    health = hum.Health,
                })
            end
        end
    end

    -- เผื่อบางเกมซ่อน model ไว้ในโฟลเดอร์ย่อยอีกชั้น
    for _, obj in ipairs(serverRoot:GetDescendants()) do
        if obj:IsA("Model") and obj.Parent ~= serverRoot then
            local hum = getHumanoidFromModel(obj)
            local hrp = getHRPFromModel(obj)
            if hum and hrp then
                local already = false
                for _, v in ipairs(results) do
                    if v.model == obj then
                        already = true
                        break
                    end
                end
                if not already then
                    table.insert(results, {
                        model = obj,
                        humanoid = hum,
                        hrp = hrp,
                        name = obj.Name,
                        health = hum.Health,
                    })
                end
            end
        end
    end

    return results
end

local function debugListPossibleTargets(rawQuestName)
    local hits = {}

    for _, enemy in ipairs(getAllServerEnemies()) do
        if isTargetModelName(enemy.name, rawQuestName) then
            table.insert(hits, enemy.name .. " hp=" .. math.floor(enemy.health))
        end
    end

    if #hits == 0 then
        log("DEBUG no server target found for", rawQuestName)
    else
        log("DEBUG matched server targets:", table.concat(hits, " | "))
    end
end

local function findBestServerEnemy(rawQuestName)
    local root = getRoot()
    local best, bestDist = nil, math.huge

    for _, enemy in ipairs(getAllServerEnemies()) do
        if enemy.health > 0 and isTargetModelName(enemy.name, rawQuestName) then
            local dist = (root.Position - enemy.hrp.Position).Magnitude
            if dist < bestDist then
                best = enemy
                bestDist = dist
            end
        end
    end

    return best
end

local function moveNearEnemy(enemy)
    local root = getRoot()
    local hum = getHumanoid()
    if not root or not hum or not enemy or not enemy.hrp then
        return false
    end

    local dir = safeUnit(root.Position - enemy.hrp.Position, Vector3.new(0, 0, 1))
    local desiredPos = enemy.hrp.Position + (dir * 6)
    root.CFrame = CFrame.new(desiredPos, enemy.hrp.Position)
    hum:Move(Vector3.zero, false)
    return true
end

local function getQuestProgress(groupId)
    local q = getVelvetQuest()
    if not q then return nil, "quest_removed" end

    local groups = q:FindFirstChild("Defeat_Groups")
    local group = groups and groups:FindFirstChild(groupId)
    if not group then return nil, "group_removed" end

    local numbers = group:FindFirstChild("Numbers")
    local maximum = group:FindFirstChild("Maximum")
    if not numbers or not maximum then return nil, "invalid_group" end

    return {
        current = tonumber(numbers.Value) or 0,
        maximum = tonumber(maximum.Value) or 0,
    }, nil
end

local function waitForProgress(groupId, oldValue, timeout)
    local started = tick()

    while tick() - started < (timeout or 6) do
        if not hasQuest() then
            return "quest_removed"
        end

        local info, reason = getQuestProgress(groupId)
        if not info then
            return reason or "progress_unavailable"
        end

        if info.current > oldValue then
            return "progress"
        end

        task.wait(0.1)
    end

    return "timeout"
end

local function killCurrentQuestTarget()
    local target = getCurrentQuestTarget()
    if not target then
        return false, "no_target"
    end

    local enemy = findBestServerEnemy(target.rawName)
    if not enemy then
        debugListPossibleTargets(target.rawName)
        log("enemy not found for prefix:", target.rawName)
        return false, "enemy_not_found"
    end

    log("server enemy:", enemy.name, "hp:", math.floor(enemy.health))

    local started = tick()
    while tick() - started < 20 do
        if not hasQuest() then
            return true, "quest_removed"
        end

        local latest = findBestServerEnemy(target.rawName)
        if not latest then
            local progressResult = waitForProgress(target.groupId, target.current, 2)
            if progressResult == "progress" or progressResult == "quest_removed" then
                return true, progressResult
            end
            return false, "enemy_disappeared"
        end

        moveNearEnemy(latest)

        if latest.humanoid.Health <= 0 then
            local progressResult = waitForProgress(target.groupId, target.current, 3)
            if progressResult == "progress" or progressResult == "quest_removed" then
                return true, progressResult
            end
        end

        task.wait(0.05)
    end

    return false, "kill_timeout"
end

task.spawn(function()
    while getgenv().VelvetRunning do
        if not hasQuest() then
            acceptQuest()
            task.wait(1)
            continue
        end

        local target = getCurrentQuestTarget()

        -- ถ้าไม่มี target แล้ว แต่เควสยังอยู่ อาจเป็นจบรอบแล้วรอหาย/รีเซ็ต
        if not target then
            if not hasQuest() then
                log("quest gone -> reaccept")
                task.wait(0.8)
            else
                log("all groups completed or waiting quest cleanup...")
                task.wait(0.8)

                if not hasQuest() then
                    log("quest removed after completion -> reaccept next loop")
                end
            end
            continue
        end

        local ok, reason = killCurrentQuestTarget()
        log("kill result:", ok, reason)

        if not hasQuest() then
            log("quest removed -> reaccept next loop")
            task.wait(0.8)
        else
            task.wait(0.2)
        end
    end
end)

local VirtualInputManager = game:GetService("VirtualInputManager")

task.spawn(function()
    while getgenv().VelvetRunning do
        -- กด G
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.G, false, game)
        task.wait(0.1)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.G, false, game)
        task.wait(300) -- 5 นาที = 300 วินาที
        warn("[AUTO] Pressed G")
    end
end)