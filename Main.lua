warn("### RAID + BOSS MAIN BUILD ###")

local State = loadstring(game:HttpGet("URL_TO/State.lua"))()
local Scheduler = loadstring(game:HttpGet("URL_TO/Scheduler.lua"))()
local UI = loadstring(game:HttpGet("URL_TO/UI.lua"))()
local AutoRaid = loadstring(game:HttpGet("URL_TO/AutoRaid.lua"))()
local AutoBoss = loadstring(game:HttpGet("URL_TO/AutoBoss.lua"))()

UI.init(State)

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
        -- 1) priority raid ก่อน
        if State.toggles.raids then
            local ok = AutoRaid.runOnce(State)

            -- raid จบแล้วค่อยเช็ก boss
            if ok and shouldDoBoss(State) then
                log("raid finished inside boss window -> go boss")
                State.runtime.bossBusy = true

                local entered = AutoBoss.goToBossFight(State)
                if entered then
                    AutoBoss.run(State)
                end

                markBossHandled(State)
                State.runtime.bossBusy = false
            end

            task.wait(0.3)
            continue
        end

        -- 2) ถ้าไม่ได้เปิด raids แต่เปิด bossFight ไว้ ก็รอตามเวลา
        if shouldDoBoss(State) then
            log("boss window active -> go boss")
            State.runtime.bossBusy = true

            local entered = AutoBoss.goToBossFight(State)
            if entered then
                AutoBoss.run(State)
            end

            markBossHandled(State)
            State.runtime.bossBusy = false
        end

        task.wait(0.5)
    end
end)