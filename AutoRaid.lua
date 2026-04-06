local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local AutoRaid = {}

local function cfg(State)
    return State.config or {}
end

local function raidCfg(State)
    State.raid = State.raid or {}
    return State.raid
end

local function runtime(State)
    State.runtime = State.runtime or {}
    return State.runtime
end

local function log(...)
    warn("[AUTO-RAID]", ...)
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

local function pressE()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
    task.wait(0.08)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
end

local function tpTo(cf)
    getRoot().CFrame = cf
    return true
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

local function getRaidParty(profile)
    local shared = ReplicatedStorage:WaitForChild("Shared")
    local parties = shared:WaitForChild("Parties")

    -- ถ้า AUTO → ใช้ชื่อตัวเอง
    if profile.partyOwner == "AUTO" then
        return parties:WaitForChild(LocalPlayer.Name)
    end

    -- ถ้าไม่ใช่ → ใช้ค่าที่กำหนด
    return parties:WaitForChild(profile.partyOwner)
end

local PROFILES = {
    spring_new = {
        displayName = "Spring Dungeons (NEW)",
        map = "Spring Dungeons",
        difficulty = "Nightmare",
        difficultyLobbyKey = "Diffculty_Nightmare",

        -- คนที่เป็นเจ้าของ party / visual server name
        partyOwner = "AUTO",
        visualServerName = "Spring Dungeons_Server_RainFatherReal",

        -- จุดวาปก่อนกดลงดัน
        lobbyTeleport = Vector3.new(9096.3105, 3169.6552, 5159.6782),

        -- reward ใหม่: มีแค่ Golds
        rewardType = "golds_only",

        -- path ใหม่
        goldsPath = {"Configs", "Others", "Rewards", "Golds"},
        portalPath = {"Configs", "Others", "Portal", "Travel", "Attachment"},
    },

    -- เผื่อไว้ ถ้าจะโยก logic เก่ากลับมาใส่ทีหลัง
    legacy = {
        displayName = "Legacy Raid",
        map = "Jujutsu Highschool",
        difficulty = "Nightmare",
        difficultyLobbyKey = "Diffculty_Nightmare",
        partyOwner = LocalPlayer.Name,
        visualServerName = nil,
        lobbyTeleport = nil,
        rewardType = "golds_and_special",
        goldsPath = {"Configs", "Others", "Rewards", "Golds"},
        specialPath = {"Configs", "Others", "Rewards", "Special"},
        portalPath = {"Configs", "Others", "Portal", "Travel", "Attachment"},
    },
}

local function getSelectedProfile(State)
    local name = raidCfg(State).profile or "spring_new"
    return PROFILES[name] or PROFILES.spring_new
end

local function getChildByPath(root, path)
    local current = root
    for _, key in ipairs(path) do
        if not current then
            return nil
        end
        current = current:FindFirstChild(key)
    end
    return current
end

local function getVisualRoot(profile)
    local visuals = Workspace:FindFirstChild("Raids_Visual")
    if not visuals then
        return nil
    end

    if profile.visualServerName then
        local exact = visuals:FindFirstChild(profile.visualServerName)
        if exact then
            return exact
        end
    end

    for _, v in ipairs(visuals:GetChildren()) do
        if v.Name:find("_Server_") then
            if (not profile.map or v.Name:find(profile.map, 1, true)) then
                return v
            end
        end
    end

    return nil
end

local function getObjectCFrame(obj)
    if not obj then
        return nil
    end

    if obj:IsA("Model") then
        return obj:GetPivot()
    end

    if obj:IsA("BasePart") then
        return obj.CFrame
    end

    if obj:IsA("Attachment") then
        return obj.WorldCFrame
    end

    local primary = obj:FindFirstChild("Primary")
    if primary and primary:IsA("BasePart") then
        return primary.CFrame
    end

    if obj.WorldPivot then
        return obj.WorldPivot
    end

    return nil
end

local function getPromptFromObject(obj)
    if not obj then
        return nil
    end

    if obj:IsA("ProximityPrompt") then
        return obj
    end

    local direct = obj:FindFirstChildOfClass("ProximityPrompt")
    if direct then
        return direct
    end

    for _, d in ipairs(obj:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            return d
        end
    end

    return nil
end

local function refreshAutoAttack(State)
    local rt = runtime(State)
    local delayTime = cfg(State).autoAttackRefresh or 0.75

    if not rt.lastAutoAttackAt or (tick() - rt.lastAutoAttackAt >= delayTime) then
        getByteNetReliable():FireServer(buffer.fromstring("\016\000"))
        rt.lastAutoAttackAt = tick()
    end
end

local function getRaidFolders(containerName)
    local root = Workspace:FindFirstChild("Worlds")
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

function AutoRaid.isInRaid()
    return #getRaidFolders("Server") > 0 or #getRaidFolders("Clients") > 0
end

local function waitUntilInRaid(State, timeout)
    local started = tick()
    local maxTime = timeout or cfg(State).enterRaidTimeout or 15

    while tick() - started < maxTime do
        if AutoRaid.isInRaid() then
            return true
        end
        task.wait(0.25)
    end

    return false
end

local function waitUntilOutOfRaid(timeout)
    local started = tick()
    local maxTime = timeout or 10

    while tick() - started < maxTime do
        if not AutoRaid.isInRaid() then
            return true
        end
        task.wait(0.25)
    end

    return false
end

local function enterRaid_newSpring(State, profile)
    log("enterRaid_newSpring start")

    if profile.lobbyTeleport then
        tpTo(CFrame.new(profile.lobbyTeleport))
        task.wait(0.8)
    end

    -- step 1: เลือก party / diff หน้า lobby
    local partyObj = getRaidPartyByName(profile)
    getRaidLobbyRemote():FireServer(partyObj, profile.difficultyLobbyKey)
    task.wait(0.35)

    -- step 2: start raid
    getRaidStartRemote():FireServer(profile.map, profile.difficulty)
    task.wait(0.35)

    -- step 3: confirm
    local confirmFolder = Instance.new("Folder")
    getRaidLobbyRemote():FireServer(confirmFolder, nil, true)
    confirmFolder:Destroy()
    task.wait(0.25)

    -- step 4: disable party
    getPartyRemote():FireServer("Disabled")
    task.wait(0.4)

    return true
end

local function enterRaid_legacy(State, profile)
    log("enterRaid_legacy start")

    local partyObj = getRaidPartyByName(profile.partyOwner)
    getRaidLobbyRemote():FireServer(partyObj, profile.map)
    task.wait(0.35)

    getRaidLobbyRemote():FireServer(partyObj, profile.difficultyLobbyKey)
    task.wait(0.35)

    getRaidStartRemote():FireServer(profile.map, profile.difficulty)
    task.wait(0.35)

    local confirmFolder = Instance.new("Folder")
    getRaidLobbyRemote():FireServer(confirmFolder, nil, true)
    confirmFolder:Destroy()
    task.wait(0.25)

    getPartyRemote():FireServer("Disabled")
    task.wait(0.4)

    return true
end

local function enterRaid(State)
    local profile = getSelectedProfile(State)

    if (raidCfg(State).profile or "spring_new") == "spring_new" then
        return enterRaid_newSpring(State, profile)
    end

    return enterRaid_legacy(State, profile)
end

local function getServerEnemyHealthFromClientTarget(clientTarget)
    if not clientTarget or not clientTarget.Parent then
        return 0
    end

    local clientRoot = clientTarget:FindFirstChild("HumanoidRootPart")
    if not clientRoot then
        return 0
    end

    local bestHealth = 0
    local bestDist = math.huge

    local serverFolders = getRaidFolders("Server")
    for _, folder in ipairs(serverFolders) do
        for _, obj in ipairs(folder:GetDescendants()) do
            if obj:IsA("Humanoid") then
                local model = obj.Parent
                local hrp = model and model:FindFirstChild("HumanoidRootPart")
                if model and hrp and obj.Health > 0 then
                    local dist = (hrp.Position - clientRoot.Position).Magnitude
                    if dist < bestDist then
                        bestDist = dist
                        bestHealth = obj.Health
                    end
                end
            end
        end
    end

    return bestHealth
end

local function getEnemies()
    local clientFolders = getRaidFolders("Clients")
    local results = {}
    local seen = {}

    for _, folder in ipairs(clientFolders) do
        for _, obj in ipairs(folder:GetDescendants()) do
            if obj:IsA("Humanoid") then
                local model = obj.Parent
                local hrp = model and model:FindFirstChild("HumanoidRootPart")
                if model and hrp and not seen[model] then
                    local hp = getServerEnemyHealthFromClientTarget(model)
                    if hp > 0 then
                        seen[model] = true
                        table.insert(results, model)
                    end
                end
            end
        end
    end

    return results
end

local function getNearestEnemy(enemies)
    local root = getRoot()
    if not root then
        return nil
    end

    local best, bestDist = nil, math.huge
    for _, enemy in ipairs(enemies) do
        local hrp = enemy:FindFirstChild("HumanoidRootPart")
        if hrp then
            local dist = (root.Position - hrp.Position).Magnitude
            if dist < bestDist then
                best = enemy
                bestDist = dist
            end
        end
    end

    return best
end

local function teleportToEnemyAndHold(State, target)
    local root = getRoot()
    local hum = getHumanoid()
    local targetRoot = target and target:FindFirstChild("HumanoidRootPart")

    if not root or not hum or not targetRoot then
        return false
    end

    local offset = cfg(State).attackOffset or 6
    local threshold = cfg(State).teleportThreshold or 12

    local dir = safeUnit(root.Position - targetRoot.Position, Vector3.new(0, 0, 1))
    local desiredPos = targetRoot.Position + (dir * offset)
    local desiredCF = CFrame.new(desiredPos, targetRoot.Position)

    if (root.Position - desiredPos).Magnitude > threshold then
        root.CFrame = desiredCF
    end

    hum:Move(Vector3.zero, false)
    return true
end

local function waitForFirstEnemies(State, timeout)
    local started = tick()
    local maxTime = timeout or cfg(State).firstEnemyTimeout or 20

    while tick() - started < maxTime do
        local enemies = getEnemies()
        if #enemies > 0 then
            return true, nil
        end
        task.wait(0.25)
    end

    return false, "first_enemy_timeout"
end

local function waitForNextWaveOrDone(State)
    local started = tick()
    local maxTime = cfg(State).nextWaveWait or 3
    local poll = cfg(State).nextWavePoll or 0.1

    while tick() - started < maxTime do
        refreshAutoAttack(State)

        if #getEnemies() > 0 then
            return false, nil
        end

        task.wait(poll)
    end

    return true, nil
end

local function clearAllEnemies(State)
    local currentTarget = nil

    while true do
        refreshAutoAttack(State)

        local enemies = getEnemies()
        if #enemies == 0 then
            local finished = waitForNextWaveOrDone(State)
            if finished then
                return true, nil
            else
                currentTarget = nil
            end
        end

        if currentTarget then
            local hrp = currentTarget:FindFirstChild("HumanoidRootPart")
            local realHP = getServerEnemyHealthFromClientTarget(currentTarget)

            if (not currentTarget.Parent) or (not hrp) or realHP <= 0 then
                currentTarget = nil
            end
        end

        if not currentTarget then
            currentTarget = getNearestEnemy(enemies)
        end

        if currentTarget then
            local realHP = getServerEnemyHealthFromClientTarget(currentTarget)
            if realHP > 0 then
                teleportToEnemyAndHold(State, currentTarget)
            else
                currentTarget = nil
            end
        end

        task.wait(0.02)
    end
end

local function openGoldsOnly(State, profile)
    local visual = getVisualRoot(profile)
    if not visual then
        log("visual not found")
        return false
    end

    local golds = getChildByPath(visual, profile.goldsPath)
    if not golds then
        log("golds not found")
        return false
    end

    local goldsCF = getObjectCFrame(golds)
    if not goldsCF then
        log("golds cframe not found")
        return false
    end

    local beforeFirstChestDelay = cfg(State).beforeFirstChestDelay or 2.0
    local chestInteractDelay = cfg(State).chestInteractDelay or 1.1
    local afterPressDelay = cfg(State).afterPressDelay or 0.8

    task.wait(beforeFirstChestDelay)

    log("opening Golds...")
    getRoot().CFrame = goldsCF
    task.wait(chestInteractDelay)

    local prompt = getPromptFromObject(golds)
    if prompt then
        fireproximityprompt(prompt)
    else
        pressE()
    end

    task.wait(afterPressDelay)

    -- กันพลาด กดซ้ำอีกครั้ง
    getRoot().CFrame = goldsCF
    task.wait(0.25)

    if prompt then
        fireproximityprompt(prompt)
    else
        pressE()
    end

    task.wait(afterPressDelay)
    return true
end

local function openRewards(State)
    local profile = getSelectedProfile(State)

    if profile.rewardType == "golds_only" then
        return openGoldsOnly(State, profile)
    end

    -- fallback แบบง่าย ถ้าจะไปขยายของเก่าทีหลัง
    return openGoldsOnly(State, profile)
end

local function usePortalGate(State)
    local profile = getSelectedProfile(State)
    local visual = getVisualRoot(profile)
    if not visual then
        log("portal visual not found")
        return false
    end

    local attachment = getChildByPath(visual, profile.portalPath)
    if not attachment then
        log("portal attachment not found")
        return false
    end

    local prompt = getPromptFromObject(attachment)
    if not prompt then
        log("portal prompt not found")
        return false
    end

    local portalCF = getObjectCFrame(attachment)
    if not portalCF then
        log("portal cframe not found")
        return false
    end

    local root = getRoot()

    -- ยืนหน้าพอร์ทัล
    root.CFrame = portalCF * CFrame.new(0, 0, -3)
    task.wait(0.2)

    local t = tick()
    while not prompt.Enabled and tick() - t < 5 do
        task.wait(0.1)
    end

    if prompt.Enabled then
        for _ = 1, 3 do
            fireproximityprompt(prompt)
            task.wait(0.15)
        end
        return true
    end

    return false
end

function AutoRaid.stopOtherModes(State)
    State.toggles = State.toggles or {}
    State.runtime = State.runtime or {}

    -- ปิด global boss ไว้ก่อนตามที่ต้องการ
    State.toggles.globalBosses = false
    State.runtime.pauseGlobalBoss = true
    State.runtime.forceRaidOnly = true

    log("other modes stopped: globalBosses=false, pauseGlobalBoss=true")
end

function AutoRaid.runOnce(State)
    State.runtime = State.runtime or {}
    State.runtime.raidBusy = true

    AutoRaid.stopOtherModes(State)

    if not AutoRaid.isInRaid() then
        enterRaid(State)

        local ok = waitUntilInRaid(State, cfg(State).enterRaidTimeout or 15)
        if not ok then
            State.runtime.raidBusy = false
            return false, "enter_raid_failed"
        end
    end

    local hasEnemies, firstEnemyReason = waitForFirstEnemies(State, cfg(State).firstEnemyTimeout or 20)
    if not hasEnemies then
        State.runtime.raidBusy = false
        return false, firstEnemyReason or "first_enemy_failed"
    end

    local cleared, clearReason = clearAllEnemies(State)
    if not cleared then
        State.runtime.raidBusy = false
        return false, clearReason or "clear_failed"
    end

    local openedRewards = openRewards(State)
    if not openedRewards then
        State.runtime.raidBusy = false
        return false, "open_rewards_failed"
    end

    task.wait(1.0)

    local usedPortal = usePortalGate(State)
    if not usedPortal then
        State.runtime.raidBusy = false
        return false, "use_portal_failed"
    end

    task.wait(1.5)
    State.runtime.raidBusy = false
    return true, nil
end

function AutoRaid.run(State)
    AutoRaid.stopOtherModes(State)

    while State.enabled do
        local ok, reason = AutoRaid.runOnce(State)
        if not ok then
            log("runOnce failed:", reason)
            task.wait(1.5)
        else
            task.wait(cfg(State).loopDelay or 1.0)
        end
    end
end

return AutoRaid