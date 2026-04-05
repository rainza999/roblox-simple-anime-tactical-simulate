local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer

local AutoGlobalBoss = {}

local ATTACK_OFFSET = 3
local TELEPORT_THRESHOLD = 6

local PORTAL_WAIT_TIMEOUT = 10
local ENTER_CHECK_TIMEOUT = 12
local BOSS_WAIT_TIMEOUT = 15
local AFTER_ENTER_DELAY = 5
local AFTER_BOSS_DEAD_DELAY = 10
local POST_GLOBAL_COOLDOWN = 12

local ATTACK_LOOP_INTERVAL = 0.03
local FIRST_BOSS_KILL_CONFIRM = 1.2
local WAIT_AFTER_FIRST_BOSS_DEAD = 8
local GLOBAL_RUN_TIMEOUT = 90
local MAX_IDLE_WITHOUT_BOSS = 12

local function log(...)
    warn("[AUTO-GLOBAL-BOSS]", ...)
end

local function isPostGlobalCooldown(State)
    if not State or not State.runtime then
        return false
    end

    local untilAt = State.runtime.globalBossCooldownUntil
    return untilAt and tick() < untilAt
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

local function refreshAutoAttack()
    local ok, err = pcall(function()
        ReplicatedStorage:WaitForChild("ByteNetReliable"):FireServer(buffer.fromstring("\016\000"))
    end)

    if not ok then
        warn("[AUTO-GLOBAL-BOSS] refreshAutoAttack failed:", err)
    end
end

function AutoGlobalBoss.getDomainBirdcageAmount()
    local playersData = ReplicatedStorage:FindFirstChild("Players_Data")
    local playerData = playersData and playersData:FindFirstChild(LocalPlayer.Name)
    local inventory = playerData and playerData:FindFirstChild("Inventory")
    local resources = inventory and inventory:FindFirstChild("Resources")
    local item = resources and resources:FindFirstChild("Domain Birdcage")
    local amount = item and item:FindFirstChild("Amount")
    return amount and amount.Value or 0
end

local function pushBirdcageToState(State, reason)
    local amount = AutoGlobalBoss.getDomainBirdcageAmount()

    if State and State.runtime then
        State.runtime.domainBirdcageCount = amount
    end

    if State and State.onDomainBirdcageChanged then
        pcall(State.onDomainBirdcageChanged, amount, reason)
    end

    return amount
end

local function talkMahito()
    ReplicatedStorage:WaitForChild("Remotes")
        :WaitForChild("Misc")
        :WaitForChild("TalkingEvent")
        :FireServer("Mahito")

    log("talked to Mahito")
end

local function closeDialogueGui()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then
        return
    end

    for _, v in ipairs(playerGui:GetDescendants()) do
        local n = v.Name:lower()

        if n:find("dialog") or n:find("talk") or n:find("npc") then
            pcall(function() v.Enabled = false end)
            pcall(function() v.Visible = false end)
        end

        if v:IsA("TextButton") or v:IsA("ImageButton") then
            local btnName = v.Name:lower()
            local btnText = ""

            pcall(function()
                btnText = tostring(v.Text):lower()
            end)

            if btnName == "x" or btnName:find("close") or btnText == "x" or btnText:find("close") then
                pcall(function()
                    v:Activate()
                end)
            end
        end
    end
end

local function getPortalPrompt()
    local root = workspace:FindFirstChild("GlobalBosses_Entering")
    if not root then
        return nil
    end

    for _, v in ipairs(root:GetDescendants()) do
        if v:IsA("ProximityPrompt") and v.Enabled then
            return v
        end
    end

    return nil
end

function AutoGlobalBoss.hasOpenPortal()
    return getPortalPrompt() ~= nil
end

local function waitForPortalPrompt(timeout)
    local started = tick()

    while tick() - started < (timeout or PORTAL_WAIT_TIMEOUT) do
        local prompt = getPortalPrompt()
        if prompt then
            return prompt
        end
        task.wait(0.2)
    end

    return nil
end

local getBossModel
local waitForBossSpawn
local waitUntilGlobalBossGone

local function tpToPortalAndEnter(prompt)
    if not prompt then
        return false
    end

    local rootPart = getRoot()
    local attachment = prompt.Parent
    if not attachment or not attachment:IsA("Attachment") then
        warn("[AUTO-GLOBAL-BOSS] portal attachment not found")
        return false
    end

    local portalPos = attachment.WorldPosition

    rootPart.CFrame = CFrame.new(portalPos + Vector3.new(0, 2, 3), portalPos)
    task.wait(1.5)

    rootPart.CFrame = CFrame.new(portalPos + Vector3.new(0, 2, 2), portalPos)
    task.wait(2)

    pcall(function()
        fireproximityprompt(prompt)
    end)

    task.wait(1.2)
    pressE()
    -- 🔥 เพิ่มตรงนี้
    task.wait(5) -- รอ map init ก่อน
    print("wait 5 seconds after pressing E to allow map to load")
    local bossFolder = waitForBossSpawn(10)
    if bossFolder then
        log("boss detected after enter:", bossFolder.Name)
        log("tried entering portal:", prompt:GetFullName())
        return true
    end

    warn("[AUTO-GLOBAL-BOSS] boss not found after enter timeout")
    return false
end

local function findGlobalBossFolder()
    local worlds = workspace:FindFirstChild("Worlds")
    local targets = worlds and worlds:FindFirstChild("Targets")
    local server = targets and targets:FindFirstChild("Server")
    if not server then
        return nil
    end

    for _, obj in ipairs(server:GetChildren()) do
        if obj.Name:match("^GlobalBosses") and obj.Parent == server then
            return obj
        end
    end

    return nil
end

function AutoGlobalBoss.findActiveBossFolder()
    return findGlobalBossFolder()
end

local function waitForBoss(timeout)
    local started = tick()

    while tick() - started < (timeout or BOSS_WAIT_TIMEOUT) do
        local boss = findGlobalBossFolder()
        if boss then
            return boss
        end
        task.wait(0.2)
    end

    return nil
end

waitForBossSpawn = function(timeout)
    local t = tick()
    while tick() - t < (timeout or 10) do
        local bossFolder = findGlobalBossFolder()
        if bossFolder and bossFolder.Parent then
            local model, humanoid = getBossModel(bossFolder)
            if humanoid and humanoid.Health > 0 then
                return bossFolder
            end
        end
        task.wait(0.2)
    end
    return nil
end

waitUntilGlobalBossGone = function(timeout)
    local t = tick()
    while tick() - t < (timeout or 10) do
        if not findGlobalBossFolder() then
            return true
        end
        task.wait(0.2)
    end
    return false
end

local function tryEnterExistingPortal()
    local prompt = getPortalPrompt()
    if not prompt then
        return false, nil
    end

    log("portal already exists, entering without talking NPC")
    -- tpToPortalAndEnter(prompt)
    local entered = tpToPortalAndEnter(prompt)
    if not entered then
        return false, nil
    end

    local bossFolder = waitForBoss(ENTER_CHECK_TIMEOUT)
    if bossFolder then
        log("entered boss map from existing portal")
        return true, bossFolder
    end

    return false, nil
end

local function openPortalByNpcAndEnter(State)
    local bird = pushBirdcageToState(State, "before_open_global")
    if bird <= 0 then
        log("no Domain Birdcage left, cannot open portal")
        return false, nil
    end

    log("no portal found, opening with NPC. Domain Birdcage =", bird)

    talkMahito()
    task.wait(1.2)
    closeDialogueGui()
    task.wait(1.5)

    local prompt = waitForPortalPrompt(PORTAL_WAIT_TIMEOUT)
    if not prompt then
        warn("[AUTO-GLOBAL-BOSS] portal did not appear after talking NPC")
        return false, nil
    end

    task.wait(1.5) -- รอ portal stable ก่อนค่อยเข้า

    -- tpToPortalAndEnter(prompt)
    local entered = tpToPortalAndEnter(prompt)
    if not entered then
        return false, nil
    end

    local bossFolder = waitForBoss(ENTER_CHECK_TIMEOUT)
    if bossFolder then
        pushBirdcageToState(State, "after_open_global")
        log("entered boss map after talking NPC")
        return true, bossFolder
    end

    warn("[AUTO-GLOBAL-BOSS] failed to enter boss map after opening portal")
    return false, nil
end

local function ensurePortalThenEnter(State)
    local okExisting, existingBoss = tryEnterExistingPortal()
    if okExisting then
        return true, existingBoss
    end

    return openPortalByNpcAndEnter(State)
end

getBossModel = function(folder)
    if not folder then
        return nil, nil, nil
    end

    for _, v in ipairs(folder:GetDescendants()) do
        if v:IsA("Humanoid") and v.Parent and v.Parent.Parent then
            local model = v.Parent
            local hrp = model and model:FindFirstChild("HumanoidRootPart")
            if model and hrp then
                return model, v, hrp
            end
        end
    end

    return nil, nil, nil
end

local function isInstanceAlive(obj)
    return typeof(obj) == "Instance" and obj.Parent ~= nil
end

local function getBossFolderNameSafe(folder)
    local ok, name = pcall(function()
        return folder and folder.Name or "nil"
    end)
    return ok and name or "nil"
end

local function findAliveBossModel(folder)
    if not isInstanceAlive(folder) then
        return nil, nil, nil
    end

    local ok, model, humanoid, hrp = pcall(function()
        for _, v in ipairs(folder:GetDescendants()) do
            if v:IsA("Humanoid") and v.Parent and v.Parent.Parent then
                local m = v.Parent
                local root = m:FindFirstChild("HumanoidRootPart")
                if m and root and v.Health > 0 then
                    return m, v, root
                end
            end
        end
        return nil, nil, nil
    end)

    if not ok then
        return nil, nil, nil
    end

    return model, humanoid, hrp
end

local function waitForBossFolderGoneOrTimeout(timeout)
    local started = tick()
    while tick() - started < timeout do
        local folder = findGlobalBossFolder()
        if not folder then
            return true
        end
        task.wait(0.2)
    end
    return false
end

local function waitForPlayerLeaveBossMap(timeout)
    local started = tick()
    while tick() - started < timeout do
        local folder = findGlobalBossFolder()
        if not folder then
            return true
        end
        task.wait(0.2)
    end
    return false
end

local function teleportToBossAndHold(bossRoot)
    if not isInstanceAlive(bossRoot) then
        return false
    end

    local root = getRoot()
    local hum = getHumanoid()
    if not root or not hum then
        return false
    end

    local ok = pcall(function()
        local dir = safeUnit(root.Position - bossRoot.Position, Vector3.new(0, 0, 1))
        local desiredPos = bossRoot.Position + (dir * ATTACK_OFFSET)
        local desiredCF = CFrame.new(desiredPos, bossRoot.Position)

        if (root.Position - desiredPos).Magnitude > TELEPORT_THRESHOLD then
            root.CFrame = desiredCF
        end

        hum:Move(Vector3.zero, false)
    end)

    return ok
end

local function attackBoss(bossFolder)
    local startedAt = tick()
    local firstBossKilled = false
    local firstBossDeadAt = nil
    local lastSeenBossAt = tick()
    local firstKilledBossName = nil

    if not bossFolder then
        bossFolder = waitForBoss(BOSS_WAIT_TIMEOUT)
    end

    if not bossFolder or not isInstanceAlive(bossFolder) then
        warn("[AUTO-GLOBAL-BOSS] no valid boss folder at attack start")
        return false
    end

    log("attackBoss start folder =", getBossFolderNameSafe(bossFolder))

    task.wait(AFTER_ENTER_DELAY)
    refreshAutoAttack()

    while true do
        if tick() - startedAt > GLOBAL_RUN_TIMEOUT then
            warn("[AUTO-GLOBAL-BOSS] global run timeout")
            return false
        end

        local liveFolder = findGlobalBossFolder()

        if not liveFolder then
            if firstBossKilled then
                log("boss folder disappeared after first kill -> finish")
                return true
            end

            if tick() - lastSeenBossAt > MAX_IDLE_WITHOUT_BOSS then
                warn("[AUTO-GLOBAL-BOSS] no boss folder for too long")
                return false
            end

            task.wait(0.2)
            continue
        end

        bossFolder = liveFolder
        lastSeenBossAt = tick()

        local model, humanoid, bossRoot = findAliveBossModel(bossFolder)

        if model and humanoid and bossRoot then
            local currentBossName = model.Name

            if firstBossKilled then
                log("new boss appeared after first kill, ignore it:", currentBossName)

                local waitedOut = waitForPlayerLeaveBossMap(WAIT_AFTER_FIRST_BOSS_DEAD)
                if waitedOut then
                    log("left boss map after first kill")
                    return true
                end

                log("still in map after waiting, treat global as finished anyway")
                return true
            end

            local ok, err = pcall(function()
                refreshAutoAttack()
                teleportToBossAndHold(bossRoot)
            end)

            if not ok then
                warn("[AUTO-GLOBAL-BOSS] attack tick error:", err)
                task.wait(0.1)
            else
                if humanoid.Health <= 0 then
                    firstBossKilled = true
                    firstBossDeadAt = tick()
                    firstKilledBossName = currentBossName
                    log("first boss dead:", currentBossName)

                    task.wait(FIRST_BOSS_KILL_CONFIRM)

                    local recheckFolder = findGlobalBossFolder()
                    if not recheckFolder then
                        log("folder gone after first boss dead -> finish")
                        return true
                    end

                    local reModel, reHumanoid = findAliveBossModel(recheckFolder)

                    if reModel and reHumanoid and reModel.Name ~= firstKilledBossName then
                        log("second boss spawned after first kill -> do not attack -> finish")
                        return true
                    end

                    local gone = waitForBossFolderGoneOrTimeout(WAIT_AFTER_FIRST_BOSS_DEAD)
                    if gone then
                        log("boss folder gone after first boss kill -> finish")
                        return true
                    end

                    log("waited after first boss kill, stop global flow now")
                    return true
                end
            end
        else
            if firstBossKilled then
                if tick() - (firstBossDeadAt or tick()) >= 1 then
                    log("no alive boss model after first kill -> finish")
                    return true
                end
            end
        end

        task.wait(ATTACK_LOOP_INTERVAL)
    end
end

local function shouldStayInBirdcageBurnMode(State, amount)
    State.runtime = State.runtime or {}

    if State.runtime.globalBossBurnMode == nil then
        State.runtime.globalBossBurnMode = false
    end

    -- เริ่ม burn mode ตอนครบ 7
    if not State.runtime.globalBossBurnMode and amount >= 7 then
        State.runtime.globalBossBurnMode = true
    end

    -- หยุด burn mode ตอนเหลือ 1 หรือน้อยกว่า
    if State.runtime.globalBossBurnMode and amount <= 1 then
        State.runtime.globalBossBurnMode = false
    end

    return State.runtime.globalBossBurnMode
end

function AutoGlobalBoss.shouldForceGlobalBoss(State)
    if not State or not State.toggles or not State.toggles.globalBosses then
        return false
    end

    if State.runtime and State.runtime.globalBossBusy then
        return false
    end

    if State.runtime and State.runtime.globalBossFinishing then
        return false
    end

    if isPostGlobalCooldown(State) then
        return false
    end

    if AutoGlobalBoss.hasOpenPortal() then
        return true
    end

    local amount = AutoGlobalBoss.getDomainBirdcageAmount()

    if State.runtime then
        State.runtime.domainBirdcageCount = amount
    end

    return shouldStayInBirdcageBurnMode(State, amount)
end

function AutoGlobalBoss.shouldInterruptRaid(State)
    if not State or not State.toggles or not State.toggles.globalBosses then
        return false
    end

    if State.runtime and State.runtime.globalBossBusy then
        return false
    end

    if State.runtime and State.runtime.globalBossFinishing then
        return false
    end

    if AutoGlobalBoss.hasOpenPortal() then
        return true
    end

    local amount = AutoGlobalBoss.getDomainBirdcageAmount()

    if State.runtime then
        State.runtime.domainBirdcageCount = amount
    end

    return shouldStayInBirdcageBurnMode(State, amount)
end

local function getFreshBoss()
    local boss = findGlobalBossFolder()
    if boss and boss.Parent then
        return boss
    end
    return nil
end

local function panicResetToLobby(State, reason)
    warn("[PANIC-RESET]", reason or "unknown")

    if State and State.runtime then
        State.runtime.raidBusy = false
        State.runtime.globalBossBusy = false
        State.runtime.globalBossFinishing = false
        State.runtime.bossBusy = false
        State.runtime.lastAutoAttackAt = 0
    end

    local ok, err = pcall(function()
        ReplicatedStorage:WaitForChild("ByteNetReliable"):FireServer(buffer.fromstring("\005\005\000Lobby"))
    end)

    if not ok then
        warn("[PANIC-RESET] failed to teleport to lobby:", err)
    end

    task.wait(10)
end

function AutoGlobalBoss.runOnce(State)
    if not State or not State.toggles or not State.toggles.globalBosses then
        return false, "global_disabled"
    end

    if State.runtime then
        State.runtime.globalBossBusy = true
        State.runtime.globalBossFinishing = false
    end

    pushBirdcageToState(State, "before_global_run")

    local ok = false
    local reason = "no_action"

    local activeBoss = getFreshBoss()
    if activeBoss then
        log("already in dungeon / boss exists, attacking")
        ok = attackBoss(activeBoss)
        reason = ok and "boss_cleared" or "boss_attack_failed"
    else
        local portalPrompt = getPortalPrompt()

        if portalPrompt then
            log("detected existing portal, entering now")
            local entered, bossFolder = ensurePortalThenEnter(State)

            if entered and bossFolder then
                ok = attackBoss(bossFolder)
                reason = ok and "boss_cleared" or "boss_attack_failed"
            else
                reason = "enter_existing_portal_failed"
            end
        else
            local bird = AutoGlobalBoss.getDomainBirdcageAmount()

            if bird > 0 then
                log("Domain Birdcage available =", bird, "-> try opening dungeon")
                local entered, bossFolder = ensurePortalThenEnter(State)

                if entered and bossFolder then
                    ok = attackBoss(bossFolder)
                    reason = ok and "boss_cleared" or "boss_attack_failed"
                else
                    reason = "open_portal_failed"
                end
            else
                log("no Domain Birdcage and no portal")
                ok = false
                reason = "no_domain_birdcage"
            end
        end
    end

    if ok then
        if State and State.runtime then
            State.runtime.globalBossFinishing = true
        end

        log("global finished -> wait map to kick player out first")
        task.wait(3)

        local leftMap = waitForPlayerLeaveBossMap(12)
        if leftMap then
            log("player already left boss map naturally")
        else
            log("map did not remove boss folder in time -> lobby reset fallback")
            panicResetToLobby(State, "global_boss_finished_fallback")
        end
    elseif reason == "boss_attack_failed"
        or reason == "enter_existing_portal_failed"
        or reason == "open_portal_failed" then
        panicResetToLobby(State, reason)
    end

    pushBirdcageToState(State, "after_global_run")

    if State and State.runtime then
        State.runtime.globalBossBusy = false
        State.runtime.globalBossFinishing = false
    end

    log("global boss flow fully ended")
    return ok, reason
end

return AutoGlobalBoss