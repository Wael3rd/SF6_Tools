--[[
RE Framework Lua Script for Street Fighter 6 (SheldonsBoxes.lua - v17.3 PAUSE UPDATE)
Changes:
- Replaced timer-based pause detection with PauseManager (Same as DistanceViewer).
- Normalized X/Y positioning for Charge Bars.
- Dynamic resizing based on screen resolution.
]]

local sdk = sdk
local imgui = imgui
local re = re
local draw = draw
local json = json

require("func/SharedHooks")
local GS = require("func/GameState")
local UIKit = require("func/UIKit")
local Vector3f = Vector3f

-- =========================================================
-- [OPTIMIZATION GLOBALS]
-- =========================================================
local v_tl = Vector3f.new(0, 0, 0)
local v_tr = Vector3f.new(0, 0, 0)
local v_bl = Vector3f.new(0, 0, 0)
local v_br = Vector3f.new(0, 0, 0)
local v_pos = Vector3f.new(0, 0, 0)
local v_p1 = Vector3f.new(0, 0, 0)
local v_p2 = Vector3f.new(0, 0, 0)

-- =========================================================
-- [1. CONFIGURATION & GLOBAL VARIABLES]
-- =========================================================
local charges_file = "SheldonsBoxes_data/SheldonsBoxes_Charges.json"
local saved_charge_db = {}
local loaded_db = _G.safe_load_json(charges_file)
if loaded_db then saved_charge_db = loaded_db end
local function save_charge_db() json.dump_file(charges_file, saved_charge_db) end
local player_max_charges = { [0] = { last_loaded_esf = nil }, [1] = { last_loaded_esf = nil } }

-- Configuration (Normalized)
local config_file = "SheldonsBoxes_data/SheldonsBoxes_Config.json"
local config = { 
    show_distance_arrow = true,
	divide_distance_display = false,
    arrow_y_offset = 0.0,
    arrow_thickness = 40.0,
    hud_x_padding = 0.286,
    hud_y_pos = (reframework:get_commit_count() <= 1695) and 0.084 or 0.132,
    font_base_size = (reframework:get_commit_count() <= 1695) and 99 or 24,
    font_filename = "frutigerltarabic-57cn.ttf",
    outline_thickness = 1.13,
    -- Charge Bars
    show_charge_bars = true,
    charge_x_pos = 0.02,
    charge_y_pos = 0.30,
    charge_width = 0.16,
    charge_height = 0.04,
    -- Box Colors & Thickness
    box_colors = {
        hitbox = 0xFFC04000, throwbox = 0xFFFF80D0, clash = 0xFFE69138, proximity = 0xFF5B5B5B,
        pushbox = 0xFFFFFF00, hurtbox = 0xFF00FF00, hurtbox_invuln = 0xFF8000FF,
        uniquebox = 0xFF00FFEE, throwhurtbox = 0xFF0000FF,
    },
    box_fill_alphas = {
        hitbox = 77, throwbox = 77, clash = 64, proximity = 64, pushbox = 64, 
        hurtbox = 64, hurtbox_invuln = 64, uniquebox = 77, throwhurtbox = 77
    },
    box_thicknesses = {
        hitbox = 1, throwbox = 1, clash = 1, proximity = 1, pushbox = 1, 
        hurtbox = 1, hurtbox_invuln = 1, uniquebox = 1, throwhurtbox = 1
    },
    fill_alpha = 77,
    -- Vital Ruler
    vital_ruler = {
        enabled       = true,
        pos_x         = 0.10,
        pos_y         = 0.089,
        width         = 0.353,
        line_thick    = 3,
        tick_len      = 0.035,
        tick_angle    = -36,
        tick_thick    = 2,
        show_half     = true,
        show_tenth    = true,
        show_labels   = true,
        label_compact = true,
        label_off_x   = 0.0,
        label_off_y   = -0.002,
        font_size     = 0.010,
        col_line      = 0xFFFFFFFF,
        col_tick      = 0xFFFFFFFF,
        col_label     = 0xFFFFFFFF,
        use_segments  = false,
        seg1_pct      = 0.30,
        seg2_pct      = 0.40,
        seg2_angle    = 0,
    },
}
local loaded_conf = _G.safe_load_json(config_file)
if loaded_conf then 
    for k,v in pairs(loaded_conf) do 
        if k == "box_colors" and type(v) == "table" then for ck, cv in pairs(v) do config.box_colors[ck] = cv end
        elseif k == "box_fill_alphas" and type(v) == "table" then for ck, cv in pairs(v) do config.box_fill_alphas[ck] = cv end
        elseif k == "box_thicknesses" and type(v) == "table" then for ck, cv in pairs(v) do config.box_thicknesses[ck] = cv end
        elseif k == "vital_ruler" and type(v) == "table" then for ck, cv in pairs(v) do config.vital_ruler[ck] = cv end
        elseif k == "vital_ruler_per_hud" and type(v) == "table" then
            if not config.vital_ruler_per_hud then config.vital_ruler_per_hud = {} end
            for hk, hv in pairs(v) do
                if type(hv) == "table" then
                    config.vital_ruler_per_hud[hk] = config.vital_ruler_per_hud[hk] or {}
                    for ck, cv in pairs(hv) do config.vital_ruler_per_hud[hk][ck] = cv end
                end
            end
        elseif k == "layout_per_hud" and type(v) == "table" then
            if not config.layout_per_hud then config.layout_per_hud = {} end
            for hk, hv in pairs(v) do
                if type(hv) == "table" then
                    config.layout_per_hud[hk] = config.layout_per_hud[hk] or {}
                    for ck, cv in pairs(hv) do
                        if ck == "vital_ruler" and type(cv) == "table" then
                            config.layout_per_hud[hk].vital_ruler = config.layout_per_hud[hk].vital_ruler or {}
                            for vk, vv in pairs(cv) do config.layout_per_hud[hk].vital_ruler[vk] = vv end
                        else
                            config.layout_per_hud[hk][ck] = cv
                        end
                    end
                end
            end
        elseif k == "display" and type(v) == "table" then config.display = v
        else config[k] = v end
    end
end
local _sb_ver_font = (reframework:get_commit_count() <= 1695) and 99 or 24
local _sb_ver_ypos = (reframework:get_commit_count() <= 1695) and 0.084 or 0.132
config.font_base_size = _sb_ver_font
config.hud_y_pos = _sb_ver_ypos
if config.layout_per_hud then
    for _, lay in pairs(config.layout_per_hud) do
        if type(lay) == "table" then lay.hud_y_pos = _sb_ver_ypos end
    end
end
if not config.box_fill_alphas then config.box_fill_alphas = {} end
if not config.box_thicknesses then config.box_thicknesses = {} end

-- Per-HUD layout configs
local HUD_KEYS = { "Default", "_01", "_02", "_03", "_04", "_05", "_06", "_07" }
local HUD_NAMES = {
    ["Default"] = "SF6", ["_01"] = "Type 01", ["_02"] = "SSF2",
    ["_03"] = "SFZ3", ["_04"] = "SF33s", ["_05"] = "SF4",
    ["_06"] = "SF5", ["_07"] = "SIMSIM",
}
local function deep_copy(src)
    if type(src) ~= "table" then return src end
    local t = {}
    for k, v in pairs(src) do t[k] = deep_copy(v) end
    return t
end
local function build_default_layout()
    return {
        vital_ruler = deep_copy(config.vital_ruler),
        charge_x_pos = config.charge_x_pos,
        charge_y_pos = config.charge_y_pos,
        charge_width = config.charge_width,
        charge_height = config.charge_height,
        hud_x_padding = config.hud_x_padding,
        hud_y_pos = config.hud_y_pos,
    }
end
-- Migrate: if vital_ruler_per_hud exists from previous version, merge into layout_per_hud
if not config.layout_per_hud then
    config.layout_per_hud = {}
    if config.vital_ruler_per_hud then
        for key, vr in pairs(config.vital_ruler_per_hud) do
            config.layout_per_hud[key] = build_default_layout()
            config.layout_per_hud[key].vital_ruler = deep_copy(vr)
        end
    end
end
for _, key in ipairs(HUD_KEYS) do
    if not config.layout_per_hud[key] then
        config.layout_per_hud[key] = build_default_layout()
    end
    local lay = config.layout_per_hud[key]
    if not lay.vital_ruler then lay.vital_ruler = deep_copy(config.vital_ruler) end
    if not lay.charge_x_pos then lay.charge_x_pos = config.charge_x_pos end
    if not lay.charge_y_pos then lay.charge_y_pos = config.charge_y_pos end
    if not lay.charge_width then lay.charge_width = config.charge_width end
    if not lay.charge_height then lay.charge_height = config.charge_height end
    if not lay.hud_x_padding then lay.hud_x_padding = config.hud_x_padding end
    if not lay.hud_y_pos then lay.hud_y_pos = config.hud_y_pos end
end
local function hud_suffix()
    return _G.CurrentHudSuffix or "Default"
end
local function get_layout()
    local suffix = hud_suffix()
    return config.layout_per_hud[suffix] or config.layout_per_hud["Default"]
end
local function vr_get_active()
    return get_layout().vital_ruler
end

local function save_config()
    json.dump_file(config_file, config)
end

-- =========================================================
-- [THEMED UI - Same style as Distance Viewer / Logger]
-- =========================================================
local COL_RED    = 0xFF4444FF
local COL_LOW    = 0xFFCC44BB
local COL_YELLOW = 0xFF00FFFF
local COL_GREEN  = 0xFF00FF00
local COL_CYAN   = 0xFFFFFF00
local COL_GREY   = 0xFF888888
local COL_GOLD   = 0xFF00D5FF

local UI_THEME = {
    hdr_info    = UIKit.THEME.hdr_gold,
    hdr_session = UIKit.THEME.hdr_purple,
    hdr_rules   = UIKit.THEME.hdr_blue,
}

local styled_header = UIKit.styled_header

-- =========================================================
-- [BOX COLOR SYSTEM]
-- =========================================================
local argb_to_abgr = UIKit.argb_to_abgr
local function make_fill(abgr_num, alpha) return ((alpha & 0xFF) << 24) | (abgr_num & 0x00FFFFFF) end

local box_col = {}
local function update_box_colors()
    for key, col in pairs(config.box_colors) do
        if type(col) == "string" then col = tonumber(col, 16) or 0xFFFFFFFF; config.box_colors[key] = col end
        local abgr_col = argb_to_abgr(col)
        box_col[key] = abgr_col
        local fa = config.box_fill_alphas[key] or config.fill_alpha or 77
        box_col[key .. "_fill"] = make_fill(abgr_col, fa)
    end
end
update_box_colors()

local stats_pos_y = 15
local margin = 20
local stats_font_size = 52
local x_pos_font_size = 26
local x_pos_y_offset = 8
local shadow_layers = 3 
local shadow_color = 0x80000000

local charge_meter_frame_font_size = 18 
local arrow_thickness = 40.0; local distance_text_color = 0xFFFFFFFF; local distance_font_size = 23; local distance_text_y_offset = -15
local arrow_col_grey = {r=128,g=128,b=128,a=128}; local arrow_color_far={r=0,g=255,b=0,a=128}; local arrow_color_close={r=255,g=0,b=0,a=128}
local gradient_end_dist=2.0; local gradient_sharp_start=2.5; local fade_start_angle_ratio=0.5; local fade_full_angle_ratio=1.0

local display_p1_hitboxes=true; local display_p1_hurtboxes=true; local display_p1_pushboxes=true; local display_p1_throwboxes=true; local display_p1_throwhurtboxes=true; local display_p1_proximityboxes=true; local display_p1_uniqueboxes=true; local display_p1_properties=true; local display_p1_position_dot=true; local display_p1_clashbox=true; local display_p1_charge_bars=true; local hide_p1_boxes=false;
local display_p2_hitboxes=true; local display_p2_hurtboxes=true; local display_p2_pushboxes=true; local display_p2_throwboxes=true; local display_p2_throwhurtboxes=true; local display_p2_proximityboxes=true; local display_p2_uniqueboxes=true; local display_p2_properties=true; local display_p2_position_dot=true; local display_p2_clashbox=true; local display_p2_charge_bars=true; local hide_p2_boxes=false;
local display_p1_hud_pos=true; local display_p1_hud_hp=true; local display_p1_hud_dr=true; local display_p1_hud_sa=true;
local display_p2_hud_pos=true; local display_p2_hud_hp=true; local display_p2_hud_dr=true; local display_p2_hud_sa=true;

-- Restore display flags from config
if config.display then
    local d = config.display
    if d.p1_hitboxes ~= nil then display_p1_hitboxes = d.p1_hitboxes end
    if d.p1_hurtboxes ~= nil then display_p1_hurtboxes = d.p1_hurtboxes end
    if d.p1_pushboxes ~= nil then display_p1_pushboxes = d.p1_pushboxes end
    if d.p1_throwboxes ~= nil then display_p1_throwboxes = d.p1_throwboxes end
    if d.p1_throwhurtboxes ~= nil then display_p1_throwhurtboxes = d.p1_throwhurtboxes end
    if d.p1_proximityboxes ~= nil then display_p1_proximityboxes = d.p1_proximityboxes end
    if d.p1_uniqueboxes ~= nil then display_p1_uniqueboxes = d.p1_uniqueboxes end
    if d.p1_properties ~= nil then display_p1_properties = d.p1_properties end
    if d.p1_position_dot ~= nil then display_p1_position_dot = d.p1_position_dot end
    if d.p1_clashbox ~= nil then display_p1_clashbox = d.p1_clashbox end
    if d.p1_charge_bars ~= nil then display_p1_charge_bars = d.p1_charge_bars end
    if d.hide_p1 ~= nil then hide_p1_boxes = d.hide_p1 end
    if d.p2_hitboxes ~= nil then display_p2_hitboxes = d.p2_hitboxes end
    if d.p2_hurtboxes ~= nil then display_p2_hurtboxes = d.p2_hurtboxes end
    if d.p2_pushboxes ~= nil then display_p2_pushboxes = d.p2_pushboxes end
    if d.p2_throwboxes ~= nil then display_p2_throwboxes = d.p2_throwboxes end
    if d.p2_throwhurtboxes ~= nil then display_p2_throwhurtboxes = d.p2_throwhurtboxes end
    if d.p2_proximityboxes ~= nil then display_p2_proximityboxes = d.p2_proximityboxes end
    if d.p2_uniqueboxes ~= nil then display_p2_uniqueboxes = d.p2_uniqueboxes end
    if d.p2_properties ~= nil then display_p2_properties = d.p2_properties end
    if d.p2_position_dot ~= nil then display_p2_position_dot = d.p2_position_dot end
    if d.p2_clashbox ~= nil then display_p2_clashbox = d.p2_clashbox end
    if d.p2_charge_bars ~= nil then display_p2_charge_bars = d.p2_charge_bars end
    if d.hide_p2 ~= nil then hide_p2_boxes = d.hide_p2 end
    if d.p1_hud_pos ~= nil then display_p1_hud_pos = d.p1_hud_pos end
    if d.p1_hud_hp ~= nil then display_p1_hud_hp = d.p1_hud_hp end
    if d.p1_hud_dr ~= nil then display_p1_hud_dr = d.p1_hud_dr end
    if d.p1_hud_sa ~= nil then display_p1_hud_sa = d.p1_hud_sa end
    if d.p2_hud_pos ~= nil then display_p2_hud_pos = d.p2_hud_pos end
    if d.p2_hud_hp ~= nil then display_p2_hud_hp = d.p2_hud_hp end
    if d.p2_hud_dr ~= nil then display_p2_hud_dr = d.p2_hud_dr end
    if d.p2_hud_sa ~= nil then display_p2_hud_sa = d.p2_hud_sa end
end
local property_text_font_size=14
local colors = { Red=0xFF0000FF, Green=0xFF00FF00, Grey=0xFF5b5b5b, White=0xFFFFFFFF, VisualChargeMeterFillStart={r=255, g=255, b=0, a=178}, VisualChargeMeterFillEnd={r=0, g=255, b=0, a=178}, VisualChargeMeterBackground=0xB3333333, VisualChargeMeterOutline=0xB3000000, VisualChargeMeterText=0xFFFFFFFF }

-- [REMOVED OLD PAUSE LOGIC]
-- Timer variables are no longer needed here

-- =========================================================
-- [2. FONT SYSTEM & HELPERS]
-- =========================================================
local custom_font = { obj = nil, last_h = 0, last_name = "", last_size = 0 }
local function try_load_font()
    local display_size = imgui.get_display_size()
    if not display_size then return end
    local sh = display_size.x * 9 / 16
    local scale_factor = sh / 1080.0
    local target_size = math.floor(config.font_base_size * scale_factor)
    if custom_font.obj == nil or sh ~= custom_font.last_h or config.font_filename ~= custom_font.last_name or config.font_base_size ~= custom_font.last_size then
        local font = imgui.load_font(config.font_filename, target_size)
        if font then custom_font.obj = font; custom_font.last_h = sh; custom_font.last_name = config.font_filename; custom_font.last_size = config.font_base_size end
    end
end

local function draw_text_with_outline(text, x, y, color)
    local ds = imgui.get_display_size()
    local scale = (ds.x * 9 / 16) / 1080.0
    local thickness = math.max(1, math.floor(config.outline_thickness * scale))
    local outline_color = 0xFF000000
    if custom_font.obj then imgui.push_font(custom_font.obj) end
    for dx = -thickness, thickness, thickness do
        for dy = -thickness, thickness, thickness do
            if dx ~= 0 or dy ~= 0 then draw.text(text, x + dx, y + dy, outline_color) end
        end
    end
    draw.text(text, x, y, color)
    if custom_font.obj then imgui.pop_font() end
end

local function get_text_size_custom(text)
    if custom_font.obj then imgui.push_font(custom_font.obj) end
    local ts = imgui.calc_text_size(text)
    if custom_font.obj then imgui.pop_font() end
    return ts.x, ts.y
end

local function bitand(a, b) return (a % (b + b) >= b) and b or 0 end
local function interpolate(a,b,f)f=math.max(0,math.min(1,f));return a+(b-a)*f end
local function interpolate_color(c1,c2,f)local r=math.floor(interpolate(c1.r,c2.r,f));local g=math.floor(interpolate(c1.g,c2.g,f));local b=math.floor(interpolate(c1.b,c2.b,f));local a=math.floor(interpolate(c1.a,c2.a,f));r=math.max(0,math.min(255,r));g=math.max(0,math.min(255,g));b=math.max(0,math.min(255,b));a=math.max(0,math.min(255,a));return a*16777216+b*65536+g*256+r end
local function get_text_width(t,s)local ts=imgui.calc_text_size(t,false,s or stats_font_size);return ts.x+3 end 
local function get_real_text_size(t) local ts = imgui.calc_text_size(t); return ts.x, ts.y end
local function draw_text_safe(text, x, y, color, size) for offset = 1, shadow_layers do draw.text(text, x + offset, y + offset, shadow_color, size) end; draw.text(text, x, y, color, size) end

local detected_infos = { [0] = { name = "Waiting...", id = -1 }, [1] = { name = "Waiting...", id = -1 } }
-- Player info from shared hook (0_SharedHooks.lua)
re.on_frame(function()
    if _G._shared_player_info then
        for i = 0, 1 do
            local info = _G._shared_player_info[i]
            if info then
                detected_infos[i].name = info.name or "Waiting..."
                detected_infos[i].id = info.id or -1
            end
        end
    end
end)

local gBattle = nil
local function get_player_data(pi)
    local p = (pi == 0) and GS.p1 or GS.p2
    if not p then return end
    if gBattle==nil then gBattle=sdk.find_type_definition("gBattle")end
    if gBattle==nil then return end
    local BT=gBattle:get_field("Team"):get_data(nil)
    if BT==nil then return end
    local cT=BT.mcTeam
    if cT==nil or cT[pi]==nil then return end
    local t=cT[pi]
    local h=p.vital_new;local mh=p.heal_new;local d=p.focus_new;local su=t.mSuperGauge
    local wx,wy=nil,nil
    if p.pos and p.pos.x and p.pos.x.v and p.pos.y and p.pos.y.v then wx=p.pos.x.v/6553600;wy=p.pos.y.v/6553600 else return end
    local fr=false;if p.BitValue~=nil then fr=(bitand(p.BitValue,128)==128)end
    local ci=nil
    local cd=gBattle:get_field("Command"):get_data(nil)
    if cd and cd.StorageData and cd.StorageData.UserEngines and cd.StorageData.UserEngines[pi]then ci=cd.StorageData.UserEngines[pi].m_charge_infos end
    if h==nil or mh==nil or d==nil or su==nil then return end
    if mh<=0 then mh=10000 end
    local detected = detected_infos[pi] or { name="?", id=-1 }
    return { health=h, max_health=mh, drive=d, super=su, world_x=wx, world_y=wy, dir=fr, charge_infos=ci, real_name=detected.name, real_id=detected.id }
end

-- =========================================================
-- [4. CHARGE BARS DRAWING - UPDATED]
-- =========================================================
local function draw_dynamic_charge_bars(p_data, pi, display_w, display_h, y_offset)
    if p_data and p_data.charge_infos then
        if p_data.charge_infos:get_Count() <= 0 then return end
        
        -- Calculate dynamic dimensions
        local lay = get_layout()
        local bar_w = lay.charge_width * display_w
        local bar_h = lay.charge_height * display_h
        local spacing = 8 * (display_h / 1080)
        local base_y = y_offset + lay.charge_y_pos * display_h
        local meter_x = lay.charge_x_pos * display_w
        if pi == 1 then meter_x = display_w - (lay.charge_x_pos * display_w) - bar_w end

        local current_esf = p_data.real_name or "Unknown"
        if player_max_charges[pi].last_loaded_esf ~= current_esf then
            player_max_charges[pi] = { last_loaded_esf = current_esf }
            if saved_charge_db[current_esf] then
                for k, v in pairs(saved_charge_db[current_esf]) do
                    local num_k = tonumber(k); if num_k then player_max_charges[pi][num_k] = v else player_max_charges[pi][k] = v end
                end
            end
        end

        local charge_values = p_data.charge_infos:get_Values()
        if charge_values and charge_values._dictionary and charge_values._dictionary._entries then
            local entries = charge_values._dictionary._entries
            for j = 0, 1 do 
                if entries[j] and entries[j].value then
                    local cur = 0; local max_c = 0; local is_charging = false
                    local val = entries[j].value; cur = val.charge_frame or 0; max_c = val.keep_frame or 0
                    if cur > 0 then
                        is_charging = true
                        local known_max = player_max_charges[pi][j]
                        if not known_max or cur > known_max then
                            player_max_charges[pi][j] = cur; player_max_charges[pi][j .. "_is_learning"] = true
                            if not saved_charge_db[current_esf] then saved_charge_db[current_esf] = {} end
                            saved_charge_db[current_esf][tostring(j)] = cur; save_charge_db()
                        end
                    else
                        if player_max_charges[pi][j] and player_max_charges[pi][j] > 0 then player_max_charges[pi][j .. "_is_learning"] = false end
                    end
                    
                    local limit_val = player_max_charges[pi][j]; local ratio = 0; local can_show_ok = false
                    local is_learning = player_max_charges[pi][j .. "_is_learning"]; local limit_text = "??"
                    if limit_val and limit_val > 1 then
                        limit_text = tostring(limit_val); ratio = math.min(cur / limit_val, 1.0)
                        if ratio >= 1.0 and is_charging and not is_learning then can_show_ok = true end
                    end                    
                    
                    local fill_color = interpolate_color(colors.VisualChargeMeterFillStart, colors.VisualChargeMeterFillEnd, ratio)
                    if can_show_ok then fill_color = 0xFF00FFFF end
                    
                    local y_off = base_y + (j * (bar_h + spacing))
                    
                    draw.filled_rect(meter_x, y_off, bar_w, bar_h, colors.VisualChargeMeterBackground)
                    if ratio > 0 then
                        local filled_w = bar_w * ratio; local fill_x = meter_x
                        if pi == 1 then fill_x = meter_x + (bar_w - filled_w) end
                        draw.filled_rect(fill_x, y_off, filled_w, bar_h, fill_color)
                    end
                    draw.outline_rect(meter_x, y_off, bar_w, bar_h, colors.VisualChargeMeterOutline)
                    
                    local font_sz = math.floor(charge_meter_frame_font_size * (display_h / 1080))
                    local central_text = can_show_ok and "CHARGE OK" or string.format("%d/%s", cur, limit_text)
                    local t_w, t_h = get_real_text_size(central_text)
                    draw_text_safe(central_text, meter_x + (bar_w/2) - (t_w/2), (y_off + bar_h/2) - (t_h/2), colors.VisualChargeMeterText, font_sz)
                    
                    local buffer_text = string.format("(%d)", max_c)
                    local b_w, b_h = get_real_text_size(buffer_text)
                    local buffer_x = (pi == 0) and (meter_x + bar_w + 8) or (meter_x - b_w - 8)
                    draw_text_safe(buffer_text, buffer_x, (y_off + bar_h/2) - (b_h/2), 0xFFFFFFFF, font_sz)
                end 
            end
        end
    end
end

-- =========================================================
-- [5. BOXES DRAWING - CONFIGURABLE COLORS]
-- =========================================================
local function draw_thick_outline(x, y, w, h, col, t)
    t = t or 1.0
    if t <= 1.0 then draw.outline_rect(x, y, w, h, col); return end
    draw.filled_rect(x - t, y - t, w + t * 2, t, col) -- Top
    draw.filled_rect(x - t, y + h, w + t * 2, t, col) -- Bottom
    draw.filled_rect(x - t, y, t, h, col)             -- Left
    draw.filled_rect(x + w, y, t, h, col)             -- Right
end

local draw_boxes = function(w, aP, p1)
    -- Fix: Replaced standard Lua ternary (a and b or c) with inline if/else 
    -- to prevent 'false' evaluations from falling through to Player 2's settings.
    local dh;    if p1 then dh = display_p1_hitboxes else dh = display_p2_hitboxes end
    local dhu;   if p1 then dhu = display_p1_hurtboxes else dhu = display_p2_hurtboxes end
    local dpu;   if p1 then dpu = display_p1_pushboxes else dpu = display_p2_pushboxes end
    local dtb;   if p1 then dtb = display_p1_throwboxes else dtb = display_p2_throwboxes end
    local dthb;  if p1 then dthb = display_p1_throwhurtboxes else dthb = display_p2_throwhurtboxes end
    local dprb;  if p1 then dprb = display_p1_proximityboxes else dprb = display_p2_proximityboxes end
    local dub;   if p1 then dub = display_p1_uniqueboxes else dub = display_p2_uniqueboxes end
    local dprop; if p1 then dprop = display_p1_properties else dprop = display_p2_properties end
    local dcb;   if p1 then dcb = display_p1_clashbox else dcb = display_p2_clashbox end

    if aP == nil or aP.Collision == nil then return end
    local col = aP.Collision

    for j, r in pairs(col.Infos._items) do
        if r ~= nil then
            if not (r.OffsetX and r.OffsetX.v and r.OffsetY and r.OffsetY.v and r.SizeX and r.SizeX.v and r.SizeY and r.SizeY.v) then goto continue_rect_loop end

            local pX = r.OffsetX.v / 6553600; local pY = r.OffsetY.v / 6553600
            local sX = r.SizeX.v / 6553600 * 2; local sY = r.SizeY.v / 6553600 * 2
            pX = pX - sX / 2; pY = pY - sY / 2
            local acx = r.OffsetX.v / 6553600 - sX / 2; local acy = r.OffsetY.v / 6553600 - sY / 2

            v_tl.x = acx - sX / 2; v_tl.y = acy + sY / 2; v_tl.z = 0
            v_tr.x = acx + sX / 2; v_tr.y = acy + sY / 2; v_tr.z = 0
            v_bl.x = acx - sX / 2; v_bl.y = acy - sY / 2; v_bl.z = 0
            v_br.x = acx + sX / 2; v_br.y = acy - sY / 2; v_br.z = 0

            local sTL = draw.world_to_screen(v_tl); local sTR = draw.world_to_screen(v_tr)
            local sBL = draw.world_to_screen(v_bl); local sBR = draw.world_to_screen(v_br)

            if sTL and sTR and sBL and sBR then
                local fX = (sTL.x + sTR.x) / 2; local fY = (sBL.y + sTL.y) / 2
                local fSX = (sTR.x - sTL.x); local fSY = (sTL.y - sBL.y)

                if r:get_field("HitPos") ~= nil then
                    if r.TypeFlag > 0 and dh then
                        draw_thick_outline(fX, fY, fSX, fSY, box_col.hitbox, config.box_thicknesses.hitbox)
                        draw.filled_rect(fX, fY, fSX, fSY, box_col.hitbox_fill)
                        if dprop then
                            local he = "Can't Hit "; local co = "Combo "
                            if bitand(r.CondFlag, 16) == 16 then he = he .. "Std, " end
                            if bitand(r.CondFlag, 32) == 32 then he = he .. "Crch, " end
                            if bitand(r.CondFlag, 64) == 64 then he = he .. "Air, " end
                            if bitand(r.CondFlag, 256) == 256 then he = he .. "Fwd, " end
                            if bitand(r.CondFlag, 512) == 512 then he = he .. "Bwd, " end
                            if bitand(r.CondFlag, 262144) == 262144 then co = co .. "Only" end
                            if bitand(r.CondFlag, 524288) == 524288 then co = co .. "Only" end
                            local fs = ""; if string.len(he) > 10 then fs = fs .. string.sub(he, 0, -3) .. "\n" end
                            if string.len(co) > 6 then fs = fs .. co .. "\n" end
                            if string.len(fs) > 0 then draw.text(fs, fX, fY + fSY / 2 + 2, 0xFFFFFFFF, property_text_font_size) end
                        end
                    elseif ((r.TypeFlag == 0 and r.PoseBit > 0) or r.CondFlag == 0x2C0) and dtb then
                        draw_thick_outline(fX, fY, fSX, fSY, box_col.throwbox, config.box_thicknesses.throwbox)
                        draw.filled_rect(fX, fY, fSX, fSY, box_col.throwbox_fill)
                    elseif r.GuardBit == 0 and dcb then
                        draw_thick_outline(fX, fY, fSX, fSY, box_col.clash, config.box_thicknesses.clash)
                        draw.filled_rect(fX, fY, fSX, fSY, box_col.clash_fill)
                    elseif dprb then
                        draw_thick_outline(fX, fY, fSX, fSY, box_col.proximity, config.box_thicknesses.proximity)
                        draw.filled_rect(fX, fY, fSX, fSY, box_col.proximity_fill)
                    end
                elseif r:get_field("Attr") ~= nil then
                    if dpu then
                        draw_thick_outline(fX, fY, fSX, fSY, box_col.pushbox, config.box_thicknesses.pushbox)
                        draw.filled_rect(fX, fY, fSX, fSY, box_col.pushbox_fill)
                    end
                elseif r:get_field("HitNo") ~= nil then
                    if (r.TypeFlag or 0) > 0 then
                        if dhu then
                            if r.Type == 2 or r.Type == 1 then
                                draw_thick_outline(fX, fY, fSX, fSY, box_col.hurtbox_invuln, config.box_thicknesses.hurtbox_invuln)
                                draw.filled_rect(fX, fY, fSX, fSY, box_col.hurtbox_invuln_fill)
                            else
                                draw_thick_outline(fX, fY, fSX, fSY, box_col.hurtbox, config.box_thicknesses.hurtbox)
                                draw.filled_rect(fX, fY, fSX, fSY, box_col.hurtbox_fill)
                            end
                            if dprop then
                                local hi = ""; if r.TypeFlag == 1 then hi = hi .. "Proj" end; if r.TypeFlag == 2 then hi = hi .. "Strike" end
                                local hu = ""; if bitand(r.Immune, 1) == 1 then hu = hu .. "Std, " end
                                if bitand(r.Immune, 2) == 2 then hu = hu .. "Crch, " end
                                if bitand(r.Immune, 4) == 4 then hu = hu .. "Air, " end
                                if bitand(r.Immune, 64) == 64 then hu = hu .. "XUp, " end
                                if bitand(r.Immune, 128) == 128 then hu = hu .. "Rev, " end
                                local fs = ""; if string.len(hi) > 0 then fs = fs .. hi .. " Invuln\n" end
                                if string.len(hu) > 0 then fs = fs .. string.sub(hu, 0, -3) .. " Immune\n" end
                                if string.len(fs) > 0 then draw.text(fs, fX, fY + fSY / 2 + 2, 0xFFFFFFFF, property_text_font_size) end
                            end
                        end
                    elseif dthb then
                        draw_thick_outline(fX, fY, fSX, fSY, box_col.throwhurtbox, config.box_thicknesses.throwhurtbox)
                        draw.filled_rect(fX, fY, fSX, fSY, box_col.throwhurtbox_fill)
                    end
                elseif r:get_field("KeyData") ~= nil and dub then
                    draw_thick_outline(fX, fY, fSX, fSY, box_col.uniquebox, config.box_thicknesses.uniquebox)
                    draw.filled_rect(fX, fY, fSX, fSY, box_col.uniquebox_fill)
                elseif r:get_field("KeyData") == nil and dthb then
                    draw_thick_outline(fX, fY, fSX, fSY, box_col.throwhurtbox, config.box_thicknesses.throwhurtbox)
                    draw.filled_rect(fX, fY, fSX, fSY, box_col.throwhurtbox_fill)
                end
            end
        end
        ::continue_rect_loop::
    end
end


local hud_text_visible = true
local hud_p1_rect = { x = 0, y = 0, w = 0, h = 0 }
local hud_p2_rect = { x = 0, y = 0, w = 0, h = 0 }
local vr_visible = true
local vr_p1_rect = { x = 0, y = 0, w = 0, h = 0 }
local vr_p2_rect = { x = 0, y = 0, w = 0, h = 0 }
local boxes_visible = true
local arrow_rect = { x = 0, y = 0, w = 0, h = 0 }
local charge_visible = true
local charge_p1_rect = { x = 0, y = 0, w = 0, h = 0 }
local charge_p2_rect = { x = 0, y = 0, w = 0, h = 0 }
local click_flash_frames = 0

local function vr_get_vital_max(player_idx)
    local p = (player_idx == 0) and GS.p1 or GS.p2
    if not p then return nil end
    local v = p.vital_max
    if v and v > 0 then return v end
    return nil
end

-- =========================================================
-- [6. MAIN LOOP]
-- =========================================================
re.on_frame(function()
    try_load_font()
    if not GS.valid then return end
    if GS.in_pause_menu then return end
    if gBattle == nil then gBattle = sdk.find_type_definition("gBattle") end; if gBattle == nil then return end

    local p1_data = get_player_data(0)
    local p2_data = get_player_data(1)
    local display_size = imgui.get_display_size()
    if not display_size then return end
    local display_w = display_size.x
    local real_h = display_size.y
    local display_h = display_w * 9 / 16
    local y_offset = (real_h - display_h) / 2

    local hud_lay = get_layout()
    local base_y_hud = y_offset + hud_lay.hud_y_pos * display_h
    local col_green = 0xFF00FF00; local col_red = 0xFF0000FF; local col_white = 0xFFFFFFFF

    if p1_data then
        local p1_x_start = hud_lay.hud_x_padding * display_w
        local p1_dist = math.abs(p1_data.world_x)
        local p2_dist = p2_data and math.abs(p2_data.world_x) or 0
        local x_col = (p1_dist > p2_dist) and col_red or col_green

        local current_x = p1_x_start
        local full_txt = ""
        if display_p1_hud_pos then
            local p1_x_val = config.divide_distance_display and p1_data.world_x or (p1_data.world_x * 100.0)
            local x_txt = string.format("X: %.2f", p1_x_val)
            full_txt = x_txt
            if hud_text_visible then
                draw_text_with_outline(x_txt, current_x, base_y_hud, x_col)
            end
            local w_x, _ = get_text_size_custom(x_txt)
            current_x = current_x + w_x
        end

        local p1_parts = {}
        if display_p1_hud_hp then table.insert(p1_parts, string.format("HP: %d", p1_data.health)) end
        if display_p1_hud_dr then table.insert(p1_parts, string.format("DR: %.1f", p1_data.drive/10000)) end
        if display_p1_hud_sa then table.insert(p1_parts, string.format("SA: %.1f", p1_data.super/10000)) end

        if #p1_parts > 0 then
            local stats_txt = table.concat(p1_parts, " | ")
            if display_p1_hud_pos then stats_txt = " | " .. stats_txt end
            full_txt = full_txt .. stats_txt
            if hud_text_visible then
                draw_text_with_outline(stats_txt, current_x, base_y_hud, col_white)
            end
        end

        local total_w, total_h = get_text_size_custom(full_txt)
        hud_p1_rect.x = p1_x_start - 5
        hud_p1_rect.y = base_y_hud - 5
        hud_p1_rect.w = total_w + 10
        hud_p1_rect.h = total_h + 10
    end

    if p2_data then
        local p2_edge = display_w - (hud_lay.hud_x_padding * display_w)
        local p1_dist = p1_data and math.abs(p1_data.world_x) or 0
        local p2_dist = math.abs(p2_data.world_x)
        local x_col = (p2_dist > p1_dist) and col_red or col_green

        local p2_parts = {}
        if display_p2_hud_sa then table.insert(p2_parts, string.format("SA: %.1f", p2_data.super/10000)) end
        if display_p2_hud_dr then table.insert(p2_parts, string.format("DR: %.1f", p2_data.drive/10000)) end
        if display_p2_hud_hp then table.insert(p2_parts, string.format("HP: %d", p2_data.health)) end

        local stats_txt = table.concat(p2_parts, " | ")
        if #p2_parts > 0 and display_p2_hud_pos then stats_txt = stats_txt .. " | " end

        local w_stats, _ = get_text_size_custom(stats_txt)

        local w_x = 0
        local x_txt = ""
        if display_p2_hud_pos then
            local p2_x_val = config.divide_distance_display and p2_data.world_x or (p2_data.world_x * 100.0)
            x_txt = string.format("X: %.2f", p2_x_val)
            w_x, _ = get_text_size_custom(x_txt)
        end

        local pos_x = p2_edge - w_x
        if hud_text_visible then
            if display_p2_hud_pos then
                draw_text_with_outline(x_txt, pos_x, base_y_hud, x_col)
            end
            if #p2_parts > 0 then
                draw_text_with_outline(stats_txt, pos_x - w_stats, base_y_hud, col_white)
            end
        end

        local full_w = w_stats + w_x
        local _, total_h = get_text_size_custom("HP")
        hud_p2_rect.x = p2_edge - full_w - 5
        hud_p2_rect.y = base_y_hud - 5
        hud_p2_rect.w = full_w + 10
        hud_p2_rect.h = total_h + 10
    end

    -- 3. DISPLAY CHARGE METER (passing display_h here)
    if config.show_charge_bars then
        local charge_lay = get_layout()
        local bar_w = charge_lay.charge_width * display_w
        local bar_h = charge_lay.charge_height * display_h
        local spacing = 8 * (display_h / 1080)
        local total_h = 2 * bar_h + spacing
        local base_y = y_offset + charge_lay.charge_y_pos * display_h
        local p1_cx = charge_lay.charge_x_pos * display_w
        local p2_cx = display_w - charge_lay.charge_x_pos * display_w - bar_w
        charge_p1_rect.x = p1_cx - 5; charge_p1_rect.y = base_y - 5; charge_p1_rect.w = bar_w + 10; charge_p1_rect.h = total_h + 10
        charge_p2_rect.x = p2_cx - 5; charge_p2_rect.y = base_y - 5; charge_p2_rect.w = bar_w + 10; charge_p2_rect.h = total_h + 10

        if charge_visible then
            if p1_data and display_p1_charge_bars then draw_dynamic_charge_bars(p1_data, 0, display_w, display_h, y_offset) end
            if p2_data and display_p2_charge_bars then draw_dynamic_charge_bars(p2_data, 1, display_w, display_h, y_offset) end
        end
    end

    -- 4. DISPLAY BOXES & OTHERS...
    if boxes_visible then
        local sWork = gBattle:get_field("Work"):get_data(nil)
        if sWork and sWork.Global_work then
            for i, obj in pairs(sWork.Global_work) do
                if obj and obj.mpActParam and obj.pos and obj.pos.x and obj.pos.y then
                   local is_dying = false; local success, result = pcall(obj.get_IsR0Die, obj); if success then is_dying = result end
                   if not is_dying then
                       local actParam = obj.mpActParam
                       local is_team1 = false; local success_team, result_team = pcall(obj.get_IsTeam1P, obj); if success_team then is_team1 = result_team end
                       if is_team1 and not hide_p1_boxes then draw_boxes(obj, actParam, true);
                            v_pos.x = obj.pos.x.v / 6553600.0; v_pos.y = obj.pos.y.v / 6553600.0; v_pos.z = 0
                            local objPos = draw.world_to_screen(v_pos); if objPos and display_p1_position_dot then draw.filled_circle(objPos.x, objPos.y + config.arrow_y_offset, 5, 0xFFFFFF00, 10) end
                       elseif not is_team1 and not hide_p2_boxes then draw_boxes(obj, actParam, false);
                            v_pos.x = obj.pos.x.v / 6553600.0; v_pos.y = obj.pos.y.v / 6553600.0; v_pos.z = 0
                            local objPos = draw.world_to_screen(v_pos); if objPos and display_p2_position_dot then draw.filled_circle(objPos.x, objPos.y + config.arrow_y_offset, 5, 0xFF0000FF, 10) end end
                   end
                end
            end
        end
        local sPlayer = GS.sP
        if sPlayer and sPlayer.mcPlayer then
            for i, player in pairs(sPlayer.mcPlayer) do
                if player and player.mpActParam and player.pos and player.pos.x and player.pos.y then
                    if i == 0 and not hide_p1_boxes then draw_boxes(player, player.mpActParam, true);
                        v_pos.x = player.pos.x.v / 6553600.0; v_pos.y = player.pos.y.v / 6553600.0; v_pos.z = 0
                        local worldPos = draw.world_to_screen(v_pos); if worldPos and display_p1_position_dot then draw.filled_circle(worldPos.x, worldPos.y + config.arrow_y_offset, 10, 0xFFFFFFFF, 10) end
                    elseif i == 1 and not hide_p2_boxes then draw_boxes(player, player.mpActParam, false);
                        v_pos.x = player.pos.x.v / 6553600.0; v_pos.y = player.pos.y.v / 6553600.0; v_pos.z = 0
                        local worldPos = draw.world_to_screen(v_pos); if worldPos and display_p2_position_dot then draw.filled_circle(worldPos.x, worldPos.y + config.arrow_y_offset, 10, 0xFFFFFFFF, 10) end end
                end
            end
        end
    end

    if config.show_distance_arrow and p1_data and p2_data then
        v_p1.x = p1_data.world_x; v_p1.y = p1_data.world_y; v_p1.z = 0
        v_p2.x = p2_data.world_x; v_p2.y = p2_data.world_y; v_p2.z = 0
        local p1s = draw.world_to_screen(v_p1); local p2s = draw.world_to_screen(v_p2)
        if p1s and p2s then
            p1s.y = p1s.y + config.arrow_y_offset
            p2s.y = p2s.y + config.arrow_y_offset

            local ht = config.arrow_thickness / 2.0
            local ax_min = math.min(p1s.x, p2s.x) - ht - 5
            local ax_max = math.max(p1s.x, p2s.x) + ht + 5
            local ay_min = math.min(p1s.y, p2s.y) - ht - 5
            local ay_max = math.max(p1s.y, p2s.y) + ht + 5
            arrow_rect.x = ax_min; arrow_rect.y = ay_min; arrow_rect.w = ax_max - ax_min; arrow_rect.h = ay_max - ay_min

            if boxes_visible then
                local dist = math.abs(p2_data.world_x - p1_data.world_x)
                local dx = p2s.x - p1s.x; local dy = p2s.y - p1s.y; local len = math.sqrt(dx*dx + dy*dy)
                local base_col; local grad = 0
                if dist <= gradient_end_dist then base_col = arrow_color_close elseif dist > gradient_sharp_start then base_col = arrow_color_far
                else grad = (dist - gradient_end_dist) / (gradient_sharp_start - gradient_end_dist); base_col = { r=math.floor(interpolate(arrow_color_close.r, arrow_color_far.r, grad)), g=math.floor(interpolate(arrow_color_close.g, arrow_color_far.g, grad)), b=math.floor(interpolate(arrow_color_close.b, arrow_color_far.b, grad)), a=math.floor(interpolate(arrow_color_close.a, arrow_color_far.a, grad)) } end
                local fade = 0; if math.abs(dx)>0.01 then local ar=math.abs(dy)/math.abs(dx); if ar>=fade_full_angle_ratio then fade=1.0 elseif ar>fade_start_angle_ratio then fade=(ar-fade_start_angle_ratio)/(fade_full_angle_ratio-fade_start_angle_ratio) end elseif math.abs(dy)>0.01 then fade=1.0 end
                local final_col = interpolate_color(base_col or arrow_col_grey, arrow_col_grey, fade)

                if len > 0.1 then
                    local nx = dx/len; local ny = dy/len; local px = -ny; local py = nx
                    draw.filled_quad(p1s.x+px*ht, p1s.y+py*ht, p2s.x+px*ht, p2s.y+py*ht, p2s.x-px*ht, p2s.y-py*ht, p1s.x-px*ht, p1s.y-py*ht, final_col)
                end
                local dist_val = config.divide_distance_display and dist or (dist * 100.0)
                local d_txt = string.format("%.2f", dist_val); local mx=(p1s.x+p2s.x)/2; local my=(p1s.y+p2s.y)/2
                local dtw = get_text_width(d_txt, distance_font_size); local dtx=mx-(dtw/2); local dty=my - (distance_font_size / 2.5)
                for o=1,3 do draw.text(d_txt, dtx+o, dty+o, 0x80000000, distance_font_size) end; draw.text(d_txt, dtx, dty, distance_text_color, distance_font_size)
            end
        end
    end
    if vr_get_active().enabled then
        local vr = vr_get_active()
        local line_w = vr.width * display_w
        local y_line = y_offset + vr.pos_y * display_h
        local tick_len_px = vr.tick_len * display_h
        local angle_rad_p1 = math.rad(vr.tick_angle)
        local angle_rad_p2 = math.rad(vr.tick_angle) * -1
        local dx_p1 = math.sin(angle_rad_p1) * tick_len_px
        local dx_p2 = math.sin(angle_rad_p2) * tick_len_px
        local dy_tick = -math.cos(angle_rad_p1) * tick_len_px
        local y_top = y_line + math.min(0, dy_tick)
        local label_bot = y_line + vr.label_off_y * display_h + vr.font_size * display_h
        local y_bot = math.max(y_line, label_bot)
        local p1_x = vr.pos_x * display_w
        local p2_x = display_w - vr.pos_x * display_w - line_w
        local p1_left = p1_x + math.min(0, dx_p1)
        local p1_right = p1_x + line_w + math.max(0, dx_p1)
        local p2_left = p2_x + math.min(0, dx_p2)
        local p2_right = p2_x + line_w + math.max(0, dx_p2)
        vr_p1_rect.x = p1_left - 5; vr_p1_rect.y = y_top - 5; vr_p1_rect.w = p1_right - p1_left + 10; vr_p1_rect.h = y_bot - y_top + 10
        vr_p2_rect.x = p2_left - 5; vr_p2_rect.y = y_top - 5; vr_p2_rect.w = p2_right - p2_left + 10; vr_p2_rect.h = y_bot - y_top + 10
    end

    if imgui.is_mouse_clicked(0) then
        local m = imgui.get_mouse()
        if m then
            local function pt_in(r)
                return r.w > 0 and m.x >= r.x and m.x <= r.x + r.w and m.y >= r.y and m.y <= r.y + r.h
            end

            local clicked_any = false

            if vr_get_active().enabled and (pt_in(vr_p1_rect) or pt_in(vr_p2_rect)) then
                vr_visible = not vr_visible
                clicked_any = true
            end

            if pt_in(hud_p1_rect) or pt_in(hud_p2_rect) then
                hud_text_visible = not hud_text_visible
                clicked_any = true
            end

            if pt_in(arrow_rect) then
                boxes_visible = not boxes_visible
                clicked_any = true
            end

            if pt_in(charge_p1_rect) or pt_in(charge_p2_rect) then
                charge_visible = not charge_visible
                clicked_any = true
            end

            if clicked_any then click_flash_frames = 10 end
        end
    end

    -- Push ruler data (D2D reads it — clears when stale)
    if vr_get_active().enabled and vr_visible then
        local p1_max = vr_get_vital_max(0)
        local p2_max = vr_get_vital_max(1)
        if p1_max or p2_max then
            _G._vr_queue = { p1_max = p1_max, p2_max = p2_max }
        else
            _G._vr_queue = nil
        end
    else
        _G._vr_queue = nil
    end

    -- Web bridge: export state & poll changes
    if not _G._sb_web_counter then _G._sb_web_counter = 0 end
    _G._sb_web_counter = _G._sb_web_counter + 1
    if _G._sb_web_counter >= 60 then
        _G._sb_web_counter = 0
        pcall(json.dump_file, "SF6_TrainingRemoteControl_data/SheldonsBoxes_WebState.json", {
            vr_visible = vr_visible,
            hud_text_visible = hud_text_visible,
            boxes_visible = boxes_visible,
            charge_visible = charge_visible,
            p1 = {
                hitboxes = display_p1_hitboxes, hurtboxes = display_p1_hurtboxes,
                pushboxes = display_p1_pushboxes, throwboxes = display_p1_throwboxes,
                throwhurtboxes = display_p1_throwhurtboxes, proximityboxes = display_p1_proximityboxes,
                uniqueboxes = display_p1_uniqueboxes, clashbox = display_p1_clashbox,
                properties = display_p1_properties, position_dot = display_p1_position_dot,
                charge_bars = display_p1_charge_bars, hide_all = hide_p1_boxes,
                hud_pos = display_p1_hud_pos, hud_hp = display_p1_hud_hp,
                hud_dr = display_p1_hud_dr, hud_sa = display_p1_hud_sa,
            },
            p2 = {
                hitboxes = display_p2_hitboxes, hurtboxes = display_p2_hurtboxes,
                pushboxes = display_p2_pushboxes, throwboxes = display_p2_throwboxes,
                throwhurtboxes = display_p2_throwhurtboxes, proximityboxes = display_p2_proximityboxes,
                uniqueboxes = display_p2_uniqueboxes, clashbox = display_p2_clashbox,
                properties = display_p2_properties, position_dot = display_p2_position_dot,
                charge_bars = display_p2_charge_bars, hide_all = hide_p2_boxes,
                hud_pos = display_p2_hud_pos, hud_hp = display_p2_hud_hp,
                hud_dr = display_p2_hud_dr, hud_sa = display_p2_hud_sa,
            },
        })
    end
    -- Poll incoming changes (skip stale bridge data on first load)
    if not _G._sb_bridge_ts then
        local ok_init, b_init = pcall(json.load_file, "SF6_TrainingRemoteControl_data/SheldonsBoxes_WebBridge.json")
        _G._sb_bridge_ts = (ok_init and b_init and b_init._web_timestamp) or 0
    end
    if _G._sb_web_counter == 0 then
        local ok, b = pcall(json.load_file, "SF6_TrainingRemoteControl_data/SheldonsBoxes_WebBridge.json")
        if ok and b then
            local ts = b._web_timestamp or 0
            if ts > _G._sb_bridge_ts then
                _G._sb_bridge_ts = ts
                if b.vr_visible ~= nil then vr_visible = b.vr_visible end
                if b.hud_text_visible ~= nil then hud_text_visible = b.hud_text_visible end
                if b.boxes_visible ~= nil then boxes_visible = b.boxes_visible end
                if b.charge_visible ~= nil then charge_visible = b.charge_visible end
                if b.p1 then
                    if b.p1.hitboxes ~= nil then display_p1_hitboxes = b.p1.hitboxes end
                    if b.p1.hurtboxes ~= nil then display_p1_hurtboxes = b.p1.hurtboxes end
                    if b.p1.pushboxes ~= nil then display_p1_pushboxes = b.p1.pushboxes end
                    if b.p1.throwboxes ~= nil then display_p1_throwboxes = b.p1.throwboxes end
                    if b.p1.throwhurtboxes ~= nil then display_p1_throwhurtboxes = b.p1.throwhurtboxes end
                    if b.p1.proximityboxes ~= nil then display_p1_proximityboxes = b.p1.proximityboxes end
                    if b.p1.uniqueboxes ~= nil then display_p1_uniqueboxes = b.p1.uniqueboxes end
                    if b.p1.clashbox ~= nil then display_p1_clashbox = b.p1.clashbox end
                    if b.p1.properties ~= nil then display_p1_properties = b.p1.properties end
                    if b.p1.position_dot ~= nil then display_p1_position_dot = b.p1.position_dot end
                    if b.p1.charge_bars ~= nil then display_p1_charge_bars = b.p1.charge_bars end
                    if b.p1.hide_all ~= nil then hide_p1_boxes = b.p1.hide_all end
                    if b.p1.hud_pos ~= nil then display_p1_hud_pos = b.p1.hud_pos end
                    if b.p1.hud_hp ~= nil then display_p1_hud_hp = b.p1.hud_hp end
                    if b.p1.hud_dr ~= nil then display_p1_hud_dr = b.p1.hud_dr end
                    if b.p1.hud_sa ~= nil then display_p1_hud_sa = b.p1.hud_sa end
                end
                if b.p2 then
                    if b.p2.hitboxes ~= nil then display_p2_hitboxes = b.p2.hitboxes end
                    if b.p2.hurtboxes ~= nil then display_p2_hurtboxes = b.p2.hurtboxes end
                    if b.p2.pushboxes ~= nil then display_p2_pushboxes = b.p2.pushboxes end
                    if b.p2.throwboxes ~= nil then display_p2_throwboxes = b.p2.throwboxes end
                    if b.p2.throwhurtboxes ~= nil then display_p2_throwhurtboxes = b.p2.throwhurtboxes end
                    if b.p2.proximityboxes ~= nil then display_p2_proximityboxes = b.p2.proximityboxes end
                    if b.p2.uniqueboxes ~= nil then display_p2_uniqueboxes = b.p2.uniqueboxes end
                    if b.p2.clashbox ~= nil then display_p2_clashbox = b.p2.clashbox end
                    if b.p2.properties ~= nil then display_p2_properties = b.p2.properties end
                    if b.p2.position_dot ~= nil then display_p2_position_dot = b.p2.position_dot end
                    if b.p2.charge_bars ~= nil then display_p2_charge_bars = b.p2.charge_bars end
                    if b.p2.hide_all ~= nil then hide_p2_boxes = b.p2.hide_all end
                    if b.p2.hud_pos ~= nil then display_p2_hud_pos = b.p2.hud_pos end
                    if b.p2.hud_hp ~= nil then display_p2_hud_hp = b.p2.hud_hp end
                    if b.p2.hud_dr ~= nil then display_p2_hud_dr = b.p2.hud_dr end
                    if b.p2.hud_sa ~= nil then display_p2_hud_sa = b.p2.hud_sa end
                end
            end
        end
    end

end)

-- =========================================================
-- [VITAL RULER - D2D OVERLAY]
-- =========================================================
local vr_font = nil
local vr_font_px = 0

local function vr_draw_line(x1, y1, x2, y2, thickness, color)
    local dx = x2 - x1
    local dy = y2 - y1
    local steps = math.max(math.abs(dx), math.abs(dy), 1)
    local sx = dx / steps
    local sy = dy / steps
    local t = thickness or 2
    local half = t * 0.5
    for i = 0, math.floor(steps) do
        d2d.fill_rect(x1 + sx * i - half, y1 + sy * i - half, t, t, color)
    end
end


local function vr_format_hp(val)
    if vr_get_active().label_compact then
        if val >= 1000 then
            if val % 1000 == 0 then return string.format("%dK", val / 1000) end
            return string.format("%.1fK", val / 1000)
        end
        return tostring(val)
    end
    return tostring(val)
end

local function vr_hp_to_x(hp_val, vital_max, x_start, line_w, mirror)
    if mirror then return x_start + (hp_val / vital_max) * line_w end
    return x_start + (1 - hp_val / vital_max) * line_w
end

local function vr_hp_to_xy(hp_val, vital_max, x_start, line_w, y_line, mirror, vr)
    if not vr.use_segments then
        local x = vr_hp_to_x(hp_val, vital_max, x_start, line_w, mirror)
        return x, y_line
    end
    local t = mirror and (hp_val / vital_max) or (1 - hp_val / vital_max)
    local s1 = vr.seg1_pct or 0.3
    local s2 = vr.seg2_pct or 0.4
    local s3 = 1 - s1 - s2
    local seg2_rad = math.rad(vr.seg2_angle or 0)
    local seg2_dy = math.sin(seg2_rad) * s2 * line_w
    if mirror then
        if t <= s3 then
            return x_start + t * line_w, y_line + seg2_dy
        elseif t <= s3 + s2 then
            local frac = (t - s3) / s2
            return x_start + t * line_w, y_line + seg2_dy * (1 - frac)
        else
            return x_start + t * line_w, y_line
        end
    else
        if t <= s1 then
            return x_start + t * line_w, y_line
        elseif t <= s1 + s2 then
            local frac = (t - s1) / s2
            return x_start + t * line_w, y_line + frac * seg2_dy
        else
            return x_start + t * line_w, y_line + seg2_dy
        end
    end
end

local function vr_draw_ruler(sw, sh, vital_max, x_start, line_w, mirror, y_off)
    local vr = vr_get_active()
    local y_line = (y_off or 0) + vr.pos_y * sh

    local tick_len_px  = vr.tick_len * sh
    local half_len_px  = tick_len_px * 0.5
    local tenth_len_px = tick_len_px * 0.1
    local angle_sign   = mirror and -1 or 1
    local angle_rad    = math.rad(vr.tick_angle) * angle_sign

    local off_x_px = vr.label_off_x * sw
    local off_y_px = vr.label_off_y * sh

    if vr.use_segments then
        local s1 = vr.seg1_pct or 0.3
        local s2 = vr.seg2_pct or 0.4
        local s3 = 1 - s1 - s2
        local seg2_rad = math.rad(vr.seg2_angle or 0)
        local seg2_dy = math.sin(seg2_rad) * s2 * line_w
        local ht = vr.line_thick * 0.5
        if mirror then
            local x1 = x_start
            local x2 = x_start + s3 * line_w
            local x3 = x_start + (s3 + s2) * line_w
            local x4 = x_start + line_w
            d2d.fill_rect(x1, y_line + seg2_dy - ht, x2 - x1, vr.line_thick, vr.col_line)
            vr_draw_line(x2, y_line + seg2_dy, x3, y_line, vr.line_thick, vr.col_line)
            d2d.fill_rect(x3, y_line - ht, x4 - x3, vr.line_thick, vr.col_line)
        else
            local x1 = x_start
            local x2 = x_start + s1 * line_w
            local x3 = x_start + (s1 + s2) * line_w
            local x4 = x_start + line_w
            d2d.fill_rect(x1, y_line - ht, x2 - x1, vr.line_thick, vr.col_line)
            vr_draw_line(x2, y_line, x3, y_line + seg2_dy, vr.line_thick, vr.col_line)
            d2d.fill_rect(x3, y_line + seg2_dy - ht, x4 - x3, vr.line_thick, vr.col_line)
        end
    else
        d2d.fill_rect(x_start, y_line - vr.line_thick * 0.5, line_w, vr.line_thick, vr.col_line)
    end

    local function draw_tick_at(hp, len)
        local tx, ty = vr_hp_to_xy(hp, vital_max, x_start, line_w, y_line, mirror, vr)
        local dx_t = math.sin(angle_rad) * len
        local dy_t = -math.cos(angle_rad) * len
        vr_draw_line(tx, ty, tx + dx_t, ty + dy_t, vr.tick_thick, vr.col_tick)
        return tx, ty
    end

    if vr.show_tenth then
        for hp = 100, vital_max, 100 do
            if hp % 500 ~= 0 then draw_tick_at(hp, tenth_len_px) end
        end
    end

    if vr.show_half then
        for hp = 500, vital_max, 500 do
            if hp % 1000 ~= 0 then draw_tick_at(hp, half_len_px) end
        end
    end

    for hp = 0, vital_max, 1000 do
        local tx, ty = draw_tick_at(hp, tick_len_px)
        if vr.show_labels and vr_font then
            local label = vr_format_hp(hp)
            local lw, lh = vr_font:measure(label)
            local lx = tx - lw * 0.5 + off_x_px
            local ly = ty + off_y_px
            d2d.text(vr_font, label, lx + 1, ly + 1, 0xFF000000)
            d2d.text(vr_font, label, lx, ly, vr.col_label)
        end
    end

    if vital_max % 1000 ~= 0 then
        local tx, ty = draw_tick_at(vital_max, (vital_max % 500 == 0) and half_len_px or tenth_len_px)
        if vr.show_labels and vr_font then
            local label = vr_format_hp(vital_max)
            local lw, lh = vr_font:measure(label)
            local lx = tx - lw * 0.5 + off_x_px
            local ly = ty + off_y_px
            d2d.text(vr_font, label, lx + 1, ly + 1, 0xFF000000)
            d2d.text(vr_font, label, lx, ly, vr.col_label)
        end
    end
end

if d2d and d2d.register then
    d2d.register(function() end, function()
        -- Consume queue (pushed by re.on_frame — stops when script is disabled)
        local vr_data = _G._vr_queue
        _G._vr_queue = nil

        -- Flash zones (also driven by re.on_frame click detection)
        local show_zones = click_flash_frames > 0
        if show_zones then
            local function draw_zone(r, fill_col, outline_col)
                if r.w > 0 then
                    d2d.fill_rect(r.x, r.y, r.w, r.h, fill_col)
                    d2d.outline_rect(r.x, r.y, r.w, r.h, 2, outline_col)
                end
            end
            draw_zone(vr_p1_rect, 0x80FF0000, 0xFFFF0000)
            draw_zone(vr_p2_rect, 0x800000FF, 0xFF0000FF)
            draw_zone(hud_p1_rect, 0x80FF8800, 0xFFFF8800)
            draw_zone(hud_p2_rect, 0x8800FF88, 0xFF00FF88)
            draw_zone(arrow_rect, 0x80FFFF00, 0xFFFFFF00)
            draw_zone(charge_p1_rect, 0x80FF00FF, 0xFFFF00FF)
            draw_zone(charge_p2_rect, 0x80FF00FF, 0xFFFF00FF)
            if click_flash_frames > 0 then click_flash_frames = click_flash_frames - 1 end
        end

        if not vr_data then return end

        local sw, real_sh = d2d.surface_size()
        local sh = sw * 9 / 16
        local d2d_y_offset = (real_sh - sh) / 2
        local vr = vr_get_active()
        local line_w = vr.width * sw

        local font_px = math.floor(vr.font_size * sh)
        if font_px < 8 then font_px = 8 end
        if not vr_font or math.abs(vr_font_px - font_px) > 1 then
            vr_font = d2d.Font.new("capcom_goji-udkakugoc80pro-db.ttf", font_px)
            vr_font_px = font_px
        end

        local p1_x = vr.pos_x * sw
        local p2_x = sw - vr.pos_x * sw - line_w
        if vr_data.p1_max then
            vr_draw_ruler(sw, sh, vr_data.p1_max, p1_x, line_w, false, d2d_y_offset)
        end
        if vr_data.p2_max then
            vr_draw_ruler(sw, sh, vr_data.p2_max, p2_x, line_w, true, d2d_y_offset)
        end
    end)
end

-- =========================================================
-- [UI RENDERING - STYLED + COLOR EDITOR]
-- =========================================================

-- Helper: draw one color picker row with independent fill alpha
local function draw_color_picker(label, config_key)
    if imgui.tree_node(label .. "##tn_" .. config_key) then
        local cur_col = config.box_colors[config_key] or 0xFFFFFFFF
        local cur_fill = config.box_fill_alphas[config_key] or config.fill_alpha or 77
        local cur_thick = config.box_thicknesses[config_key] or 1.0
        
        local changed1, new_col = imgui.color_edit_argb("Bordure (Color)##cp_" .. config_key, cur_col)
        local changed2, new_fill = imgui.drag_int("Fond (Alpha)##fa_" .. config_key, cur_fill, 1, 0, 255)
        local changed3, new_thick = imgui.drag_float("Épaisseur (Outline)##th_" .. config_key, cur_thick, 0.1, 1.0, 20.0, "%.1f")
        
        if changed1 or changed2 or changed3 then
            if changed1 then config.box_colors[config_key] = new_col end
            if changed2 then config.box_fill_alphas[config_key] = new_fill end
            if changed3 then config.box_thicknesses[config_key] = new_thick end
            update_box_colors()
            save_config()
        end
        imgui.tree_pop()
    end
end
local function save_display_config()
    config.display = {
        p1_hitboxes = display_p1_hitboxes, p1_hurtboxes = display_p1_hurtboxes,
        p1_pushboxes = display_p1_pushboxes, p1_throwboxes = display_p1_throwboxes,
        p1_throwhurtboxes = display_p1_throwhurtboxes, p1_proximityboxes = display_p1_proximityboxes,
        p1_uniqueboxes = display_p1_uniqueboxes, p1_properties = display_p1_properties,
        p1_position_dot = display_p1_position_dot, p1_clashbox = display_p1_clashbox,
        p1_charge_bars = display_p1_charge_bars, hide_p1 = hide_p1_boxes,
        p2_hitboxes = display_p2_hitboxes, p2_hurtboxes = display_p2_hurtboxes,
        p2_pushboxes = display_p2_pushboxes, p2_throwboxes = display_p2_throwboxes,
        p2_throwhurtboxes = display_p2_throwhurtboxes, p2_proximityboxes = display_p2_proximityboxes,
        p2_uniqueboxes = display_p2_uniqueboxes, p2_properties = display_p2_properties,
        p2_position_dot = display_p2_position_dot, p2_clashbox = display_p2_clashbox,
        p2_charge_bars = display_p2_charge_bars, hide_p2 = hide_p2_boxes,
        p1_hud_pos = display_p1_hud_pos, p1_hud_hp = display_p1_hud_hp,
        p1_hud_dr = display_p1_hud_dr, p1_hud_sa = display_p1_hud_sa,
        p2_hud_pos = display_p2_hud_pos, p2_hud_hp = display_p2_hud_hp,
        p2_hud_dr = display_p2_hud_dr, p2_hud_sa = display_p2_hud_sa,
    }
    save_config()
end

re.on_draw_ui(function()
    if imgui.tree_node("SHELDON'S BOXES") then

        imgui.push_style_color(21, 0xFF005500)
        imgui.push_style_color(22, 0xFF007700)
        imgui.push_style_color(23, 0xFF009900)
        if imgui.button("SAVE DISPLAY CONFIG") then
            save_display_config()
        end
        imgui.pop_style_color(3)
        imgui.separator()

        -- ==========================================
        -- 1. GLOBAL : HUD & FONT
        -- ==========================================
        if styled_header("--- GLOBAL : HUD & FONT ---", UI_THEME.hdr_rules) then
            local c = false
            local cf, nf = imgui.input_text("Font File (.ttf)", config.font_filename); if cf then config.font_filename = nf; c = true end
            local cs, ns = imgui.drag_int("Font Size", config.font_base_size, 1, 10, 120); if cs then config.font_base_size = ns; c = true end
            local ct, nt = imgui.drag_float("Outline Thickness", config.outline_thickness, 0.1, 1.0, 10.0, "%.1f"); if ct then config.outline_thickness = nt; c = true end
            imgui.separator()
            local cd, nd = imgui.checkbox("Divide Distance/Pos by 100", config.divide_distance_display); if cd then config.divide_distance_display = nd; c = true end
            imgui.separator()
            if c then save_config() end
		end
        -- ==========================================
        -- 1b. HUD TEXT POSITION (per HUD type)
        -- ==========================================
        if styled_header("--- HUD TEXT POSITION ---", UI_THEME.hdr_rules) then
            local suffix = hud_suffix()
            local hud_name = HUD_NAMES[suffix] or suffix
            imgui.text_colored("Active HUD: " .. hud_name .. " [" .. suffix .. "]", 0xFF00FFFF)
            local lay = get_layout()
            local c = false
            local cx, nx = imgui.drag_float("Text Padding X (P1)##hud", lay.hud_x_padding, 0.001, 0.0, 0.5, "%.3f"); if cx then lay.hud_x_padding = nx; c = true end
            local cy, ny = imgui.drag_float("Text Position Y##hud", lay.hud_y_pos, 0.001, 0.0, 1.0, "%.3f"); if cy then lay.hud_y_pos = ny; c = true end
            if c then save_config() end
		end
        if styled_header("--- DISTANCE ARROW ---", UI_THEME.hdr_info) then
            local changed_arrow; changed_arrow, config.show_distance_arrow = imgui.checkbox("Show Distance Arrow", config.show_distance_arrow); if changed_arrow then c = true end
            if config.show_distance_arrow then
                local cay, nay = imgui.drag_float("Arrow Y Offset", config.arrow_y_offset, 1.0, -800.0, 800.0, "%.1f")
                if cay then config.arrow_y_offset = nay; c = true end
                local cat, nat = imgui.drag_float("Arrow Thickness", config.arrow_thickness, 0.5, 1.0, 200.0, "%.1f")
                if cat then config.arrow_thickness = nat; c = true end
            end
			            if c then save_config() end
		end

        -- ==========================================
        -- 2. CHARGE BARS
        -- ==========================================
        if styled_header("--- CHARGE BARS ---", UI_THEME.hdr_info) then
            local suffix = hud_suffix()
            local hud_name = HUD_NAMES[suffix] or suffix
            imgui.text_colored("Active HUD: " .. hud_name .. " [" .. suffix .. "]", 0xFF00FFFF)
            local lay = get_layout()
            local c = false
            local changed_cb; changed_cb, config.show_charge_bars = imgui.checkbox("Show Charge Bars", config.show_charge_bars); if changed_cb then c = true end
            local bx, nx = imgui.drag_float("Bars X Pos##cb", lay.charge_x_pos, 0.001, 0.0, 1.0, "%.3f"); if bx then lay.charge_x_pos = nx; c = true end
            local by, ny = imgui.drag_float("Bars Y Pos##cb", lay.charge_y_pos, 0.001, 0.0, 1.0, "%.3f"); if by then lay.charge_y_pos = ny; c = true end
            imgui.separator()
            local bw, nw = imgui.drag_float("Bars Width##cb", lay.charge_width, 0.001, 0.01, 0.5, "%.3f"); if bw then lay.charge_width = nw; c = true end
            local bh, nh = imgui.drag_float("Bars Height##cb", lay.charge_height, 0.001, 0.005, 0.2, "%.3f"); if bh then lay.charge_height = nh; c = true end
            if c then save_config() end
        end

        -- ==========================================
        -- 3. BOX COLORS
        -- ==========================================
        if styled_header("--- BOX COLORS ---", UI_THEME.hdr_info) then
            imgui.text_colored("Expand to configure Border + Background", COL_GREY)
            imgui.separator()

            imgui.text_colored(">> Attack Boxes", COL_YELLOW)
            draw_color_picker("Hitbox",           "hitbox")
            draw_color_picker("Throw Box",        "throwbox")
            draw_color_picker("Projectile Clash", "clash")
            draw_color_picker("Proximity",        "proximity")

            imgui.separator()
            imgui.text_colored(">> Defense Boxes", COL_YELLOW)
            draw_color_picker("Hurtbox",           "hurtbox")
            draw_color_picker("Hurtbox (Invuln)",  "hurtbox_invuln")
            draw_color_picker("Throw Hurtbox",     "throwhurtbox")

            imgui.separator()
            imgui.text_colored(">> Other Boxes", COL_YELLOW)
            draw_color_picker("Pushbox",           "pushbox")
            draw_color_picker("Unique Box",        "uniquebox")

            imgui.separator()
            if imgui.button("Reset to Defaults##boxcol") then
                config.box_colors = {
                    hitbox = 0xFFC04000, throwbox = 0xFFFF80D0, clash = 0xFFE69138,
                    proximity = 0xFF5B5B5B, pushbox = 0xFFFFFF00, hurtbox = 0xFF00FF00,
                    hurtbox_invuln = 0xFF8000FF, uniquebox = 0xFF00FFEE, throwhurtbox = 0xFF0000FF,
                }
                config.box_fill_alphas = {
                    hitbox = 77, throwbox = 77, clash = 64, proximity = 64,
                    pushbox = 64, hurtbox = 64, hurtbox_invuln = 64,
                    uniquebox = 77, throwhurtbox = 77
                }
                config.fill_alpha = 77
                update_box_colors()
                save_config()
            end
        end

        -- ==========================================
        -- 4. VITAL RULER
        -- ==========================================
        if styled_header("--- VITAL RULER ---", UI_THEME.hdr_info) then
            local suffix = hud_suffix()
            local hud_name = HUD_NAMES[suffix] or suffix
            imgui.text_colored("Active HUD: " .. hud_name .. " [" .. suffix .. "]", 0xFF00FFFF)
            local c = false
            local vr = vr_get_active()
            local ch
            ch, vr.enabled = imgui.checkbox("Enabled##vr", vr.enabled); if ch then c = true end
            ch, vr.pos_x = imgui.drag_float("X position##vr", vr.pos_x, 0.001, 0.0, 1.0, "%.3f"); if ch then c = true end
            ch, vr.pos_y = imgui.drag_float("Y position##vr", vr.pos_y, 0.001, 0.0, 1.0, "%.3f"); if ch then c = true end
            ch, vr.width = imgui.drag_float("Width##vr", vr.width, 0.001, 0.0, 1.0, "%.3f"); if ch then c = true end
            ch, vr.tick_len = imgui.drag_float("Tick length##vr", vr.tick_len, 0.001, 0.0, 0.2, "%.3f"); if ch then c = true end
            ch, vr.tick_angle = imgui.drag_float("Tick angle##vr", vr.tick_angle, 0.5, -90.0, 90.0, "%.1f"); if ch then c = true end
            ch, vr.line_thick = imgui.drag_float("Line thickness##vr", vr.line_thick, 0.5, 1.0, 10.0, "%.1f"); if ch then c = true end
            ch, vr.tick_thick = imgui.drag_float("Tick thickness##vr", vr.tick_thick, 0.5, 1.0, 10.0, "%.1f"); if ch then c = true end
            ch, vr.show_half = imgui.checkbox("Show 500 ticks##vr", vr.show_half); if ch then c = true end
            ch, vr.show_tenth = imgui.checkbox("Show 100 ticks##vr", vr.show_tenth); if ch then c = true end
            ch, vr.show_labels = imgui.checkbox("Show HP labels##vr", vr.show_labels); if ch then c = true end
            ch, vr.label_compact = imgui.checkbox("Compact labels (K)##vr", vr.label_compact); if ch then c = true end
            ch, vr.label_off_x = imgui.drag_float("Label offset X##vr", vr.label_off_x, 0.001, -0.1, 0.1, "%.3f"); if ch then c = true end
            ch, vr.label_off_y = imgui.drag_float("Label offset Y##vr", vr.label_off_y, 0.001, -0.1, 0.1, "%.3f"); if ch then c = true end
            ch, vr.font_size = imgui.drag_float("Font size##vr", vr.font_size, 0.001, 0.005, 0.05, "%.3f"); if ch then c = true end
            local col_ch, new_col = imgui.color_edit_argb("Ruler Color##vr", vr.col_line)
            if col_ch then
                vr.col_line = new_col
                vr.col_tick = new_col
                vr.col_label = new_col
                c = true
            end
            imgui.separator()
            ch, vr.use_segments = imgui.checkbox("3-Segment Mode##vr", vr.use_segments or false); if ch then c = true end
            if vr.use_segments then
                ch, vr.seg1_pct = imgui.drag_float("Seg 1 width %##vr", vr.seg1_pct or 0.3, 0.01, 0.0, 1.0, "%.2f"); if ch then c = true end
                ch, vr.seg2_pct = imgui.drag_float("Seg 2 width %##vr", vr.seg2_pct or 0.4, 0.01, 0.0, 1.0, "%.2f"); if ch then c = true end
                local seg3 = 1.0 - (vr.seg1_pct or 0.3) - (vr.seg2_pct or 0.4)
                imgui.text(string.format("Seg 3 width: %.0f%%", seg3 * 100))
                ch, vr.seg2_angle = imgui.drag_float("Seg 2 angle##vr", vr.seg2_angle or 0, 0.5, -45.0, 45.0, "%.1f"); if ch then c = true end
            end
            if c then save_config() end
        end

        -- ==========================================
        -- 5. PLAYER 1 DISPLAY
        -- ==========================================
        if styled_header("[ PLAYER 1 DISPLAY ]", UI_THEME.hdr_session) then
            imgui.text_colored(">> Collision Boxes", COL_YELLOW)
            _, display_p1_hitboxes = imgui.checkbox("Hitboxes##P1", display_p1_hitboxes); imgui.same_line()
            _, display_p1_hurtboxes = imgui.checkbox("Hurtboxes##P1", display_p1_hurtboxes); imgui.same_line()
            _, display_p1_pushboxes = imgui.checkbox("Pushboxes##P1", display_p1_pushboxes)
            _, display_p1_throwboxes = imgui.checkbox("Throw Boxes##P1", display_p1_throwboxes); imgui.same_line()
            _, display_p1_throwhurtboxes = imgui.checkbox("Throw Hurtboxes##P1", display_p1_throwhurtboxes)
            _, display_p1_proximityboxes = imgui.checkbox("Proximity Boxes##P1", display_p1_proximityboxes); imgui.same_line()
            _, display_p1_clashbox = imgui.checkbox("Projectile Clash##P1", display_p1_clashbox); imgui.same_line()
            _, display_p1_uniqueboxes = imgui.checkbox("Unique Boxes##P1", display_p1_uniqueboxes)
            _, display_p1_charge_bars = imgui.checkbox("Charge Bars##P1", display_p1_charge_bars)
            imgui.separator()
            imgui.separator()
            imgui.text_colored(">> HUD Top Text", COL_YELLOW)
            _, display_p1_hud_pos = imgui.checkbox("Position X##P1", display_p1_hud_pos); imgui.same_line()
            _, display_p1_hud_hp = imgui.checkbox("Health (HP)##P1", display_p1_hud_hp); imgui.same_line()
            _, display_p1_hud_dr = imgui.checkbox("Drive (DR)##P1", display_p1_hud_dr); imgui.same_line()
            _, display_p1_hud_sa = imgui.checkbox("Super (SA)##P1", display_p1_hud_sa)
            imgui.separator()
            imgui.text_colored(">> Extras", COL_YELLOW)
            _, display_p1_properties = imgui.checkbox("Display Box Properties##P1", display_p1_properties); imgui.same_line()
            _, display_p1_position_dot = imgui.checkbox("Display Position Dot##P1", display_p1_position_dot)
            imgui.separator()
            _, hide_p1_boxes = imgui.checkbox("Hide All P1 Boxes", hide_p1_boxes)
        end

        -- ==========================================
        -- 6. PLAYER 2 DISPLAY
        -- ==========================================
        if styled_header("[ PLAYER 2 DISPLAY ]", UI_THEME.hdr_session) then
            imgui.text_colored(">> Collision Boxes", COL_YELLOW)
            _, display_p2_hitboxes = imgui.checkbox("Hitboxes##P2", display_p2_hitboxes); imgui.same_line()
            _, display_p2_hurtboxes = imgui.checkbox("Hurtboxes##P2", display_p2_hurtboxes); imgui.same_line()
            _, display_p2_pushboxes = imgui.checkbox("Pushboxes##P2", display_p2_pushboxes)
            _, display_p2_throwboxes = imgui.checkbox("Throw Boxes##P2", display_p2_throwboxes); imgui.same_line()
            _, display_p2_throwhurtboxes = imgui.checkbox("Throw Hurtboxes##P2", display_p2_throwhurtboxes)
            _, display_p2_proximityboxes = imgui.checkbox("Proximity Boxes##P2", display_p2_proximityboxes); imgui.same_line()
            _, display_p2_clashbox = imgui.checkbox("Projectile Clash##P2", display_p2_clashbox); imgui.same_line()
            _, display_p2_uniqueboxes = imgui.checkbox("Unique Boxes##P2", display_p2_uniqueboxes)
            _, display_p2_charge_bars = imgui.checkbox("Charge Bars##P2", display_p2_charge_bars)
            imgui.separator()
            imgui.text_colored(">> HUD Top Text", COL_YELLOW)
            _, display_p2_hud_pos = imgui.checkbox("Position X##P2", display_p2_hud_pos); imgui.same_line()
            _, display_p2_hud_hp = imgui.checkbox("Health (HP)##P2", display_p2_hud_hp); imgui.same_line()
            _, display_p2_hud_dr = imgui.checkbox("Drive (DR)##P2", display_p2_hud_dr); imgui.same_line()
            _, display_p2_hud_sa = imgui.checkbox("Super (SA)##P2", display_p2_hud_sa)
            imgui.separator()
            imgui.text_colored(">> Extras", COL_YELLOW)
            _, display_p2_properties = imgui.checkbox("Display Box Properties##P2", display_p2_properties); imgui.same_line()
            _, display_p2_position_dot = imgui.checkbox("Display Position Dot##P2", display_p2_position_dot)
            imgui.separator()
            _, hide_p2_boxes = imgui.checkbox("Hide All P2 Boxes", hide_p2_boxes)
        end

        imgui.tree_pop()
    end
end)