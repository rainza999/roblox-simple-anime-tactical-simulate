task.spawn(function()
    while getgenv().VelvetRunning do
        -- กด G
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.G, false, game)
        task.wait(0.1)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.G, false, game)
        task.wait(300) -- 5 นาที = 300 วินาที
        warn("[AUTO] Pressed G")
    end
end)