DEDICATED = false
for i,a in pairs(arg) do
    if a == "--dedicated" or a == "--headless" then
        DEDICATED = true
    end
end

if DEDICATED then
    function love.conf(t)
        t.version = "11.3"
        t.console = true

        t.modules.window = false
        t.modules.graphics = false
        t.modules.mouse = false
        t.modules.sound = false
        t.modules.audio = false
        t.modules.keyboard = false
        t.modules.joystick = false
        t.modules.physics = true
    end
else
    function love.conf(t)
        t.version = "11.3"

        t.window = false
    end
end
