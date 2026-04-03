warn("### SIMPLE AUTORAID ONE FILE BUILD ###")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer

-- =========================
-- CONFIG
-- =========================
local CONFIG = {
    raidMap = "Jujutsu Highschool",
    raidDifficulty = "Nightmare",

    podName = "Pod_01",

    attackOffset = 3.0,          -- ระยะยืนห่างมอน
    teleportThreshold = 1.5,     -- ถ้าห่างจากจุดยืนเกินนี้ค่อยวาร์ปใหม่
    autoAttackRefresh = 1.5,     -- กดเปิด auto attack ซ้ำทุกกี่วิ
    scanInterval = 0.05,         -- ความถี่ loop ตอนตีมอน
    enterRaidTimeout = 15,
    firstEnemyTimeout = 10,
    chestWaitTimeout = 10,

    nextWaveWait = 3,      -- รอ wave ใหม่
    nextWavePoll = 0.1,    -- ความถี่ตอนรอ wave ใหม่
    debug = true,
}

-- =========================
-- HELPERS
-- =========================
local function log(...)
    warn("[SIMPLE-RAID]", ...)
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

local function safeUnit(v, fallback)
    if v.Magnitude <= 0.001 then
        return fallback or Vector3.new(0, 0, 1)
    end
    return v.Unit
end

local function getParty()
    return ReplicatedStorage
        :WaitForChild("Shared")
        :WaitForChild("Parties")
        :WaitForChild(LocalPlayer.Name)
end

local function getRaidLobbyRemote()
    return ReplicatedStorage
        :WaitForChild("Remotes")
        :WaitForChild("Gameplays")
        :WaitForChild("RaidsLobbies")
end

local function getRaidStartRemote()
    return ReplicatedStorage
        :WaitForChild("Remotes")
        :WaitForChild("Systems")
        :WaitForChild("RaidsEvent")
end

local function getPartyRemote()
    return ReplicatedStorage
        :WaitForChild("Remotes")
        :WaitForChild("Misc")
        :WaitForChild("Parties")
end

local function getByteNetReliable()
    return ReplicatedStorage:WaitForChild("ByteNetReliable")
end

local RaidPods = {
    Pod_01 = Workspace:WaitForChild("Raids_Entering"):WaitForChild("Pod_01"),
}

local RaidMapAlias = {
    ["Jujutsu Highschool"] = "Worlds_Jujutsu Highschool",
}

local RaidDifficultyAlias = {
    ["Nightmare"] = "Diffculty_Nightmare",
    ["Hard"] = "Diffculty_Hard",
    ["Normal"] = "Diffculty_Normal",
    ["Easy"] = "Diffculty_Easy",
}

local function tpTo(cf)
    local root = getRoot()
    root.CFrame = cf
    return true
end

local function refreshAutoAttack(state)
    if not state.lastAutoAttackAt or (tick() - state.lastAutoAttackAt >= CONFIG.autoAttackRefresh) then
        getByteNetReliable():FireServer(buffer.fromstring("\016\000"))
        state.lastAutoAttackAt = tick()
        if CONFIG.debug then
            log("auto attack refreshed")
        end
    end
end

-- =========================
-- RAID ENTRY
-- =========================
local function goToChallengesLobby()
    log("goToChallengesLobby")
    getByteNetReliable():FireServer(buffer.fromstring("\005\005\000Lobby"))
    return true
end

local function teleportToRaidPod(podName)
    podName = podName or CONFIG.podName
    local pod = RaidPods[podName]
    if not pod then
        log("no pod:", podName)
        return false
    end

    if pod:IsA("Model") then
        return tpTo(pod.WorldPivot)
    end

    local center = pod:FindFirstChild("Centers")
    if center and center:IsA("BasePart") then
        return tpTo(center.CFrame)
    end

    return false
end

local function stepIntoRaidPod(podName)
    podName = podName or CONFIG.podName
    local pod = RaidPods[podName]
    if not pod then
        log("no pod:", podName)
        return false
    end

    local root = getRoot()

    if pod:IsA("Model") then
        root.CFrame = pod.WorldPivot
        return true
    end

    local center = pod:FindFirstChild("Centers")
    if center and center:IsA("BasePart") then
        root.CFrame = center.CFrame
        return true
    end

    return false
end

local function selectRaidMap(mapName)
    local mapped = RaidMapAlias[mapName] or mapName
    local party = getParty()
    log("selectRaidMap:", mapped)
    getRaidLobbyRemote():FireServer(party, mapped)
    return true
end

local function selectRaidDifficulty(diffName)
    local mapped = RaidDifficultyAlias[diffName] or diffName
    local party = getParty()
    log("selectRaidDifficulty:", mapped)
    getRaidLobbyRemote():FireServer(party, mapped)
    return true
end

local function startRaid(mapName, diffName)
    log("startRaid:", mapName, diffName)
    getRaidStartRemote():FireServer(mapName, diffName)
    return true
end

local function confirmRaidLobby()
    log("confirmRaidLobby")
    local args = { Instance.new("Folder"), true }
    getRaidLobbyRemote():FireServer(unpack(args))
    return true
end

local function disableParty()
    log("disableParty")
    getPartyRemote():FireServer("Disabled")
    return true
end

local function getRaidFolders(containerName)
    local root = workspace:FindFirstChild("Worlds")
    root = root and root:FindFirstChild("Targets")
    root = root and root:FindFirstChild(containerName or "Clients")

    local results = {}
    if not root then
        return results
    end

    for _, obj in ipairs(root:GetChildren()) do
        if obj.Name:match("^Raids") then
            table.insert(results, obj)
        end
    end

    return results
end

local function isInRaid()
    return #getRaidFolders("Server") > 0 or #getRaidFolders("Clients") > 0
end
local getEnemies
local function waitForNextWaveOrDone(state)
    local started = tick()
    local maxWait = CONFIG.nextWaveWait or 3
    local poll = CONFIG.nextWavePoll or 0.1

    while tick() - started < maxWait do
        refreshAutoAttack(state)

        local enemies = getEnemies()
        if #enemies > 0 then
            log("next wave detected:", #enemies)
            return false
        end

        task.wait(poll)
    end

    log("no new wave after wait => raid finished")
    return true
end

local function waitUntilInRaid(timeout)
    local started = tick()
    while tick() - started < (timeout or CONFIG.enterRaidTimeout) do
        if isInRaid() then
            log("raid instance detected")
            return true
        end
        task.wait(0.25)
    end
    log("timed out waiting for raid instance")
    return false
end

local function enterRaid(mapName, diffName)
    log("enterRaid:", mapName, diffName)

    goToChallengesLobby()
    task.wait(1.2)

    teleportToRaidPod(CONFIG.podName)
    task.wait(0.5)

    stepIntoRaidPod(CONFIG.podName)
    task.wait(1.0)

    selectRaidMap(mapName)
    task.wait(0.35)

    selectRaidDifficulty(diffName)
    task.wait(0.35)

    startRaid(mapName, diffName)
    task.wait(0.35)

    confirmRaidLobby()
    task.wait(0.2)

    disableParty()
    task.wait(0.5)

    return true
end

-- =========================
-- ENEMY
-- =========================
function getEnemies()
    local clientFolders = getRaidFolders("Clients")
    local serverFolders = getRaidFolders("Server")

    local results = {}
    local seen = {}

    -- map ชื่อ model จาก server -> hp จริง
    local serverHP = {}

    for _, folder in ipairs(serverFolders) do
        for _, obj in ipairs(folder:GetDescendants()) do
            if obj:IsA("Humanoid") then
                local model = obj.Parent
                if model then
                    serverHP[model.Name] = obj.Health
                end
            end
        end
    end

    -- ใช้ client model สำหรับตำแหน่ง/วาร์ป
    for _, folder in ipairs(clientFolders) do
        for _, obj in ipairs(folder:GetDescendants()) do
            if obj:IsA("Humanoid") then
                local model = obj.Parent
                local hrp = model and model:FindFirstChild("HumanoidRootPart")
                local hp = model and serverHP[model.Name] or 0

                if model and hrp and hp > 0 and not seen[model] then
                    seen[model] = true
                    table.insert(results, model)
                end
            end
        end
    end

    -- if CONFIG.debug then
    --     log("raid client folders =", #clientFolders, "| raid server folders =", #serverFolders, "| enemies =", #results)
    -- end

    return results
end

local function getTargetDistanceFromPlayer(target)
    local root = getRoot()
    local hrp = target and target:FindFirstChild("HumanoidRootPart")
    if not root or not hrp then
        return math.huge
    end
    return (root.Position - hrp.Position).Magnitude
end

local function getNearestEnemy(enemies)
    local root = getRoot()
    if not root then
        return nil
    end

    local best = nil
    local bestDist = math.huge

    for _, enemy in ipairs(enemies) do
        local hum = enemy:FindFirstChildOfClass("Humanoid")
        local hrp = enemy:FindFirstChild("HumanoidRootPart")

        if hum and hum.Health > 0 and hrp then
            local dist = (root.Position - hrp.Position).Magnitude
            if dist < bestDist then
                best = enemy
                bestDist = dist
            end
        end
    end

    if CONFIG.debug then
        log("nearest enemy =", best and best.Name or "nil", "| dist =", bestDist ~= math.huge and math.floor(bestDist) or "inf")
    end

    return best
end

local function teleportToEnemyAndHold(target)
    local root = getRoot()
    local hum = getHumanoid()
    local targetRoot = target and target:FindFirstChild("HumanoidRootPart")

    if not root or not hum or not targetRoot then
        return false
    end

    local dir = safeUnit(root.Position - targetRoot.Position, Vector3.new(0, 0, 1))
    local desiredPos = targetRoot.Position + (dir * CONFIG.attackOffset)
    local desiredCF = CFrame.new(desiredPos, targetRoot.Position)

    if (root.Position - desiredPos).Magnitude > CONFIG.teleportThreshold then
        root.CFrame = desiredCF
    end

    hum:Move(Vector3.zero, false)
    return true
end

local function waitForFirstEnemies(timeout)
    local started = tick()
    while tick() - started < (timeout or CONFIG.firstEnemyTimeout) do
        local enemies = getEnemies()
        if #enemies > 0 then
            log("first enemies detected:", #enemies)
            return true
        end
        task.wait(0.25)
    end
    log("no enemies seen yet, will continue polling")
    return false
end

local function getServerEnemyHealthByName(enemyName)
    local serverFolders = getRaidFolders("Server")

    for _, folder in ipairs(serverFolders) do
        for _, obj in ipairs(folder:GetDescendants()) do
            if obj:IsA("Humanoid") then
                local model = obj.Parent
                if model and model.Name == enemyName then
                    return obj.Health
                end
            end
        end
    end

    return 0
end

local function clearAllEnemies(state)
    log("clearAllEnemies start FAST")
    local currentTarget = nil

    while true do
        refreshAutoAttack(state)

        local enemies = getEnemies()
        if #enemies == 0 then
            log("no enemies visible, waiting for next wave...")

            local finished = waitForNextWaveOrDone(state)
            if finished then
                return true
            else
                currentTarget = nil
            end
        end

        -- ถ้า target เดิมเลือดหมด/ไม่มีแล้ว ทิ้งทันที ไม่ต้องรอ model หาย
        if currentTarget then
            local hrp = currentTarget:FindFirstChild("HumanoidRootPart")
            local realHP = getServerEnemyHealthByName(currentTarget.Name)

            if (not currentTarget.Parent) or (not hrp) or realHP <= 5 then
                if CONFIG.debug then
                    log("drop target immediately =>", currentTarget.Name, "serverHP =", realHP)
                end
                currentTarget = nil
            end
        end

        -- หาเป้าใหม่ทันที
        if not currentTarget then
            currentTarget = getNearestEnemy(enemies)
            if CONFIG.debug then
                log("retarget =>", currentTarget and currentTarget.Name or "nil")
            end
        end

        -- วาร์ปเกาะเป้าตลอด ถ้ายังไม่ตาย
        if currentTarget then
            local realHP = getServerEnemyHealthByName(currentTarget.Name)
            if realHP > 0 then
                teleportToEnemyAndHold(currentTarget)
            else
                currentTarget = nil
            end
        end

        task.wait(0.02) -- เร็วขึ้นจาก 0.05
    end
end

-- =========================
-- REWARD CHEST
-- =========================
local function findActiveRaidVisual()
    local visuals = Workspace:FindFirstChild("Raids_Visual")
    if not visuals then
        return nil
    end

    for _, obj in ipairs(visuals:GetChildren()) do
        if obj.Name:find("_Server_") then
            return obj
        end
    end

    return nil
end

local function getRewardChests()
    local visual = findActiveRaidVisual()
    if not visual then
        log("no raid visual found")
        return {}
    end

    local rewards = visual:FindFirstChild("Configs")
    rewards = rewards and rewards:FindFirstChild("Others")
    rewards = rewards and rewards:FindFirstChild("Rewards")

    if not rewards then
        log("no rewards folder")
        return {}
    end

    local results = {}
    local golds = rewards:FindFirstChild("Golds")
    local specials = rewards:FindFirstChild("Specials")

    if golds then table.insert(results, golds) end
    if specials then table.insert(results, specials) end

    log("reward chests:", #results)
    return results
end

local function pressE()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
    task.wait(0.08)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
end

local function openAllChestsDirect()
    local root = getRoot()
    local visuals = workspace:FindFirstChild("Raids_Visual")
    if not visuals then
        warn("no visuals")
        return false
    end

    for _, v in ipairs(visuals:GetChildren()) do
        if v.Name:find("_Server_") then
            local rewards = v:FindFirstChild("Configs")
                and v.Configs:FindFirstChild("Others")
                and v.Configs.Others:FindFirstChild("Rewards")

            if not rewards then
                warn("no rewards")
                return false
            end

            local golds = rewards:FindFirstChild("Golds")
            local special = rewards:FindFirstChild("Special")

            -- เปิด Golds ก่อน
            if golds then
                root.CFrame = golds.WorldPivot
                warn("TP Golds:", golds.WorldPivot)
                task.wait(1)

                pressE()
                task.wait(0.3)
            else
                warn("Golds not found")
            end

            if special then
                root.CFrame = special.WorldPivot
                warn("TP Special 1:", special.WorldPivot)
                task.wait(1)

                pressE()
                task.wait(0.15)

                root.CFrame = special.WorldPivot * CFrame.new(0, 0, -3)
                warn("TP Special 2:", root.CFrame)
                task.wait(0.15)

                pressE()
                task.wait(0.3)
            end

            return true
        end
    end

    return false
end

local function openAllRewardChests()
    local started = tick()

    while tick() - started < CONFIG.chestWaitTimeout do
        local chests = getRewardChests()
        if #chests > 0 then
            for _, chest in ipairs(chests) do
                openChest(chest)
                task.wait(0.15)
            end
            return true
        end
        task.wait(0.2)
    end

    log("no chests found after timeout")
    return false
end

local function usePortalGate()
    local visuals = workspace:FindFirstChild("Raids_Visual")
    if not visuals then
        warn("no visuals")
        return false
    end

    local root = getRoot()

    for _, v in ipairs(visuals:GetChildren()) do
        if v.Name:find("_Server_") then
            local portal = v:FindFirstChild("Configs")
                and v.Configs:FindFirstChild("Others")
                and v.Configs.Others:FindFirstChild("Portal")
                and v.Configs.Others.Portal:FindFirstChild("Travel")

            local attachment = portal and portal:FindFirstChild("Attachment")
            local prompt = attachment and attachment:FindFirstChildOfClass("ProximityPrompt")

            if prompt and attachment then
                warn("FOUND PORTAL:", prompt:GetFullName(), "Enabled=", prompt.Enabled)

                local pos
                if attachment:IsA("Attachment") and attachment.Parent and attachment.Parent:IsA("BasePart") then
                    pos = attachment.WorldPosition
                elseif attachment:IsA("BasePart") then
                    pos = attachment.Position
                end

                if pos then
                    local targetCF = CFrame.new(pos + Vector3.new(0, 0, 3), pos)
                    root.CFrame = targetCF
                    task.wait(0.2)
                end

                local t = tick()
                while not prompt.Enabled and tick() - t < 5 do
                    task.wait(0.1)
                end

                if prompt.Enabled then
                    for i = 1, 3 do
                        fireproximityprompt(prompt)
                        task.wait(0.15)
                    end
                    return true
                else
                    warn("portal not enabled")
                end
            end
        end
    end

    return false
end

-- =========================
-- MAIN
-- =========================
local state = {
    lastAutoAttackAt = 0,
}

if not isInRaid() then
    enterRaid(CONFIG.raidMap, CONFIG.raidDifficulty)

    local ok = waitUntilInRaid(CONFIG.enterRaidTimeout)
    if not ok then
        log("failed to enter raid")
        return
    end
end

getgenv().AutoRaidRunning = true

task.spawn(function()
    while getgenv().AutoRaidRunning do
        waitForFirstEnemies(CONFIG.firstEnemyTimeout)
        clearAllEnemies(state)
        openAllChestsDirect()
        task.wait(0.5)
        log("raid complete")
        usePortalGate()
        task.wait(1.5)
    end
end)

-- getgenv().AutoRaidRunning = false