-- Training_SharedUI.lua
local UI = {}
local imgui = imgui

-- Global floating rect registry (cleared each frame, any script can publish)
function UI.clear_rects()
    _G.FloatingRects = {}
end

function UI.publish_rect(x, y, w, h)
    if not _G.FloatingRects then _G.FloatingRects = {} end
    table.insert(_G.FloatingRects, { x = x, y = y, w = w, h = h })
end

UI.COLORS = {
    White  = 0xFFDADADA, Green  = 0xFF00FF00, Red    = 0xFF0000FF,
    Grey   = 0x99FFFFFF, DarkGrey = 0xFF888888, Orange = 0xFF00A5FF, 
    Cyan   = 0xFFFFFF00, Yellow = 0xFF00FFFF, 
    Shadow = 0xFF000000, Blue   = 0xFFFFAA00 
}

local fonts = { main = nil, timer = nil, main_size = 0, timer_size = 0, timer_font_name = "" }
local res = { w = 0, h = 0, cooldown = 0 }
local last_hud_suffix = "Default"

-- ==========================================
-- HUD DICTIONARY (Font, Size, Y Pos, X Pos)
-- ==========================================
UI.HUD_CONFIG = {
    ["Default"] = { font = "SF6_college.ttf", size = 78, y = -0.45, x = 0.0 },  -- SF6		: OK
    ["_01"]     = { font = "SF6_college.ttf", size = 60, y = -0.42, x = 0.0 },  -- ??? 		: 
    ["_02"]     = { font = "SF6_college.ttf", size = 50, y = -0.39, x = 0.0 },  -- SSF2 	: OK
    ["_03"]     = { font = "SF6_college.ttf", size = 45, y = -0.441, x = 0.0 }, -- SFZ3 	: OK
    ["_04"]     = { font = "SF6_college.ttf", size = 55, y = -0.425, x = 0.0 }, -- SF33s 	: OK
    ["_05"]     = { font = "SF6_college.ttf", size = 65, y = -0.445, x = 0.0 }, -- SF4 		: OK
    ["_06"]     = { font = "SF6_college.ttf", size = 65, y = -0.45, x = 0.0 },  -- SF5 		: OK
    ["_07"]     = { font = "SF6_college.ttf", size = 65, y = -0.451, x = 0.0 }  -- SIMSIM	: OK
}

function UI.get_screen_size()
    local w, h = 1920, 1080 
    if imgui.get_display_size then
        local result = imgui.get_display_size()
        if type(result) == "userdata" then
            pcall(function() w, h = result.x, result.y end)
        elseif type(result) == "number" then 
            w, h = imgui.get_display_size() 
        end
    end
    return math.max(w, 1920), math.max(h, 1080)
end

function UI.update_fonts(cfg)
    local sw, sh = UI.get_screen_size()
    local scale = math.max(0.1, sh / 1080.0)

    -- On lit la configuration du HUD actif
    local current_hud = _G.CurrentHudSuffix or "Default"
    local hud_cfg = UI.HUD_CONFIG[current_hud] or UI.HUD_CONFIG["Default"]

    local t_main = math.floor((cfg.hud_base_size or 20) * (cfg.hud_auto_scale and scale or 1.0))
    local t_timer = math.floor((hud_cfg.size) * (cfg.hud_auto_scale and scale or 1.0))

    if fonts.main_size ~= t_main then
        fonts.main = imgui.load_font("capcom_goji-udkakugoc80pro-db.ttf", t_main)
        fonts.main_size = t_main
    end
    
    -- On recharge si la taille OU le nom de la police change !
    if fonts.timer_size ~= t_timer or fonts.timer_font_name ~= hud_cfg.font then
        fonts.timer = imgui.load_font(hud_cfg.font, t_timer)
        fonts.timer_size = t_timer
        fonts.timer_font_name = hud_cfg.font
    end
end

function UI.handle_resolution(cfg)
    local sw, sh = UI.get_screen_size()
    local current_hud = _G.CurrentHudSuffix or "Default"
    local force_update = false

    if res.w == 0 then 
        res.w = sw; res.h = sh; last_hud_suffix = current_hud
        UI.update_fonts(cfg); return 
    end
    
    if sw ~= res.w or sh ~= res.h then res.cooldown = 30; res.w = sw; res.h = sh end
    
    -- NOUVEAU : Si le joueur change de HUD, on déclenche une mise à jour des polices
    if current_hud ~= last_hud_suffix then
        last_hud_suffix = current_hud
        force_update = true
    end

    if res.cooldown > 0 then 
        res.cooldown = res.cooldown - 1
        if res.cooldown == 0 then force_update = true end 
    end
    
    if force_update then UI.update_fonts(cfg) end
end

function UI.draw_text(text, x, y, color)
    local safe = string.gsub(text, "%%", "%%%%")
    local thick = 0.1
    imgui.set_cursor_pos(Vector2f.new(x, y)); imgui.text_colored(safe, UI.COLORS.Grey)
    for dx = -thick, thick do
        for dy = -thick, thick do
            if (dx ~= 0 or dy ~= 0) and (math.abs(dx) + math.abs(dy) <= thick) then
                imgui.set_cursor_pos(Vector2f.new(x + dx, y + dy))
                imgui.text_colored(safe, UI.COLORS.Grey)
            end
        end
    end
    imgui.set_cursor_pos(Vector2f.new(x, y)); imgui.text_colored(safe, color)
end

function UI.draw_timer(text, x, y, color)
    local safe = string.gsub(text, "%%", "%%%%")
    local thick = 2
    for dx = -thick, thick, thick do
        for dy = -thick, thick, thick do
            if dx ~= 0 or dy ~= 0 then
                imgui.set_cursor_pos(Vector2f.new(x + dx, y + dy))
                imgui.text_colored(safe, 0xFF000000)
            end
        end
    end
    imgui.set_cursor_pos(Vector2f.new(x, y)); imgui.text_colored(safe, color)
end

function UI.format_time(s)
    if not s or s < 0 then s = 0 end 
    return string.format("%02d:%02d", math.floor(s/60), math.floor(s%60)) 
end

function UI.push_main() if fonts.main then imgui.push_font(fonts.main) end end
function UI.pop_main() if fonts.main then imgui.pop_font() end end
function UI.push_timer() if fonts.timer then imgui.push_font(fonts.timer) end end
function UI.pop_timer() if fonts.timer then imgui.pop_font() end end


function UI.draw_standard_hud(window_name, cfg, session, mode_label, show_timer, custom_stats_func)
    UI.handle_resolution(cfg)
    local sw, sh = UI.get_screen_size()
    
    imgui.push_style_var(4, 0.0); imgui.push_style_var(2, Vector2f.new(0, 0)); imgui.push_style_color(2, 0) 
    imgui.set_next_window_pos(Vector2f.new(0, 0)); imgui.set_next_window_size(Vector2f.new(sw, sh))
    
    local win_flags = 1 | 2 | 4 | 8 | 512 | 786432 | 128 -- ImGui Flags transparents

    if imgui.begin_window(window_name, true, win_flags) then
        UI.push_main()
        
        local center_x = sw / 2; local center_y = sh / 2
        local top_y = center_y + ((cfg.hud_n_global_y or -0.33) * sh)
        local spread_score_px = (cfg.hud_n_spread_score or 0.09) * sw
        local spacing_y_px    = (cfg.hud_n_spacing_y or 0.03) * sh
        
        local off_score_px = (cfg.hud_n_offset_score or 0.0) * sw
        local off_total_px = (cfg.hud_n_offset_total or 0.0) * sw
        local off_timer_px = (cfg.hud_n_offset_timer or 0.0) * sw
        local off_status_px = (cfg.hud_n_offset_status_y or 0.0) * sh

        -- 1. TIMER
        if show_timer then
            local current_hud = _G.CurrentHudSuffix or "Default"
            local hud_cfg = UI.HUD_CONFIG[current_hud] or UI.HUD_CONFIG["Default"]
            
            local time_show = session.is_running and session.time_rem or ((cfg.timer_minutes or 0) * 60)
            local t_txt = UI.format_time(time_show)
            
            UI.pop_main(); UI.push_timer()
            
            local w_t = imgui.calc_text_size(t_txt).x
            local t_col = UI.COLORS.White
            if session.is_paused then t_col = UI.COLORS.Yellow
            elseif session.time_rem and session.time_rem < 10 and session.is_running then t_col = UI.COLORS.Red end
            if session.is_time_up then t_col = UI.COLORS.Red end
            
            -- FIX : On utilise le Y et X spécifiques au HUD détecté
            UI.draw_timer(t_txt, center_x - (w_t / 2) + (hud_cfg.x * sw), center_y + (hud_cfg.y * sh), t_col)
            
            UI.pop_timer(); UI.push_main()
        end

        -- 2. SCORE & LABELS
        local s_txt = "SCORE: " .. (session.score or 0)
        local tot_txt = "TOTAL: " .. (session.total or 0)
        
        local w_s = imgui.calc_text_size(s_txt).x
        UI.draw_text(s_txt, center_x - spread_score_px - w_s + off_score_px, top_y, session.score_col or UI.COLORS.White)

        local w_m = imgui.calc_text_size(mode_label).x
        local mode_col = session.is_paused and UI.COLORS.Yellow or UI.COLORS.White
        UI.draw_text(mode_label, center_x - (w_m / 2) + off_timer_px, top_y, mode_col)

        UI.draw_text(tot_txt, center_x + spread_score_px + off_total_px, top_y, UI.COLORS.White)

        -- 3. SPECIFIC STATS INJECTION (Callback)
        local stat_y = top_y + spacing_y_px
        if custom_stats_func then custom_stats_func(center_x, stat_y, sw, sh) end

        -- 4. STATUS
        local final_msg = session.feedback and session.feedback.text or ""
        local final_col = session.feedback and session.feedback.color or UI.COLORS.White
        
        if session.is_running and session.is_paused then
            final_msg = UI.pause_message()
            final_col = UI.COLORS.Yellow
        end
        
        local status_y = stat_y + spacing_y_px + off_status_px
        local w_msg = imgui.calc_text_size(final_msg).x
        UI.draw_text(final_msg, center_x - w_msg/2, status_y, final_col)

        UI.pop_main()
        imgui.end_window()
    end
    imgui.pop_style_var(2); imgui.pop_style_color(1)
end

-- ==========================================
-- DYNAMIC SHORTCUT LABEL (pad vs keyboard)
-- ==========================================
local function is_keyboard_mode()
    local kb = false
    pcall(function()
        local igm = sdk.get_managed_singleton("app.InputGuideManager")
        if igm then kb = (igm:call("GetMode", 0) == 2) end
    end)
    return kb
end
UI.is_keyboard_mode = is_keyboard_mode

function UI.sc(pad_key)
    local map = { L = "1", U = "2", D = "3", R = "4" }
    return is_keyboard_mode() and (map[pad_key] or pad_key) or pad_key
end

-- Training scripts: buttons left to right = D(1), U(2), R(3), L(4)
function UI.sc_t(pad_key)
    local map = { D = "1", U = "2", R = "3", L = "4" }
    return is_keyboard_mode() and (map[pad_key] or pad_key) or pad_key
end

-- ==========================================
-- FUNC BUTTON NAME + DYNAMIC MESSAGES
-- ==========================================
local FUNC_NAMES = {
    [16384] = "SELECT",
    [8192]  = "R3",
    [4096]  = "L3",
}

function UI.get_func_name()
    local id = _G.TrainingFuncButton
    if not id then return nil end
    return FUNC_NAMES[id] or ("BTN " .. tostring(id))
end

-- Dynamic pause/reset messages adapting to keyboard vs controller
function UI.pause_message()
    local fn = UI.get_func_name()
    if is_keyboard_mode() or not fn then
        return "PAUSED : PRESS 4 TO RESUME"
    end
    return "PAUSED : PRESS (" .. fn .. ") + RIGHT TO RESUME"
end

function UI.reset_message()
    local fn = UI.get_func_name()
    if is_keyboard_mode() or not fn then
        return "PRESS 3 TO RESET"
    end
    return "PRESS (" .. fn .. ") + LEFT TO RESET"
end

-- Dynamic shortcut label for button text: D/U/R/L → keyboard number or FUNC+DIR
local DIR_NAMES = { D = "DOWN", U = "UP", R = "RIGHT", L = "LEFT", A = "CROSS" }
local DIR_TO_KEY = { D = "1", U = "2", R = "3", L = "4", A = "8" }

function UI.sc_label(pad_dir, kb_key)
    local fn = UI.get_func_name()
    if is_keyboard_mode() or not fn then
        return kb_key or DIR_TO_KEY[pad_dir] or pad_dir
    else
        return fn .. "+" .. (DIR_NAMES[pad_dir] or pad_dir)
    end
end

-- Always returns pad label (longest) for stable button width calculations
function UI.sc_label_max(pad_dir)
    local fn = UI.get_func_name()
    if not fn then return DIR_TO_KEY[pad_dir] or pad_dir end
    return fn .. "+" .. (DIR_NAMES[pad_dir] or pad_dir)
end

-- ==========================================
-- SHORTCUT BUTTON COLORS (read from Training_ScriptManager via _G)
-- ==========================================
-- Fallback defaults (ABGR) if ScriptManager hasn't loaded yet
local SC_DEFAULTS = {
    c1 = { text = 0xFF4444FF, base = 0x784444FF, hover = 0xA04444FF, active = 0xC84444FF, border = 0xFFFFFFFF },
    c2 = { text = 0xFF44FF44, base = 0x7844FF44, hover = 0xA044FF44, active = 0xC844FF44, border = 0xFFFFFFFF },
    c3 = { text = 0xFFFF4444, base = 0x78FF4444, hover = 0xA0FF4444, active = 0xC8FF4444, border = 0xFFFFFFFF },
    c4 = { text = 0xFF00A5FF, base = 0x7800A5FF, hover = 0xA000A5FF, active = 0xC800A5FF, border = 0xFFFFFFFF },
}

-- Dynamic accessor: always reads live colors from _G (updated by ScriptManager)
UI.SC_COLORS = setmetatable({}, {
    __index = function(_, key)
        local g = _G.TrainingSCColors
        if g and g[key] then return g[key] end
        return SC_DEFAULTS[key]
    end
})

function UI.sc_button(label, colors, width)
    imgui.push_style_color(5,  colors.text)
    imgui.push_style_color(21, colors.base)
    imgui.push_style_color(22, colors.hover)
    imgui.push_style_color(23, colors.active)
    imgui.push_style_color(0,  colors.border)
    local clicked = imgui.button(label, width and Vector2f.new(width, 0) or nil)
    imgui.pop_style_color(5)
    return clicked
end

-- ==========================================
-- FLOATING SESSION WINDOW (ComboTrials style)
-- ==========================================
local float_ui_font = nil    -- Window font (same as ComboTrials custom_ui_font)
local float_btn_font = nil   -- Button font (same as ComboTrials sf6_btn_font)
local float_font_attempted = false
local float_last_sh = 0

function UI.begin_floating_window(window_name)
    local sw, sh = UI.get_screen_size()

    -- Load fonts (same as ComboTrials: ui=20, btn=SF6_college 22)
    if not float_font_attempted or sh ~= float_last_sh then
        float_font_attempted = true
        float_last_sh = sh
        local font_scale = sh / 1080.0
        pcall(function() float_ui_font = imgui.load_font("capcom_goji-udkakugoc80pro-db.ttf", math.max(10, math.floor(20 * font_scale))) end)
        pcall(function() float_btn_font = imgui.load_font("SF6_college.ttf", math.max(10, math.floor(22 * font_scale))) end)
    end

    -- Identical style to ComboTrials floating window
    imgui.push_style_color(2,  0x00000000)   -- WindowBg transparent
    imgui.push_style_color(5,  0x00000000)   -- Border transparent
    imgui.push_style_color(7,  0xAA220044)   -- Border accent
    imgui.push_style_color(8,  0xCC6600AA)   -- Title bar
    imgui.push_style_var(2, Vector2f.new(sw * 0.01, sh * 0.02))  -- WindowPadding

    if float_ui_font then imgui.push_font(float_ui_font) end

    -- Full width, same height as ComboTrials single-line bar, fixed at bottom
    local target_h = sh * 0.0444
    imgui.set_next_window_size(Vector2f.new(sw, target_h), 1)      -- Always
    imgui.set_next_window_pos(Vector2f.new(0, sh - target_h), 1)   -- Always
    -- 15 = NoTitleBar(1) + NoResize(2) + NoMove(4) + NoScrollbar(8)
    local visible = imgui.begin_window(window_name, true, 15)
    if not visible then _G.TrainingFloatingBar = nil end
    return visible, sw, sh
end

function UI.end_floating_window()
    imgui.end_window()
    if float_ui_font then imgui.pop_font() end
    imgui.pop_style_var(1)   -- WindowPadding
    imgui.pop_style_color(4)
end

-- Top floating window (vertical mirror of the bottom one)
function UI.begin_floating_window_top(window_name, width_pct, height_pct)
    local sw, sh = UI.get_screen_size()
    width_pct = width_pct or 1.0
    height_pct = height_pct or 0.0444

    -- Load fonts (reuses same font cache as bottom bar)
    if not float_font_attempted or sh ~= float_last_sh then
        float_font_attempted = true
        float_last_sh = sh
        local font_scale = sh / 1080.0
        pcall(function() float_ui_font = imgui.load_font("capcom_goji-udkakugoc80pro-db.ttf", math.max(10, math.floor(20 * font_scale))) end)
        pcall(function() float_btn_font = imgui.load_font("SF6_college.ttf", math.max(10, math.floor(22 * font_scale))) end)
    end

    imgui.push_style_color(2,  0x00000000)   -- WindowBg transparent
    imgui.push_style_color(5,  0x00000000)   -- Border transparent
    imgui.push_style_color(7,  0xAA220044)   -- Border accent
    imgui.push_style_color(8,  0xCC6600AA)   -- Title bar
    imgui.push_style_var(2, Vector2f.new(sw * 0.01, sh * 0.02))  -- WindowPadding

    if float_ui_font then imgui.push_font(float_ui_font) end

    local target_w = sw * width_pct
    local target_h = sh * height_pct
    imgui.set_next_window_size(Vector2f.new(target_w, target_h), 1)
    imgui.set_next_window_pos(Vector2f.new((sw - target_w) / 2, 0), 1)  -- Centered at top
    local visible = imgui.begin_window(window_name, true, 15)
    return visible, sw, sh
end

function UI.end_floating_window_top()
    imgui.end_window()
    if float_ui_font then imgui.pop_font() end
    imgui.pop_style_var(1)
    imgui.pop_style_color(4)
end

-- Draw dark background for top bar
function UI.draw_floating_bg_top()
    local w = imgui.get_window_size()
    imgui.set_cursor_pos(Vector2f.new(-10, -10))
    imgui.push_style_color(7, 0xFF220000)
    pcall(function() imgui.progress_bar(0.0, Vector2f.new(w.x + 20, w.y + 20)) end)
    imgui.pop_style_color(1)
    -- Publish window rect
    local pos = imgui.get_window_pos()
    _G.TrainingFloatingBarTop = { x = pos.x, y = pos.y, w = w.x, h = w.y, active = true }
    UI.publish_rect(pos.x, pos.y, w.x, w.y)
end

-- Draw dark background (same as ComboTrials progress_bar trick)
function UI.draw_floating_bg()
    local w = imgui.get_window_size()
    imgui.set_cursor_pos(Vector2f.new(-10, -10))
    imgui.push_style_color(7, 0xFF220000)
    pcall(function() imgui.progress_bar(0.0, Vector2f.new(w.x + 20, w.y + 20)) end)
    imgui.pop_style_color(1)
    -- Publish window rect
    local pos = imgui.get_window_pos()
    _G.TrainingFloatingBar = { x = pos.x, y = pos.y, w = w.x, h = w.y, active = true }
    UI.publish_rect(pos.x, pos.y, w.x, w.y)
end

-- SF6 neon button (identical to styled_sf6_button in floating mode with sf6_btn_font)
function UI.sf6_button(label, colors, width)
    if float_btn_font then imgui.push_font(float_btn_font) end
    imgui.push_style_color(5,  colors.text)    -- Border
    imgui.push_style_color(21, colors.base)    -- Button
    imgui.push_style_color(22, colors.hover)   -- ButtonHovered
    imgui.push_style_color(23, colors.active)  -- ButtonActive
    imgui.push_style_color(0,  colors.border)  -- Text
    local clicked = imgui.button(label, Vector2f.new(width or 0, 0))
    imgui.pop_style_color(5)
    if float_btn_font then imgui.pop_font() end
    return clicked
end

return UI