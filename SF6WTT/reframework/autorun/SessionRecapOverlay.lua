-- zzz_SessionRecapOverlay.lua
-- Loaded last (alphabetically) to ensure Session Recap draws ON TOP of everything.
-- This is a thin relay — all logic is in func/Training_SessionRecap.lua

local SessionRecap = require("func/Training_SessionRecap")

if d2d and d2d.register then
    d2d.register(function() end, function()
        if SessionRecap and SessionRecap.d2d_draw then
            SessionRecap.d2d_draw()
        end
    end)
end
