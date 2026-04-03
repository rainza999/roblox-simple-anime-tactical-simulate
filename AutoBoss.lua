local AutoBoss = {}

local function log(...)
    warn("[AUTO-BOSS]", ...)
end

function AutoBoss.isInBossFight()
    local clients = workspace:FindFirstChild("Worlds")
    clients = clients and clients:FindFirstChild("Targets")
    clients = clients and clients:FindFirstChild("Clients")
    if not clients then
        return false
    end

    for _, v in ipairs(clients:GetChildren()) do
        if v.Name:match("^BossFight") then
            return true
        end
    end

    return false
end

function AutoBoss.canStartBossNow()
    return true
end

function AutoBoss.goToBossFight(State)
    log("goToBossFight placeholder")
    -- TODO:
    -- 1) วาร์ปไปตำแหน่งเข้า boss
    -- 2) กด/เข้า instance
    -- 3) รอจนเข้า boss สำเร็จ
    return false
end

function AutoBoss.run(State)
    log("run placeholder")
    -- TODO:
    -- ใส่ logic ตี boss จริงตรงนี้
    task.wait(1)
    return true
end

return AutoBoss