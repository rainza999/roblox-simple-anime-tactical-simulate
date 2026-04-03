warn("### RAID + BOSS MAIN BUILD V2###")

local BASE = "https://raw.githubusercontent.com/rainza999/roblox-simple-anime-tactical-simulate/main/"
local ts = tostring(os.time())

local State = loadstring(game:HttpGet(BASE .. "State.lua?t=" .. ts))()
local Scheduler = loadstring(game:HttpGet(BASE .. "Scheduler.lua?t=" .. ts))()
local UI = loadstring(game:HttpGet(BASE .. "UI.lua?t=" .. ts))()
local AutoRaid = loadstring(game:HttpGet(BASE .. "AutoRaid.lua?t=" .. ts))()
local AutoBoss = loadstring(game:HttpGet(BASE .. "AutoBoss.lua?t=" .. ts))()

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