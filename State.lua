local State = {
    enabled = true,

    toggles = {
        raids = true,
        bossFight = false,
        globalBosses = false,
    },

    -- raid = {
    --     map = "Jujutsu Highschool",
    --     difficulty = "Nightmare",
    --     podName = "Pod_01",
    -- },
        raid = {
        profile = "spring_new",
        map = "Spring Dungeons",
        difficulty = "Nightmare",
    },

    config = {
        debug = true,

        attackOffset = 3.0,
        teleportThreshold = 1.5,
        autoAttackRefresh = 1.5,
        scanInterval = 0.05,
        enterRaidTimeout = 15,
        firstEnemyTimeout = 10,
        chestWaitTimeout = 10,
        nextWaveWait = 3,
        nextWavePoll = 0.1,

        globalBossFocusAt = 10,

        beforeFirstChestDelay = 2.5,
        betweenChestDelay = 3.0,
        chestInteractDelay = 1.2,
        afterPressDelay = 0.8,

        leaveRaidTimeout = 10,
        afterLeaveRaidTeleportDelay = 2.5,
        afterLeaveRaidStableDelay = 1.5,
    },

    runtime = {
        lastAutoAttackAt = 0,
        bossBusy = false,
        raidBusy = false,

        globalBossBusy = false,
        domainBirdcageCount = 0,

        lastBossWindowHandled = nil,

        globalBossFinishing = false,
        globalBossCooldownUntil = 0,
        globalBossBurnMode = false,
    }
}

return State