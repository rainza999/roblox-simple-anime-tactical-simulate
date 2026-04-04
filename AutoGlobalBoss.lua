local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer

local AutoGlobalBoss = {}

local ATTACK_OFFSET = 3
local TELEPORT_THRESHOLD = 6

local PORTAL_WAIT_TIMEOUT = 8
local ENTER_CHECK_TIMEOUT = 10
local BOSS_WAIT_TIMEOUT = 12
local AFTER_ENTER_DELAY = 3
local AFTER_BOSS_DEAD_DELAY = 8

local function log(...)
    warn("[AUTO-GLOBAL-BOSS]", ...)
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
    task.wait(0.8)

    rootPart.CFrame = CFrame.new(portalPos + Vector3.new(0, 2, 2), portalPos)
    task.wait(1)

    pcall(function()
        fireproximityprompt(prompt)
    end)

    task.wait(0.7)
    pressE()
    -- 🔥 เพิ่มตรงนี้
    task.wait(2) -- รอ map init ก่อน
    print("wait 2 seconds after pressing E to allow map to load")
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
        if obj.Name:match("^GlobalBosses") then
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
    task.wait(0.6)
    closeDialogueGui()
    task.wait(0.8)

    local prompt = waitForPortalPrompt(PORTAL_WAIT_TIMEOUT)
    if not prompt then
        warn("[AUTO-GLOBAL-BOSS] portal did not appear after talking NPC")
        return false, nil
    end

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
        if v:IsA("Humanoid") then
            local model = v.Parent
            local hrp = model and model:FindFirstChild("HumanoidRootPart")
            if model and hrp then
                return model, v, hrp
            end
        end
    end

    return nil, nil, nil
end

local function teleportToBossAndHold(bossRoot)
    local root = getRoot()
    local hum = getHumanoid()
    if not root or not hum or not bossRoot then
        return false
    end

    local dir = safeUnit(root.Position - bossRoot.Position, Vector3.new(0, 0, 1))
    local desiredPos = bossRoot.Position + (dir * ATTACK_OFFSET)
    local desiredCF = CFrame.new(desiredPos, bossRoot.Position)

    if (root.Position - desiredPos).Magnitude > TELEPORT_THRESHOLD then
        root.CFrame = desiredCF
    end

    hum:Move(Vector3.zero, false)
    return true
end

-- local function attackBoss(bossFolder)
--     if not bossFolder then
--         bossFolder = waitForBoss(BOSS_WAIT_TIMEOUT)
--     end

--     if not bossFolder then
--         warn("[AUTO-GLOBAL-BOSS] GlobalBosses not found")
--         return false
--     end

--     log("found boss folder:", bossFolder.Name)

--     local model, humanoid, bossRoot = getBossModel(bossFolder)
--     if not model or not humanoid or not bossRoot then
--         warn("[AUTO-GLOBAL-BOSS] Boss model not found")
--         return false
--     end

--     log("found boss model:", model.Name)

--     task.wait(AFTER_ENTER_DELAY)
--     refreshAutoAttack()

--     while true do
--         if not bossFolder or not bossFolder.Parent then
--             log("boss folder removed")
--             break
--         end

--         if not model or not model.Parent then
--             log("boss model removed")
--             break
--         end

--         if not humanoid or not humanoid.Parent then
--             log("boss humanoid removed")
--             break
--         end

--         if humanoid.Health <= 0 then
--             log("boss dead")
--             break
--         end

--         if not bossRoot or not bossRoot.Parent then
--             log("boss root removed")
--             break
--         end

--         refreshAutoAttack()
--         teleportToBossAndHold(bossRoot)
--         task.wait(0.02)
--     end

--     return true
-- end

local function attackBoss(bossFolder)
    if not bossFolder then
        bossFolder = waitForBoss(BOSS_WAIT_TIMEOUT)
    end

    if not bossFolder or not bossFolder.Parent then
        warn("[AUTO-GLOBAL-BOSS] GlobalBosses not found")
        return false
    end

    log("found boss folder:", bossFolder.Name)

    task.wait(AFTER_ENTER_DELAY)
    refreshAutoAttack()

    while true do
        if not bossFolder or not bossFolder.Parent then
            log("boss folder removed")
            break
        end

        local model, humanoid, bossRoot = getBossModel(bossFolder)
        if not model or not humanoid or not bossRoot then
            log("boss model/root missing")
            task.wait(0.1)
            continue
        end

        if humanoid.Health <= 0 then
            log("boss dead")
            break
        end

        refreshAutoAttack()
        teleportToBossAndHold(bossRoot)
        task.wait(0.02)
    end

    return true
end

local function shouldStayInBirdcageBurnMode(State, amount)
    State.runtime = State.runtime or {}

    if State.runtime.globalBossBurnMode == nil then
        State.runtime.globalBossBurnMode = false
    end

    -- เริ่ม burn mode ตอนครบ 10
    if not State.runtime.globalBossBurnMode and amount >= 10 then
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

function AutoGlobalBoss.runOnce(State)
    if not State or not State.toggles or not State.toggles.globalBosses then
        return false, "global_disabled"
    end

    if State.runtime then
        State.runtime.globalBossBusy = true
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
        waitUntilGlobalBossGone(8)
        task.wait(AFTER_BOSS_DEAD_DELAY)
    end

    pushBirdcageToState(State, "after_global_run")

    if State.runtime then
        State.runtime.globalBossBusy = false
    end

    if State.onGlobalBossFinished then
        pcall(State.onGlobalBossFinished, State.runtime and State.runtime.domainBirdcageCount or 0, reason)
    end

    return ok, reason
end

return AutoGlobalBoss