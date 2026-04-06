-- =========================================================
-- SF6_ZoneChecker.lua
-- Shows if P1 is in P2's Orange Zone (and vice versa)
-- Reads attack data from SF6DistanceLogger_Data_Attacks.json
-- =========================================================

local re = re
local sdk = sdk
local imgui = imgui
local json = json

-- =========================================================
-- CHARACTER DETECTION (same hook as DistanceViewer)
-- =========================================================
local esf_names_map = {
    ["ESF_001"]="Ryu",     ["ESF_002"]="Luke",    ["ESF_003"]="Kimberly", ["ESF_004"]="Chun-Li",
    ["ESF_005"]="Manon",   ["ESF_006"]="Zangief", ["ESF_007"]="JP",       ["ESF_008"]="Dhalsim",
    ["ESF_009"]="Cammy",   ["ESF_010"]="Ken",     ["ESF_011"]="Dee Jay",  ["ESF_012"]="Lily",
    ["ESF_013"]="A.K.I.",  ["ESF_014"]="Rashid",  ["ESF_015"]="Blanka",   ["ESF_016"]="Juri",
    ["ESF_017"]="Marisa",  ["ESF_018"]="Guile",   ["ESF_019"]="Ed",
    ["ESF_020"]="E. Honda",["ESF_021"]="Jamie",   ["ESF_022"]="Akuma",
    ["ESF_025"]="Sagat",   ["ESF_026"]="M.Bison", ["ESF_027"]="Terry",
    ["ESF_028"]="Maï",     ["ESF_029"]="Elena",   ["ESF_030"]="Viper",["ESF_031"]="Alex"
}

local detected = { [0] = "?", [1] = "?" }

pcall(function()
    local t_med = sdk.find_type_definition("app.FBattleMediator")
    if not t_med then return end
    local method = t_med:get_method("UpdateGameInfo")
    if not method then return end
    sdk.hook(method, function(args)
        local managed_obj = sdk.to_managed_object(args[2])
        if managed_obj then
            local f_pt = t_med:get_field("PlayerType")
            if f_pt then
                local array = f_pt:get_data(managed_obj)
                if array and array:call("get_Length") >= 2 then
                    for i = 0, 1 do
                        local obj = array:call("GetValue", i)
                        if obj then
                            local pid = obj:get_type_definition():get_field("value__"):get_data(obj)
                            local esf = string.format("ESF_%03d", pid)
                            detected[i] = esf_names_map[esf] or esf
                        end
                    end
                end
            end
        end
    end, function(r) return r end)
end)

-- =========================================================
-- ATTACK DATA (orange zone thresholds per character)
-- =========================================================
local attack_data = json.load_file("SF6DistanceLogger_Data_Attacks.json") or {}

local function get_orange_ar(char_name)
    local cdata = attack_data[char_name]
    if cdata and cdata.red then
        return cdata.red.ar or 0, cdata.red.input or "?"
    end
    return 0, "?"
end

-- =========================================================
-- DISTANCE READING
-- =========================================================
local state = {
    p1_x = 0, p2_x = 0,
    dist = 0,
    p1_in_p2_orange = false,
    p2_in_p1_orange = false,
    p1_orange_ar = 0, p1_orange_move = "?",
    p2_orange_ar = 0, p2_orange_move = "?",
}

re.on_frame(function()
    pcall(function()
        local gBattle = sdk.find_type_definition("gBattle")
        if not gBattle then return end
        local pmgr = gBattle:get_field("Player"):get_data(nil)
        if not pmgr then return end
        local cP = pmgr.mcPlayer
        if not cP or not cP[0] or not cP[1] then return end

        local p1 = cP[0]
        local p2 = cP[1]

        if p1.pos and p1.pos.x and p1.pos.x.v and p2.pos and p2.pos.x and p2.pos.x.v then
            state.p1_x = p1.pos.x.v / 6553600.0
            state.p2_x = p2.pos.x.v / 6553600.0
            state.dist = math.abs(state.p1_x - state.p2_x) * 100

            -- Get orange zone thresholds
            state.p1_orange_ar, state.p1_orange_move = get_orange_ar(detected[0])
            state.p2_orange_ar, state.p2_orange_move = get_orange_ar(detected[1])

            -- P1 is in P2's orange zone = P1 is close enough for P2's orange move to reach
            state.p1_in_p2_orange = (state.dist <= state.p2_orange_ar / 100.0)
            -- P2 is in P1's orange zone = P2 is close enough for P1's orange move to reach
            state.p2_in_p1_orange = (state.dist <= state.p1_orange_ar / 100.0)
        end
    end)
end)

-- =========================================================
-- EXPOSE VIA _G
-- =========================================================
_G.SF6_ZoneChecker = state

-- =========================================================
-- IMGUI DISPLAY
-- =========================================================
re.on_draw_ui(function()
    if imgui.tree_node("Zone Checker") then
        imgui.text("P1: " .. detected[0] .. "  |  P2: " .. detected[1])
        imgui.text(string.format("Distance: %.2f", state.dist))
        imgui.spacing()

        -- P1 in P2's orange zone
        local p1_label = state.p1_in_p2_orange and "YES" or "no"
        imgui.text(string.format("P1 in P2 Orange Zone: %s  (P2 %s ar=%.0f dist=%.2f)",
            p1_label, state.p2_orange_move, state.p2_orange_ar, state.dist * 100))

        -- P2 in P1's orange zone
        local p2_label = state.p2_in_p1_orange and "YES" or "no"
        imgui.text(string.format("P2 in P1 Orange Zone: %s  (P1 %s ar=%.0f dist=%.2f)",
            p2_label, state.p1_orange_move, state.p1_orange_ar, state.dist * 100))

        imgui.tree_pop()
    end
end)
