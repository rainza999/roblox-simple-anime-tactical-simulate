local Scheduler = {}

function Scheduler.getNow()
    local t = os.date("*t")
    return t
end

function Scheduler.getMinute()
    return tonumber(os.date("%M")) or 0
end

function Scheduler.getBossSlotInfo()
    local minute = Scheduler.getMinute()
    local slotStart = math.floor(minute / 10) * 10
    local slotEnd = slotStart + 5
    local inWindow = minute >= slotStart and minute <= slotEnd

    return {
        minute = minute,
        slotStart = slotStart, -- 00,10,20,30,40,50
        slotEnd = slotEnd,     -- 05,15,25,35,45,55
        inWindow = inWindow,
    }
end

function Scheduler.isBossWindow()
    return Scheduler.getBossSlotInfo().inWindow
end

function Scheduler.getBossWindowKey()
    local t = Scheduler.getNow()
    local slot = Scheduler.getBossSlotInfo()

    return string.format(
        "%04d-%02d-%02d-%02d-%02d",
        t.year, t.month, t.day, t.hour, slot.slotStart
    )
end

function Scheduler.secondsUntilNextBossOpen()
    local t = Scheduler.getNow()
    local minute = t.min
    local second = t.sec or 0

    local nextStart = (math.floor(minute / 10) * 10)
    if minute % 10 ~= 0 or second > 0 then
        nextStart = nextStart + 10
    end

    if nextStart >= 60 then
        return ((60 - minute) * 60) - second
    end

    return ((nextStart - minute) * 60) - second
end

return Scheduler