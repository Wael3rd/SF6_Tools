--[[
    SF6 Distance Logger V8.2
    - Advanced : Log automatique basé sur l'Action ID — capture l'AR max de l'action.
    - Tri de la liste par AR décroissant.
    - RED / LOW (violet) / Yellow par perso avec highlight dans la liste.
    - Teleport + Jump conservés.
    - NOUVEAU : Capture du GuardBit et signalement du coup qui a la plus grande portée (MAX) par type de garde.
    - NOUVEAU : Détection des coups Cancelables via trigger_notice.
]]

local sdk = sdk
local imgui = imgui
local re = re
local json = json
local Vector2f = Vector2f

-- =========================================================
-- CONFIGURATION PATHS
-- =========================================================
local jump_filename = "SF6DistanceLogger_Data_Jumps.json"
local ui_state_filename = "SF6DistanceLogger_Config.json"
local advanced_filename = "SF6DistanceLogger_Data_Attacks.json"

local jump_data_store = {}
local advanced_data = {} -- { ["Ryu"] = { moves={}, red=nil, low=nil }, ... }

-- State par joueur pour le tracking
-- prev_bv : valeur boutons du frame précédent (pour détecter front montant)
local adv_state = {
    [0] = { act_id = -1, last_attack_input = "5", peak_ar = 0, peak_guard_bit = 0, had_hitbox = false, prev_bv = 0, logging_active = false, is_cancelable = false , is_super_cancelable = false },
    [1] = { act_id = -1, last_attack_input = "5", peak_ar = 0, peak_guard_bit = 0, had_hitbox = false, prev_bv = 0, logging_active = false, is_cancelable = false , is_super_cancelable = false },
}

local status_msg = ""
local status_timer = 0
local edit_state = { key = nil, buf = "", ar_buf = "" }  -- état édition nom + AR de move 

-- VARIABLE TELEPORT
local teleport_target_dist = 184.000

-- NOUVEAU : État des checkboxes (false = Center, true = Border)
local tp_p1_border = false 
local tp_p2_border = true  -- Par défaut comme avant (P2 Border, P1 Center)

-- VARIABLES JUMP
local REC_IDLE = 0
local REC_WAITING = 1 
local REC_RECORDING = 2 
local USE_SMOOTHING = true
local SMOOTH_THRESHOLD = 0.002 

local jump_rec_state = {
    [0] = { status = REC_IDLE, buffer = {}, origin_x = 0 },
    [1] = { status = REC_IDLE, buffer = {}, origin_x = 0 }
}

-- VARIABLES UI STATE
local ui_state = {
    show_overlay = true,
    pos_x = 50.0,
    pos_y = 50.0,
    size_x = 0,
    size_y = 0
}
local ui_dirty = false
local ui_save_timer = 0.0
local first_draw = true

-- ÉCHELLES
local SCALE_DIST = 65536.0   -- x100
local SCALE_JUMP = 6553600.0 -- Raw

-- =========================================================
-- LISTE DES NOMS
-- =========================================================
local esf_names_map = {
    ["ESF_001"]="Ryu", ["ESF_002"]="Luke", ["ESF_003"]="Kimberly", ["ESF_004"]="Chun-Li",
    ["ESF_005"]="Manon", ["ESF_006"]="Zangief", ["ESF_007"]="JP", ["ESF_008"]="Dhalsim",
    ["ESF_009"]="Cammy", ["ESF_010"]="Ken", ["ESF_011"]="Dee Jay", ["ESF_012"]="Lily",
    ["ESF_013"]="A.K.I.", ["ESF_014"]="Rashid", ["ESF_015"]="Blanka", ["ESF_016"]="Juri",
    ["ESF_017"]="Marisa", ["ESF_018"]="Guile", ["ESF_019"]="Ed", 
    ["ESF_020"]="E. Honda", ["ESF_021"]="Jamie", ["ESF_022"]="Akuma", 
    ["ESF_025"]="Sagat", ["ESF_026"]="M.Bison", ["ESF_027"]="Terry", 
    ["ESF_028"]="Maï", ["ESF_029"]="Elena", ["ESF_030"]="Viper",["ESF_031"]="Alex"
}

-- =========================================================
-- 1. HELPERS & JSON UI
-- =========================================================
local function load_ui_config()
    local f = json.load_file(ui_state_filename)
    if f then
        if f.show_overlay ~= nil then ui_state.show_overlay = f.show_overlay end
        if f.pos_x then ui_state.pos_x = f.pos_x end
        if f.pos_y then ui_state.pos_y = f.pos_y end
        if f.size_x then ui_state.size_x = f.size_x end
        if f.size_y then ui_state.size_y = f.size_y end
    end
end

local function save_ui_config()
    json.dump_file(ui_state_filename, ui_state)
    ui_dirty = false
end

local function bitand(a,b) local r=0;local B=1;while a>0 and b>0 do if a%2==1 and b%2==1 then r=r+B end;B=B*2;a=math.floor(a/2);b=math.floor(b/2)end;return r end
local function reversePairs(T)local K={};for k,v in pairs(T)do K[#K+1]=k end;table.sort(K,function(a,b)return a>b end);local n=0;return function()n=n+1;if n>#K then return end;return K[n],T[K[n]]end end
local function abs(num) if num < 0 then return num * -1 else return num end end

local function get_pos_x_dist(p)
    if not p then return 0 end
    if p.pos and p.pos.x and p.pos.x.v then 
        return p.pos.x.v / SCALE_DIST 
    end
    return 0
end

local function get_numpad_notation(dir_val)
    if not dir_val then return "5" end
    local u, d, l, r = (dir_val & 1) ~= 0, (dir_val & 2) ~= 0, (dir_val & 4) ~= 0, (dir_val & 8) ~= 0
    if u and l then return "7" elseif u and r then return "9" elseif d and l then return "1" elseif d and r then return "3"
    elseif u then return "8" elseif d then return "2" elseif l then return "4" elseif r then return "6" end
    return "5"
end

local function get_btn_text(val)
    if not val or val == 0 then return "" end
    local btns = {}
    if (val & 16) ~= 0  then table.insert(btns, "LP") end
    if (val & 32) ~= 0  then table.insert(btns, "MP") end
    if (val & 64) ~= 0  then table.insert(btns, "HP") end
    if (val & 128) ~= 0 then table.insert(btns, "LK") end
    if (val & 256) ~= 0 then table.insert(btns, "MK") end
    if (val & 512) ~= 0 then table.insert(btns, "HK") end
    if #btns == 0 then return "" end
    return table.concat(btns, "")
end

local function refine_buffer(buffer)
    if not buffer or #buffer < 2 then return buffer end
    local new_buffer = {}
    table.insert(new_buffer, buffer[1])
    for i = 1, #buffer - 1 do
        local p1 = buffer[i]
        local p2 = buffer[i+1]
        local dx = p2.x - p1.x
        local dy = p2.y - p1.y
        local dist = math.sqrt(dx*dx + dy*dy)
        if USE_SMOOTHING and dist > SMOOTH_THRESHOLD then
            local mid_x = (p1.x + p2.x) * 0.5
            local mid_y = (p1.y + p2.y) * 0.5
            table.insert(new_buffer, { x = mid_x, y = mid_y })
        end
        table.insert(new_buffer, p2)
    end
    return new_buffer
end

local function get_guard_type_name(gb)
    if not gb or gb == 0 then return "---" end
    if gb == 7 then return "Mid" end
    if gb == 6 then return "Low" end
    if gb == 5 then return "Overhead" end
    if gb == 3 then return "Grd.Mid" end
    if gb == 1 then return "High" end
    if gb == 2 then return "Crouch" end
    if gb == 4 then return "Air" end
    return tostring(gb)
end

-- =========================================================
-- 2. CALCUL AR & GUARD BIT
-- =========================================================
local function get_hitbox_range_data(player_obj, act_param)
    local facingRight = false
    if player_obj.BitValue ~= nil then facingRight = (bitand(player_obj.BitValue, 128) == 128) end
    local maxHitboxEdgeX = nil
    local active_guard_bit = 0
    
    if act_param ~= nil and act_param.Collision ~= nil then
        local col = act_param.Collision
        if col.Infos and col.Infos._items then
            for j, rect in reversePairs(col.Infos._items) do
                if rect ~= nil then
                    local posX = rect.OffsetX.v / SCALE_DIST
                    local sclX = rect.SizeX.v / SCALE_DIST * 2
                    
                    if rect:get_field("HitPos") ~= nil then
                        if rect.TypeFlag > 0 or (rect.TypeFlag == 0 and rect.PoseBit > 0) then
                            local hitbox_X
                            if facingRight then hitbox_X = posX + sclX / 2 else hitbox_X = posX - sclX / 2 end
                            
                            if maxHitboxEdgeX == nil then 
                                maxHitboxEdgeX = hitbox_X 
                                active_guard_bit = rect.GuardBit or 0
                            else
                                if facingRight and hitbox_X > maxHitboxEdgeX then 
                                    maxHitboxEdgeX = hitbox_X
                                    active_guard_bit = rect.GuardBit or 0
                                elseif not facingRight and hitbox_X < maxHitboxEdgeX then 
                                    maxHitboxEdgeX = hitbox_X
                                    active_guard_bit = rect.GuardBit or 0
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    if maxHitboxEdgeX ~= nil then
        local playerStartPosX = 0
        if player_obj.act_root and player_obj.act_root.x then
             playerStartPosX = player_obj.act_root.x.v / SCALE_DIST
        elseif player_obj.pos and player_obj.pos.x then
             playerStartPosX = player_obj.pos.x.v / SCALE_DIST
        end
        return abs(maxHitboxEdgeX - playerStartPosX), active_guard_bit
    end
    return 0, 0
end

-- =========================================================
-- 3. GESTION FICHIERS CONFIG
-- =========================================================
local function save_jump_data()
    local ok = json.dump_file(jump_filename, jump_data_store)
    if ok then status_msg = "Saved!" else status_msg = "Error Write!" end
    status_timer = 120
end

local function save_advanced_data()
    local lines = { "{" }
    local chars = {}
    for k in pairs(advanced_data) do table.insert(chars, k) end
    table.sort(chars) -- Trie les persos par ordre alphabétique
    
    for i, char_name in ipairs(chars) do
        local cdata = advanced_data[char_name]
        table.insert(lines, string.format('    "%s": {', char_name))
        
        local props = {}
        if cdata.red then table.insert(props, string.format('        "red": { "input": "%s", "ar": %.5f }', cdata.red.input, cdata.red.ar)) end
        if cdata.low then table.insert(props, string.format('        "low": { "input": "%s", "ar": %.5f }', cdata.low.input, cdata.low.ar)) end
        local y_off = cdata.yellow_offset or 50
        table.insert(props, string.format('        "yellow_offset": %d', y_off))
        
        if cdata.moves and #cdata.moves > 0 then
            if #props > 0 then table.insert(lines, table.concat(props, ",\n") .. ",") end
            table.insert(lines, '        "moves": [')
            for j, mv in ipairs(cdata.moves) do
                local comma = (j == #cdata.moves) and "" or ","
                local gb = mv.guard_bit or 0
                local isc = mv.is_cancelable and "true" or "false"
                local issc = mv.is_super_cancelable and "true" or "false"
                table.insert(lines, string.format('            { "input": "%s", "ar": %.5f, "guard_bit": %d, "is_cancelable": %s, "is_super_cancelable": %s }%s', mv.input, mv.ar, gb, isc, issc, comma))
            end
            table.insert(lines, '        ]')
        else
            if #props > 0 then table.insert(lines, table.concat(props, ",\n") .. ",\n        \"moves\": []")
            else table.insert(lines, '        "moves": []') end
        end
        
        local char_comma = (i == #chars) and "" or ","
        table.insert(lines, "    }" .. char_comma)
    end
    table.insert(lines, "}")
    
    -- Écriture manuelle du fichier custom
    local file = io.open("" .. advanced_filename, "w")
    if file then
        file:write(table.concat(lines, "\n"))
        file:close()
        status_msg = "ADV Saved!"
    else
        status_msg = "ERR ADV SAVE!"
    end
    status_timer = 120
end

local function sort_moves(cdata)
    if cdata and cdata.moves then
        table.sort(cdata.moves, function(a, b) return a.ar > b.ar end)
    end
end

local function log_move(char_name, input, ar, guard_bit, is_cancelable, is_super_cancelable)
    if not advanced_data[char_name] then
        advanced_data[char_name] = { moves = {}, red = nil, low = nil }
    end
    local cdata = advanced_data[char_name]
    if not cdata.moves then cdata.moves = {} end
    local found = false
    for _, entry in ipairs(cdata.moves) do
        if entry.input == input then
            entry.ar = ar
            entry.guard_bit = guard_bit
            entry.is_cancelable = is_cancelable or entry.is_cancelable
            entry.is_super_cancelable = is_super_cancelable or entry.is_super_cancelable

            found = true
            break
        end
    end
    if not found then
        table.insert(cdata.moves, { input = input, ar = ar, guard_bit = guard_bit, is_cancelable = is_cancelable, is_super_cancelable = is_super_cancelable })
    end
    sort_moves(cdata)
    save_advanced_data()
    status_msg = string.format("LOG: %s -> %.5f", input, ar)
    status_timer = 150
end

local function load_advanced_data()
    local f = json.load_file(advanced_filename)
    if f and type(f) == "table" then
        advanced_data = f
        for _, cdata in pairs(advanced_data) do
            sort_moves(cdata)
        end
        status_msg = "ADV Data Loaded"
    end
    status_timer = 120
end

local function load_jump_data()
    for i=1, 60 do 
        local k = string.format("ESF_%03d", i)
        if not jump_data_store[k] then jump_data_store[k] = {} end
    end
    
    local data = json.load_file(jump_filename)
    if data then
        for k, v in pairs(data) do jump_data_store[k] = v end
        status_msg = "Data Loaded OK"
    else 
        status_msg = "New Session" 
    end
    status_timer = 150
end

load_jump_data(); load_ui_config(); load_advanced_data()

-- =========================================================
-- 4. TELEPORT LOGIC (UPDATED: POS_SETx & via.sfix)
-- =========================================================
local function apply_teleport_exact(distance)
    local gb = sdk.find_type_definition("gBattle")
    if not gb then return end
    
    local sP = gb:get_field("Player"):get_data(nil)
    if not sP or not sP.mcPlayer then return end

    local function get_col_width(player)
        if not player or not player.pos or not player.mpActParam or not player.mpActParam.Collision then return 0.0 end
        local width = 0.0
        local col = player.mpActParam.Collision
        if col.Infos and col.Infos._items then
            for j, r in pairs(col.Infos._items) do
                if r and (r:get_field("Attr") ~= nil or r:get_field("HitNo") ~= nil) then
                    local size_x = r.SizeX.v / 6553600.0
                    if size_x > width then width = size_x end
                end
            end
        end
        return width * 100.0 -- Convert to cm
    end

    local p1 = sP.mcPlayer[0]
    local p2 = sP.mcPlayer[1]

    local p1_offset = tp_p1_border and get_col_width(p1) or 0.0
    local p2_offset = tp_p2_border and get_col_width(p2) or 0.0

    local total_center_dist = distance + p1_offset + p2_offset
    
    -- Surgical precision: compute in raw sfix units to prevent division drift (1 cm = 65536 units)
    local raw_total = math.floor((total_center_dist * 65536.0) + 0.5)
    local raw_p2 = math.floor(raw_total / 2.0)
    local raw_p1 = -(raw_total - raw_p2)

    local p1_pos_double = raw_p1 / 65536.0
    local p2_pos_double = raw_p2 / 65536.0

    local sfix_type = sdk.find_type_definition("via.sfix")
    if sfix_type then
        local sfix_from_double = sfix_type:get_method("From(System.Double)")
        if p1 and p1.POS_SETx then p1:POS_SETx(sfix_from_double:call(nil, p1_pos_double)) end
        if p2 and p2.POS_SETx then p2:POS_SETx(sfix_from_double:call(nil, p2_pos_double)) end
    end

    status_msg = string.format("APPLIED: %.5f (P1:%s P2:%s)", distance, tp_p1_border and "B" or "C", tp_p2_border and "B" or "C")
    status_timer = 150
end

-- =========================================================
-- 5. BOUCLE PRINCIPALE
-- =========================================================
local detected_infos = {
    [0] = { key = "ESF_000", name = "Wait...", last_ar = 0.0, live_input = "5", cur_act_id = -1 },
    [1] = { key = "ESF_000", name = "Wait...", last_ar = 0.0, live_input = "5", cur_act_id = -1 }
}
local origin_dist = 0.0

local t_med = sdk.find_type_definition("app.FBattleMediator")
if t_med then
    local m = t_med:get_method("UpdateGameInfo")
    sdk.hook(m, function(args)
        local mgr = sdk.to_managed_object(args[2])
        if mgr then
            local pt = t_med:get_field("PlayerType"):get_data(mgr)
            if pt and pt:call("get_Length") >= 2 then
                for i=0,1 do
                    local p = pt:call("GetValue", i)
                    local pid = p:get_type_definition():get_field("value__"):get_data(p)
                    local k = string.format("ESF_%03d", pid)
                    detected_infos[i].key = k
                    detected_infos[i].name = esf_names_map[k] or p:call("ToString")
                end
            end
        end
    end, function(ret) return ret end)
end

re.on_frame(function()
    local gb = sdk.find_type_definition("gBattle")
    local p1_x_dist, p2_x_dist = 0, 0
    
    if gb then 
        local sP = gb:get_field("Player"):get_data(nil)
        if sP and sP.mcPlayer then
            local p1 = sP.mcPlayer[0]; local p2 = sP.mcPlayer[1]
            if p1 then p1_x_dist = get_pos_x_dist(p1) end
            if p2 then p2_x_dist = get_pos_x_dist(p2) end
            origin_dist = abs(p1_x_dist - p2_x_dist)

            for i=0,1 do
                local p = sP.mcPlayer[i]
                if p then
                    local f_in = p:get_type_definition():get_field("pl_input_new")
                    local f_sw = p:get_type_definition():get_field("pl_sw_new")
                    local dv = (f_in and f_in:get_data(p)) or 0
                    local bv = (f_sw and f_sw:get_data(p)) or 0
                    local full_input = get_numpad_notation(dv) .. get_btn_text(bv)

                    local val, gb_val = get_hitbox_range_data(p, p.mpActParam)
                    if val > 0 then
                        detected_infos[i].last_ar = val
                    end

                    -- ADVANCED TRACKING
                    local st        = adv_state[i]
                    local cname_adv = esf_names_map[detected_infos[i].key] or detected_infos[i].name
                    
                    if cname_adv == "Alex" and p.mpActParam ~= nil and p.mpActParam.ActionPart ~= nil then
                        local eng = p.mpActParam.ActionPart._Engine
                        if eng ~= nil then
                            local act_id = eng:get_ActionID()
							if act_id == 972 -- LP en prowler
							or act_id == 971 -- LP en prowler
							or act_id == 970 -- LP en prowler
                            or act_id == 957 
							or act_id == 960 
							or act_id == 964 
							or act_id == 962 
							or act_id == 973 
							or act_id == 976 
							or act_id == 977 
							or act_id == 980 
							or act_id == 982 
							or act_id == 967 
							or act_id == 968 
							or act_id == 969 
							or act_id == 978 
							or act_id == 993 
							
							
							then cname_adv = "Alex_Prowler" end
                        end
                    end
                    detected_infos[i].name = cname_adv

                    -- Front montant bouton : nouveau appui (pas maintien)
                    local btn_text     = get_btn_text(bv)
                    local btn_text_prev = get_btn_text(st.prev_bv)
                    local new_press    = (btn_text ~= "" and btn_text_prev == "")
                    st.prev_bv = bv

                    if new_press then
                        st.last_attack_input = get_numpad_notation(dv) .. btn_text
                        st.peak_ar           = 0
                        st.peak_guard_bit    = 0
                        st.had_hitbox        = false
                        st.is_cancelable     = false
						st.is_super_cancelable = false
                    end


                    -- Capture dynamique du trigger_notice
                    local current_tn = p.trigger_notice or 0
                    if current_tn == 2 then
                        st.is_super_cancelable = true
                    end


                    -- Capture dynamique du trigger_notice
                    local current_tn = p.trigger_notice or 0
                    if current_tn == 1 then
                        st.is_cancelable = true
                    end

                    -- Accumulation peak AR et GuardBit associé
                    if val > 0 then
                        st.had_hitbox = true
                        if val > st.peak_ar then 
                            st.peak_ar = val 
                            st.peak_guard_bit = gb_val
                        end
                    end

                    -- Action ID & Margin Frame
                    local cur_act_id = -1
                    local cur_frame = 0
                    local margin_frame = 0
                    
                    if p.mpActParam ~= nil and p.mpActParam.ActionPart ~= nil then
                        local eng = p.mpActParam.ActionPart._Engine
                        if eng ~= nil then
                            cur_act_id = eng:get_ActionID()
                            local f_act = eng:get_ActionFrame()
                            local f_mar = eng:get_MarginFrame()
                            
                            -- Extract float values via ToString() just like read_sfix
                            if f_act then cur_frame = math.floor(tonumber(f_act:call("ToString()")) or 0) end
                            if f_mar then margin_frame = math.floor(tonumber(f_mar:call("ToString()")) or 0) end
                        end
                    end
                    detected_infos[i].cur_act_id = cur_act_id

                    -- Check if action changed OR if we perfectly hit the margin frame
                    local action_changed = (cur_act_id ~= -1 and cur_act_id ~= st.act_id)
                    local margin_reached = (margin_frame > 0 and cur_frame == margin_frame)

                    if action_changed or (margin_reached and not st.margin_logged) then
                        -- Log if the action had hitboxes
                        if st.logging_active
                           and st.had_hitbox and st.peak_ar > 0.01
                           and st.last_attack_input ~= "5"
                           and cname_adv ~= "Wait..." then
                            log_move(cname_adv, st.last_attack_input, st.peak_ar, st.peak_guard_bit, st.is_cancelable, st.is_super_cancelable)
                        end
                        
                        -- Reset states when action ID completely changes
                        if action_changed then
                            st.act_id        = cur_act_id
                            st.had_hitbox    = false
                            st.is_cancelable = false
                            st.is_super_cancelable = false
                            st.margin_logged = false
                        end
                        
                        -- Prevent duplicate logging on the same margin frame
                        if margin_reached then
                            st.margin_logged = true
                        end
                    end

                    if full_input ~= "5" then detected_infos[i].live_input = full_input end

                    -- JUMP LOGIC
                    local raw_x, raw_y = 0, 0
                    if p.pos and p.pos.x and p.pos.y then
                        raw_x = p.pos.x.v
                        raw_y = p.pos.y.v
                    end
                    
                    local px_jump = raw_x / SCALE_JUMP
                    local py_jump = raw_y / SCALE_JUMP
                    
                    local rec = jump_rec_state[i]
                    if rec.status == REC_WAITING then
                        if py_jump <= 0.01 then 
                            rec.origin_x = px_jump
                        else 
                            rec.status = REC_RECORDING
                            rec.buffer = {} 
                            table.insert(rec.buffer, {x=0.0, y=0.0})
                            table.insert(rec.buffer, {x=abs(px_jump - rec.origin_x), y=py_jump}) 
                        end
                    elseif rec.status == REC_RECORDING then
                        if py_jump <= 0.001 then 
                            table.insert(rec.buffer, {x=abs(px_jump - rec.origin_x), y=0.0})
                            rec.buffer = refine_buffer(rec.buffer)
                            
                            local k = detected_infos[i].key
                            if not jump_data_store[k] then jump_data_store[k] = {} end
                            local target = jump_data_store[k]
                            
							target.points = {}
                            for _, point in ipairs(rec.buffer) do table.insert(target.points, point) end
							                            
                            save_jump_data()
                            rec.status = REC_IDLE; status_msg = "JUMP SAVED P"..(i+1); status_timer = 150
                        else 
                            table.insert(rec.buffer, {x=abs(px_jump - rec.origin_x), y=py_jump}) 
                        end
                    end
                end
            end
        end
    end

    if ui_state.show_overlay then
        if first_draw then
            imgui.set_next_window_pos(Vector2f.new(ui_state.pos_x, ui_state.pos_y), 1 << 3)
            first_draw = false
        end

        if imgui.begin_window("SF6 DISTANCE LOGGER", true, 32) then
    -- Toggle to disable the floating window from within itself
    local changed, new_val = imgui.checkbox("Afficher Overlay Flottant", ui_state.show_overlay)
    if changed then
        ui_state.show_overlay = new_val
        ui_dirty = true
        save_ui_config()
    end
    imgui.separator()

    local cur_pos = imgui.get_window_pos()
    if abs(cur_pos.x - ui_state.pos_x) > 1.0 or abs(cur_pos.y - ui_state.pos_y) > 1.0 then
        ui_state.pos_x = cur_pos.x
        ui_state.pos_y = cur_pos.y
        ui_dirty = true
    end
    
    draw_main_content(true) 
    imgui.end_window()
end
    end

    if ui_dirty then
        ui_save_timer = ui_save_timer + 1
        if ui_save_timer > 120 then 
            save_ui_config()
            ui_save_timer = 0
        end
    end
end)

-- =========================================================
-- SHARED DRAW FUNCTION & THEMES
-- =========================================================
local COL_RED    = 0xFF4444FF
local COL_LOW    = 0xFFCC44BB
local COL_YELLOW = 0xFF00FFFF
local COL_GREEN  = 0xFF00FF00
local COL_CYAN   = 0xFFFFFF00
local COL_GREY   = 0xFF888888
local COL_GOLD   = 0xFF00D5FF 

local UI_THEME = {
    hdr_info    = { base = 0xFFDB9834, hover = 0xFFE6A94D, active = 0xFFC78320 },
    hdr_session = { base = 0xFFB6599B, hover = 0xFFC770AC, active = 0xFFA04885 },
    hdr_rules   = { base = 0xFF5D6DDA, hover = 0xFF7382E6, active = 0xFF4555C9 },
}

local function styled_header(label, style)
    imgui.push_style_color(24, style.base); imgui.push_style_color(25, style.hover); imgui.push_style_color(26, style.active)
    local is_open = imgui.collapsing_header(label)
    imgui.pop_style_color(3)
    return is_open
end

function draw_main_content(is_overlay)
    if status_timer > 0 then
        imgui.text_colored(status_msg, COL_GREEN)
        status_timer = status_timer - 1
        imgui.separator()
    end

    -- ==========================================
    -- 1. TELEPORT (GLOBAL)
    -- ==========================================
    if styled_header("--- GLOBAL : TELEPORT ---", UI_THEME.hdr_info) then
        -- Checkbox P1
        if imgui.checkbox("P1 Center", not tp_p1_border) then tp_p1_border = false end
        imgui.same_line()
        if imgui.checkbox("P1 Border", tp_p1_border) then tp_p1_border = true end

        -- Checkbox P2
        if imgui.checkbox("P2 Center", not tp_p2_border) then tp_p2_border = false end
        imgui.same_line()
        if imgui.checkbox("P2 Border", tp_p2_border) then tp_p2_border = true end

        imgui.separator()

        local t_str = tostring(teleport_target_dist)
        imgui.push_item_width(100)
        local changed, new_t = imgui.input_text("Target", t_str)
        imgui.pop_item_width()
        if changed then local n = tonumber(new_t); if n then teleport_target_dist = n end end
        imgui.same_line(); if imgui.button("APPLY") then apply_teleport_exact(teleport_target_dist) end

        if imgui.button("184") then teleport_target_dist = 184; apply_teleport_exact(184) end
        imgui.same_line()
        if imgui.button("185") then teleport_target_dist = 185; apply_teleport_exact(185) end
        imgui.same_line()
        if imgui.button("179") then teleport_target_dist = 179; apply_teleport_exact(179) end
        imgui.same_line()
        if imgui.button("180") then teleport_target_dist = 180; apply_teleport_exact(180) end

        imgui.text_colored(string.format("Current Dist: %.5f", origin_dist), COL_GREEN)
    end
    imgui.separator()

    -- ==========================================
    -- 2. PLAYERS DATA (JUMP + ADVANCED)
    -- ==========================================
    for i = 0, 1 do
        local info      = detected_infos[i]
        local key       = info.key
        local cname     = info.name
        
        if styled_header(string.format("[ PLAYER %d : %s ]", i+1, cname), UI_THEME.hdr_session) then
            -- ---- A. JUMP DATA ----
            imgui.text_colored(">> JUMP CONFIGURATION", COL_YELLOW)
            local jump_info = jump_data_store[key]
            local has_jump  = (jump_info and jump_info.points and #jump_info.points > 0)
            local rec = jump_rec_state[i]
            
            if rec.status == REC_IDLE then
                if imgui.button("REC JUMP##"..i) then rec.status = REC_WAITING; rec.buffer = {} end
                if has_jump then imgui.same_line(); imgui.text_colored("OK", COL_GREEN) end
            elseif rec.status == REC_WAITING then
                imgui.text_colored("JUMP NOW...", 0xFF00FFFF)
                imgui.same_line()
                if imgui.button("X##jrec"..i) then rec.status = REC_IDLE end
            elseif rec.status == REC_RECORDING then
                imgui.text_colored("REC...", COL_RED)
            end

            imgui.same_line()
            if imgui.button("XUp St##"..i) then
                if not jump_data_store[key] then jump_data_store[key] = {} end
                jump_data_store[key].cross_up_st = origin_dist; save_jump_data()
            end
            if jump_info and jump_info.cross_up_st then
                imgui.same_line(); imgui.text(string.format("(%.5f)", jump_info.cross_up_st))
            end

            imgui.same_line()
            if imgui.button("XUp Cr##"..i) then
                if not jump_data_store[key] then jump_data_store[key] = {} end
                jump_data_store[key].cross_up_cr = origin_dist; save_jump_data()
            end
            if jump_info and jump_info.cross_up_cr then
                imgui.same_line(); imgui.text(string.format("(%.5f)", jump_info.cross_up_cr))
            end

            imgui.separator()

            -- ---- B. ADVANCED ATTACK DATA ----
            imgui.text_colored(">> ADVANCED ATTACK RANGES", COL_YELLOW)
            if cname == "Wait..." then
                imgui.text_colored("En attente...", COL_GREY)
            else
                if not advanced_data[cname] then advanced_data[cname] = { moves = {}, red = nil, low = nil } end
                local cdata = advanced_data[cname]
                if not cdata.moves then cdata.moves = {} end

                local max_ar_per_gb = {}
                for _, entry in ipairs(cdata.moves) do
                    local gb = entry.guard_bit or 0
                    if gb > 0 then
                        if not max_ar_per_gb[gb] or entry.ar > max_ar_per_gb[gb] then max_ar_per_gb[gb] = entry.ar end
                    end
                end

                if cdata.low then imgui.text_colored(string.format("LOW    [%s]  :  %.5f", cdata.low.input, cdata.low.ar), COL_LOW)
                else imgui.text_colored("LOW    [--]  :  --", COL_LOW) end

                if cdata.red then imgui.text_colored(string.format("RED    [%s]  :  %.5f", cdata.red.input, cdata.red.ar), COL_RED)
                else imgui.text_colored("RED    [--]  :  --", COL_RED) end

                local y_off = cdata.yellow_offset or 50
                local base_ar = nil
                local base_input = "--"
                
                if cdata.red and cdata.low then
                    if cdata.red.ar >= cdata.low.ar then base_ar = cdata.red.ar; base_input = cdata.red.input
                    else base_ar = cdata.low.ar; base_input = cdata.low.input end
                elseif cdata.red then base_ar = cdata.red.ar; base_input = cdata.red.input
                elseif cdata.low then base_ar = cdata.low.ar; base_input = cdata.low.input end

                if base_ar then
                    local yellow_val = base_ar + y_off
                    imgui.text_colored(string.format("YELLOW [%s]  :  %.5f  (+%d)", base_input, yellow_val, y_off), COL_YELLOW)
                else
                    imgui.text_colored(string.format("YELLOW [--]  :  --  (+%d)", y_off), COL_YELLOW)
                end

                imgui.push_item_width(60)
                local ch, ns = imgui.input_text("Y-Off##yoff"..i, tostring(y_off))
                imgui.pop_item_width()
                if ch then local n = tonumber(ns); if n then cdata.yellow_offset = n; save_advanced_data() end end
                imgui.separator()

                local st_ui = adv_state[i]
                imgui.text_colored(string.format("Act ID : %d", info.cur_act_id), COL_GREY)
                -- Update Live and Memos display to 5 decimal places for surgical precision
                imgui.text(string.format("Live   : [%s]  AR: %.5f", info.live_input, info.last_ar))
                
                local cancel_info = st_ui.is_cancelable and "  [C]" or ""
                local super_cancel_info = st_ui.is_super_cancelable and "  [SC]" or ""
                imgui.text_colored(string.format("Memos  : [%s]  AR: %.5f  (Grd:%s)%s%s", st_ui.last_attack_input, st_ui.peak_ar, get_guard_type_name(st_ui.peak_guard_bit), cancel_info, super_cancel_info), COL_CYAN)

                local st_btn = adv_state[i]
                local btn_label = st_btn.logging_active and "STOP LOG##"..i or "START LOG##"..i
                if imgui.button(btn_label) then st_btn.logging_active = not st_btn.logging_active end
                imgui.same_line()
                if st_btn.logging_active then imgui.text_colored("LOGGING STARTED", COL_GREEN)
                else imgui.text_colored("LOGGING STOPPED", COL_RED) end

                if #cdata.moves > 0 then
                    local is_moves_open = imgui.tree_node("Recorded Moves##" .. i)
                    imgui.same_line()
                    imgui.text_colored(string.format("(%d)", #cdata.moves), COL_GREY)
                    if is_moves_open then
                        local to_delete = nil
                        for idx, entry in ipairs(cdata.moves) do
                            local is_red = cdata.red and cdata.red.input == entry.input
                            local is_low = cdata.low and cdata.low.input == entry.input
                            local edit_key = i .. "_" .. idx
                            
                            local gb_val = entry.guard_bit or 0
                            local gb_name = get_guard_type_name(gb_val)
                            local is_max_for_gb = (gb_val > 0 and entry.ar == max_ar_per_gb[gb_val])

                            if edit_state.key == edit_key then
                                imgui.push_item_width(100)
                                local c1, new_name = imgui.input_text("##editname"..edit_key, edit_state.buf)
                                if c1 then edit_state.buf = new_name end
                                imgui.pop_item_width()
                                imgui.same_line()
                                imgui.push_item_width(80)
                                local c2, new_ar = imgui.input_text("##editar"..edit_key, edit_state.ar_buf)
                                if c2 then edit_state.ar_buf = new_ar end
                                imgui.pop_item_width()
                                imgui.same_line()
                                if imgui.button("OK##ok"..edit_key) then
                                    local trimmed = edit_state.buf:match("^%s*(.-)%s*$")
                                    if trimmed ~= "" then
                                        if cdata.red and cdata.red.input == entry.input then cdata.red.input = trimmed end
                                        if cdata.low and cdata.low.input == entry.input then cdata.low.input = trimmed end
                                        entry.input = trimmed
                                    end
                                    local new_ar_val = tonumber(edit_state.ar_buf)
                                    if new_ar_val then
                                        if cdata.red and cdata.red.input == entry.input then cdata.red.ar = new_ar_val end
                                        if cdata.low and cdata.low.input == entry.input then cdata.low.ar = new_ar_val end
                                        entry.ar = new_ar_val
                                    end
                                    save_advanced_data()
                                    status_msg = string.format("Modifié → [%s] %.5f", entry.input, entry.ar)
                                    status_timer = 150
                                    edit_state.key = nil
                                end
                                imgui.same_line()
                                if imgui.button("Annuler##can"..edit_key) then edit_state.key = nil end
                            else
                                local row_text = string.format("  [%s] [%s]  AR: %.5f", entry.input, gb_name, entry.ar)
                                if is_red and is_low then imgui.text_colored(row_text .. "  [R][L]", 0xFFEE88FF)
                                elseif is_red then imgui.text_colored(row_text .. "  [R]", COL_RED)
                                elseif is_low then imgui.text_colored(row_text .. "  [L]", COL_LOW)
                                else imgui.text(row_text) end

                                if entry.is_cancelable then imgui.same_line(); imgui.text_colored(" [C]", COL_GREEN) end
                                if entry.is_super_cancelable then imgui.same_line(); imgui.text_colored(" [SC]", COL_RED) end
                                if is_max_for_gb then imgui.same_line(); imgui.text_colored(" ★ [MAX " .. gb_name .. "]", COL_GOLD) end

                                -- New Action Buttons
                                imgui.same_line()
                                if imgui.button("APPLY##tp"..edit_key) then apply_teleport_exact(entry.ar) end
                                
                                -- imgui.same_line()
                                -- if imgui.button("-0.00001##min"..edit_key) then
                                    -- entry.ar = entry.ar - 0.00001
                                    -- if is_red then cdata.red.ar = entry.ar end
                                    -- if is_low then cdata.low.ar = entry.ar end
                                    -- save_advanced_data()
                                -- end

                                -- imgui.same_line()
                                -- if imgui.button("+0.00001##plus"..edit_key) then
                                    -- entry.ar = entry.ar + 0.00001
                                    -- if is_red then cdata.red.ar = entry.ar end
                                    -- if is_low then cdata.low.ar = entry.ar end
                                    -- save_advanced_data()
                                -- end

                                -- Existing Action Buttons
                                imgui.same_line()
                                if imgui.button("Edit##ed"..edit_key) then
                                    edit_state.key = edit_key
                                    edit_state.buf = entry.input
                                    edit_state.ar_buf = string.format("%.5f", entry.ar)
                                end
                                imgui.same_line()
                                if imgui.button("R##sr"..i.."_"..idx) then
                                    cdata.red = { input = entry.input, ar = entry.ar }; save_advanced_data()
                                    status_msg = string.format("RED = [%s] %.5f", entry.input, entry.ar); status_timer = 150
                                end
                                imgui.same_line()
                                if imgui.button("L##sl"..i.."_"..idx) then
                                    cdata.low = { input = entry.input, ar = entry.ar }; save_advanced_data()
                                    status_msg = string.format("LOW = [%s] %.5f", entry.input, entry.ar); status_timer = 150
                                end
                                imgui.same_line()
                                if imgui.button("X##del"..i.."_"..idx) then to_delete = idx end
                            end
                        end

                        if to_delete then
                            if cdata.red and cdata.red.input == cdata.moves[to_delete].input then cdata.red = nil end
                            if cdata.low and cdata.low.input == cdata.moves[to_delete].input then cdata.low = nil end
                            table.remove(cdata.moves, to_delete)
                            save_advanced_data()
                        end
                        imgui.tree_pop()
                    end
                else
                    imgui.text_colored("  (en attente d'actions...)", COL_GREY)
                end
            end
        end
        imgui.separator()
    end
end

re.on_draw_ui(function()
    if imgui.tree_node("SF6 DISTANCE LOGGER") then
        local changed, new_val = imgui.checkbox("Afficher Overlay Flottant", ui_state.show_overlay)
        if changed then
            ui_state.show_overlay = new_val
            ui_dirty = true
            save_ui_config()
        end
        
        if not ui_state.show_overlay then
            imgui.separator()
            imgui.text_colored("MODE MENU REFRAMEWORK (Overlay Masqué)", 0xFF00FFFF)
            draw_main_content(false)
        end

        imgui.tree_pop()
    end
end)