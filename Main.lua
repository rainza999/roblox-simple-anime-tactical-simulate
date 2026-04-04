warn("### RAID + BOSS MAIN BUILD V7.1 ###")

local BASE = "https://raw.githubusercontent.com/rainza999/roblox-simple-anime-tactical-simulate/main/"
local ts = tostring(os.time())

local State = loadstring(game:HttpGet(BASE .. "State.lua?t=" .. ts))()
local Scheduler = loadstring(game:HttpGet(BASE .. "Scheduler.lua?t=" .. ts))()
local UI = loadstring(game:HttpGet(BASE .. "UI.lua?t=" .. ts))()
local AutoRaid = loadstring(game:HttpGet(BASE .. "AutoRaid.lua?t=" .. ts))()
local AutoBoss = loadstring(game:HttpGet(BASE .. "AutoBoss.lua?t=" .. ts))()
local AutoGlobalBoss = loadstring(game:HttpGet(BASE .. "AutoGlobalBoss.lua?t=" .. ts))()

local function refreshDomainBirdcage(reason)
 local count = AutoGlobalBoss.getDomainBirdcageAmount()
 State.runtime.domainBirdcageCount = count
 UI.updateDomainBirdcage(count)
 warn("[MAIN] DomainBirdcage refreshed:", count, "reason:", reason or "unknown")
 return count
end


UI.init(State)
refreshDomainBirdcage("init")

State.onDomainBirdcageChanged = function(count, reason)
 State.runtime.domainBirdcageCount = count or 0
 UI.updateDomainBirdcage(State.runtime.domainBirdcageCount)
 warn("[MAIN] DomainBirdcage callback:", State.runtime.domainBirdcageCount, "reason:", reason or "unknown")
end

State.onGlobalBossFinished = function()
 refreshDomainBirdcage("global_boss_finished")
end

State.shouldInterruptRaidForGlobalBoss = function()
 return AutoGlobalBoss.shouldInterruptRaid(State)
end

getgenv().RaidBossMainRunning = true

local function log(...)
    warn("[MAIN]", ...)
end

local function shouldDoBoss(State)
    if not State.toggles.bossFight then
        return false
    end

    if not Scheduler.isBossWindow() then
        return false
    end

    local key = Scheduler.getBossWindowKey()
    if State.runtime.lastBossWindowHandled == key then
        return false
    end

    return true
end

local function markBossHandled(State)
    State.runtime.lastBossWindowHandled = Scheduler.getBossWindowKey()
end

task.spawn(function()
 while getgenv().RaidBossMainRunning and State.enabled do

    refreshDomainBirdcage("loop_tick")

    -- 1) GlobalBoss มาก่อน ถ้ามี portal หรือถ้าถึง threshold
    if AutoGlobalBoss.shouldForceGlobalBoss(State) then
        log("global boss priority -> go global now")
        AutoGlobalBoss.runOnce(State)
        refreshDomainBirdcage("after_global_priority")
        task.wait(0.2)
        continue
    end

  -- 2) ค่อย raid
  if State.toggles.raids then
    local ok, reason = AutoRaid.runOnce(State)

    if not ok then
        warn("[MAIN] AutoRaid stopped:", reason)
    end
    refreshDomainBirdcage("after_raid")

   -- raid จบแล้วค่อยเช็ก boss
    if ok and shouldDoBoss(State) then
        log("raid finished inside boss window -> go boss")
        State.runtime.bossBusy = true

        local entered = AutoBoss.goToBossFight(State)
        if entered then
            markBossHandled(State)
        end

        State.runtime.bossBusy = false
    end
  else
   -- 3) ถ้าไม่ได้ลง raid ค่อยใช้ logic boss เดิม
   if shouldDoBoss(State) then
    log("boss window without raid -> go boss")
    State.runtime.bossBusy = true

    local entered = AutoBoss.goToBossFight(State)
    if entered then
     markBossHandled(State)
    end

    State.runtime.bossBusy = false
   else
    task.wait(0.3)
   end
  end

  task.wait(0.1)
 end
end)