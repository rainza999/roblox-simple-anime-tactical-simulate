local State = {
    enabled = true,

    toggles = {
        raids = true,
        bossFight = false,
    },

    raid = {
        map = "Jujutsu Highschool",
        difficulty = "Nightmare",
        podName = "Pod_01",
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
    },

    runtime = {
        lastAutoAttackAt = 0,
        bossBusy = false,
        raidBusy = false,
        lastBossWindowHandled = nil, -- กันยิงซ้ำใน window เดียว
    }
}

return State