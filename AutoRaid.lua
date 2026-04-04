local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local AutoRaid = {}

local function cfg(State)
    return State.config
end

local function raidCfg(State)
    return State.raid
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

local function refreshAutoAttack(State)
    if not State.runtime.lastAutoAttackAt or (tick() - State.runtime.lastAutoAttackAt >= cfg(State).autoAttackRefresh) then
        getByteNetReliable():FireServer(buffer.fromstring("\016\000"))
        State.runtime.lastAutoAttackAt = tick()
    end
end

local function tpTo(cf)
    getRoot().CFrame = cf
    return true
end

local function goToChallengesLobby()
    getByteNetReliable():FireServer(buffer.fromstring("\005\005\000Lobby"))
    return true
end

local function teleportToRaidPod(State)
    local podName = raidCfg(State).podName
    local pod = RaidPods[podName]
    if not pod then return false end

    if pod:IsA("Model") then
        return tpTo(pod.WorldPivot)
    end

    local center = pod:FindFirstChild("Centers")
    if center and center:IsA("BasePart") then
        return tpTo(center.CFrame)
    end

    return false
end

local function stepIntoRaidPod(State)
    local podName = raidCfg(State).podName
    local pod = RaidPods[podName]
    if not pod then return false end

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

local function selectRaidMap(State)
    local mapName = raidCfg(State).map
    local mapped = RaidMapAlias[mapName] or mapName
    getRaidLobbyRemote():FireServer(getParty(), mapped)
    return true
end

local function selectRaidDifficulty(State)
    local diffName = raidCfg(State).difficulty
    local mapped = RaidDifficultyAlias[diffName] or diffName
    getRaidLobbyRemote():FireServer(getParty(), mapped)
    return true
end

local function startRaid(State)
    getRaidStartRemote():FireServer(raidCfg(State).map, raidCfg(State).difficulty)
    return true
end

local function confirmRaidLobby()
    getRaidLobbyRemote():FireServer(Instance.new("Folder"), true)
    return true
end

local function disableParty()
    getPartyRemote():FireServer("Disabled")
    return true
end

local function getRaidFolders(containerName)
    local root = workspace:FindFirstChild("Worlds")
    root = root and root:FindFirstChild("Targets")
    root = root and root:FindFirstChild(containerName or "Clients")

    local results = {}
    if not root then return results end

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
    while tick() - started < (timeout or cfg(State).enterRaidTimeout) do
        if AutoRaid.isInRaid() then
            return true
        end
        task.wait(0.25)
    end
    return false
end

local function enterRaid(State)
    goToChallengesLobby()
    task.wait(1.2)

    teleportToRaidPod(State)
    task.wait(0.5)

    stepIntoRaidPod(State)
    task.wait(1.0)

    selectRaidMap(State)
    task.wait(0.35)

    selectRaidDifficulty(State)
    task.wait(0.35)

    startRaid(State)
    task.wait(0.35)

    confirmRaidLobby()
    task.wait(0.2)

    disableParty()
    task.wait(0.5)

    return true
end

local function getEnemies()
    local clientFolders = getRaidFolders("Clients")
    local serverFolders = getRaidFolders("Server")

    local results = {}
    local seen = {}
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

    return results
end

local function getNearestEnemy(enemies)
    local root = getRoot()
    if not root then return nil end

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

    return best
end

local function teleportToEnemyAndHold(State, target)
    local root = getRoot()
    local hum = getHumanoid()
    local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
    if not root or not hum or not targetRoot then return false end

    local dir = safeUnit(root.Position - targetRoot.Position, Vector3.new(0,0,1))
    local desiredPos = targetRoot.Position + (dir * cfg(State).attackOffset)
    local desiredCF = CFrame.new(desiredPos, targetRoot.Position)

    if (root.Position - desiredPos).Magnitude > cfg(State).teleportThreshold then
        root.CFrame = desiredCF
    end

    hum:Move(Vector3.zero, false)
    return true
end

local function shouldAbortForGlobalBoss(State)
    if not State then
        return false
    end

    if not State.toggles or not State.toggles.globalBosses then
        return false
    end

    if type(State.shouldInterruptRaidForGlobalBoss) == "function" then
        local ok, result = pcall(State.shouldInterruptRaidForGlobalBoss)
        if ok and result then
            return true
        end
    end

    return false
end

local function waitForFirstEnemies(State, timeout)
 local started = tick()

 while tick() - started < (timeout or cfg(State).firstEnemyTimeout) do
  if shouldAbortForGlobalBoss(State) then
   return false, "global_boss_interrupt"
  end

  local enemies = getEnemies()
  if #enemies > 0 then
   return true, nil
  end

  task.wait(0.25)
 end

 return false, "first_enemy_timeout"
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

local function waitForNextWaveOrDone(State)
    if shouldAbortForGlobalBoss(State) then
        return false, "global_boss_interrupt"
    end
    local started = tick()
    while tick() - started < (cfg(State).nextWaveWait or 3) do
        refreshAutoAttack(State)

        if #getEnemies() > 0 then
            return false, nil
        end

        task.wait(cfg(State).nextWavePoll or 0.1)
    end

    return true, nil
end

local function clearAllEnemies(State)
    local currentTarget = nil

    while true do
        if shouldAbortForGlobalBoss(State) then
            return false, "global_boss_interrupt"
        end
        refreshAutoAttack(State)

        local enemies = getEnemies()
        if #enemies == 0 then
            local finished, reason = waitForNextWaveOrDone(State)
            if reason == "global_boss_interrupt" then
                return false, reason
            end

            if finished then
                return true, nil
            else
                currentTarget = nil
            end
        end

        if currentTarget then
            local hrp = currentTarget:FindFirstChild("HumanoidRootPart")
            local realHP = getServerEnemyHealthByName(currentTarget.Name)
            if (not currentTarget.Parent) or (not hrp) or realHP <= 5 then
                currentTarget = nil
            end
        end

        if not currentTarget then
            currentTarget = getNearestEnemy(enemies)
        end

        if currentTarget then
            local realHP = getServerEnemyHealthByName(currentTarget.Name)
            if realHP > 0 then
                teleportToEnemyAndHold(State, currentTarget)
            else
                currentTarget = nil
            end
        end

        task.wait(0.02)
    end
end

local function pressE()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
    task.wait(0.08)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
end

local function openAllChestsDirect()
    local root = getRoot()
    local visuals = workspace:FindFirstChild("Raids_Visual")
    if not visuals then return false end

    for _, v in ipairs(visuals:GetChildren()) do
        if v.Name:find("_Server_") then
            local rewards = v:FindFirstChild("Configs")
                and v.Configs:FindFirstChild("Others")
                and v.Configs.Others:FindFirstChild("Rewards")

            if not rewards then return false end

            local golds = rewards:FindFirstChild("Golds")
            local special = rewards:FindFirstChild("Special")

            if golds then
                root.CFrame = golds.WorldPivot
                task.wait(1)
                pressE()
                task.wait(0.3)
            end

            if special then
                root.CFrame = special.WorldPivot
                task.wait(1)
                pressE()
                task.wait(0.15)

                root.CFrame = special.WorldPivot * CFrame.new(0, 0, -3)
                task.wait(0.15)
                pressE()
                task.wait(0.3)
            end

            return true
        end
    end

    return false
end

local function usePortalGate()
    local visuals = workspace:FindFirstChild("Raids_Visual")
    if not visuals then return false end

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
                local pos
                if attachment:IsA("Attachment") and attachment.Parent and attachment.Parent:IsA("BasePart") then
                    pos = attachment.WorldPosition
                elseif attachment:IsA("BasePart") then
                    pos = attachment.Position
                end

                if pos then
                    root.CFrame = CFrame.new(pos + Vector3.new(0,0,3), pos)
                    task.wait(0.2)
                end

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
            end
        end
    end

    return false
end

function AutoRaid.runOnce(State)
    State.runtime.raidBusy = true

    if shouldAbortForGlobalBoss(State) then
        State.runtime.raidBusy = false
        return false, "global_boss_interrupt"
    end

    if not AutoRaid.isInRaid() then
        enterRaid(State)

        local ok = waitUntilInRaid(State, cfg(State).enterRaidTimeout)
        if not ok then
            State.runtime.raidBusy = false
        return false, "enter_raid_failed"
        end
    end

    local hasEnemies, firstEnemyReason = waitForFirstEnemies(State, cfg(State).firstEnemyTimeout)
    if not hasEnemies and firstEnemyReason == "global_boss_interrupt" then
        State.runtime.raidBusy = false
        return false, "global_boss_interrupt"
    end

    local cleared, clearReason = clearAllEnemies(State)
    if not cleared and clearReason == "global_boss_interrupt" then
        State.runtime.raidBusy = false
        return false, "global_boss_interrupt"
    end

    if shouldAbortForGlobalBoss(State) then
        State.runtime.raidBusy = false
        return false, "global_boss_interrupt"
    end

    openAllChestsDirect()

    task.wait(0.5)

    if shouldAbortForGlobalBoss(State) then
        State.runtime.raidBusy = false
        return false, "global_boss_interrupt"
    end

    usePortalGate()
    task.wait(1.5)

    State.runtime.raidBusy = false
    return true, nil
end

return AutoRaid