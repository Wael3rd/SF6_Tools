-- =========================================================
-- SF6_ZoneChecker.lua
-- Shows if P1 is in P2's Orange Zone (and vice versa)
-- Uses collision box edges (same as DistanceViewer)
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
        return (cdata.red.ar or 0), (cdata.red.input or "?")
    end
    return 0, "?"
end

-- =========================================================
-- DISTANCE CALCULATION (edge-to-edge, same as DistanceViewer)
-- =========================================================
local function get_closest_dist(player_obj, ref_x)
    local min_dist = 999999.0

    if not player_obj or not player_obj.mpActParam or not player_obj.mpActParam.Collision then
        return min_dist
    end

    local col = player_obj.mpActParam.Collision
    if col.Infos and col.Infos._items then
        for _, r in pairs(col.Infos._items) do
            if r and (r:get_field("Attr") ~= nil or r:get_field("HitNo") ~= nil) then
                local box_x = (r.OffsetX and r.OffsetX.v) and (r.OffsetX.v / 6553600.0) or 0.0
                local size_x = (r.SizeX and r.SizeX.v) and (r.SizeX.v / 6553600.0) or 0.0

                local right_edge = box_x + size_x
                local left_edge = box_x - size_x

                local d_left = math.abs(ref_x - left_edge)
                local d_right = math.abs(ref_x - right_edge)
                if d_left < min_dist then min_dist = d_left end
                if d_right < min_dist then min_dist = d_right end
            end
        end
    end
    return min_dist
end

-- =========================================================
-- STATE
-- =========================================================
local state = {
    p1_dist = 0, p2_dist = 0,
    p1_in_p2_orange = false,
    p2_in_p1_orange = false,
    p1_orange_ar = 0, p1_orange_move = "?",
    p2_orange_ar = 0, p2_orange_move = "?",
    debug = "waiting",
}

re.on_frame(function()
    pcall(function()
        local gBattle = sdk.find_type_definition("gBattle")
        if not gBattle then state.debug = "no gBattle"; return end
        local pmgr = gBattle:get_field("Player"):get_data(nil)
        if not pmgr then state.debug = "no pmgr"; return end
        local cP = pmgr.mcPlayer
        if not cP or not cP[0] or not cP[1] then state.debug = "no players"; return end

        local p1 = cP[0]
        local p2 = cP[1]
        local p1_x = p1.pos.x.v / 6553600.0
        local p2_x = p2.pos.x.v / 6553600.0

        -- Edge-to-edge distance (same as DistanceViewer analyze_boxes)
        -- P1's closest edge to P2's position
        state.p1_dist = get_closest_dist(p1, p2_x)
        -- P2's closest edge to P1's position
        state.p2_dist = get_closest_dist(p2, p1_x)

        -- Get orange zone thresholds (ar is in same units * 100, compare with ar/100)
        state.p1_orange_ar, state.p1_orange_move = get_orange_ar(detected[0])
        state.p2_orange_ar, state.p2_orange_move = get_orange_ar(detected[1])

        -- P1 is in P2's orange zone = P2's closest edge to P1 is within P2's orange ar
        state.p1_in_p2_orange = (state.p2_dist <= state.p2_orange_ar / 100.0 + 0.001)
        -- P2 is in P1's orange zone = P1's closest edge to P2 is within P1's orange ar
        state.p2_in_p1_orange = (state.p1_dist <= state.p1_orange_ar / 100.0 + 0.001)

        state.debug = "OK"
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
        imgui.text("Status: " .. state.debug)
        imgui.spacing()

        imgui.text(string.format("P1 edge dist to P2: %.4f  |  P2 orange ar: %.2f (%.4f)",
            state.p1_dist, state.p2_orange_ar, state.p2_orange_ar / 100.0))
        if state.p1_in_p2_orange then
            imgui.text_colored(">>> P1 IN P2 ORANGE ZONE (" .. state.p2_orange_move .. ") <<<", 0xFF00A5FF)
        else
            imgui.text("P1 NOT in P2 Orange Zone")
        end

        imgui.spacing()

        imgui.text(string.format("P2 edge dist to P1: %.4f  |  P1 orange ar: %.2f (%.4f)",
            state.p2_dist, state.p1_orange_ar, state.p1_orange_ar / 100.0))
        if state.p2_in_p1_orange then
            imgui.text_colored(">>> P2 IN P1 ORANGE ZONE (" .. state.p1_orange_move .. ") <<<", 0xFF00A5FF)
        else
            imgui.text("P2 NOT in P1 Orange Zone")
        end

        imgui.tree_pop()
    end
end)
