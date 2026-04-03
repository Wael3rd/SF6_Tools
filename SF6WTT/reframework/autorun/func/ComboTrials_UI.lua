-- =========================================================
-- ComboTrials_UI.lua - All ImGui UI code
-- Received shared context via init(). Registers re.on_frame and re.on_draw_ui.
-- =========================================================



local sdk = sdk
local imgui = imgui
local re = re
local json = json

local M = {}
local ctx

-- Forward declarations resolved in init()
local d2d_cfg, trial_state, players, file_system
local common_exceptions, sf6_menu_state
local load_and_start_trial, start_recording, stop_recording_and_save, cancel_recording
local refresh_combo_list, restore_trial_vital, save_d2d_config, get_exc_filename
local ui_state


local dump_status = ""
local exc_status = ""

-- Raccourcis dynamiques : pad (L/U/D/R) ou clavier (1/2/3/4)
-- InputGuideManager.GetMode(0) : 1=pad, 2=clavier
local function sc(pad_key)
    local kb = false
    pcall(function()
        local igm = sdk.get_managed_singleton("app.InputGuideManager")
        if igm then kb = (igm:call("GetMode", 0) == 2) end
    end)
    local map = { L = "1", U = "2", D = "3", R = "4" }
    return kb and (map[pad_key] or pad_key) or pad_key
end

-- =========================================================
-- THEME ET STYLES UI (Inspirés du Training Hit Confirm)
-- =========================================================
local COLORS = {
    White = 0xFFDADADA,
    Green = 0xFF00FF00,
    Red = 0xFF0000FF,
    Grey = 0x99FFFFFF,
    DarkGrey = 0xFF888888,
    Orange = 0xFF00A5FF,
    Cyan = 0xFFFFFF00,
    Yellow = 0xFF00FFFF,
    Shadow = 0xFF000000,
    Blue = 0xFFFFAA00
}

local UI_THEME = {
    hdr_info    = { base = 0xFFDB9834, hover = 0xFFE6A94D, active = 0xFFC78320 },
    hdr_session = { base = 0xFFB6599B, hover = 0xFFC770AC, active = 0xFFA04885 },
    hdr_rules   = { base = 0xFF5D6DDA, hover = 0xFF7382E6, active = 0xFF4555C9 },
    hdr_matrix  = { base = 0xFF9CBC1A, hover = 0xFFAED12B, active = 0xFF8AA814 },

    btn_neutral = { base = 0xFF444444, hover = 0xFF666666, active = 0xFF222222 },
    btn_green   = { base = 0xFF00AA00, hover = 0xFF00CC22, active = 0xFF007700 },
    btn_red     = { base = 0xFF0000CC, hover = 0xFF2222FF, active = 0xFF000099 },
    btn_orange  = { base = 0xFFFF8800, hover = 0xFFFFAA33, active = 0xFFCC6600 }
}

local function styled_button(label, style, text_col)
    imgui.push_style_color(21, style.base); imgui.push_style_color(22, style.hover); imgui.push_style_color(23,
        style.active)
    if text_col then imgui.push_style_color(0, text_col) end
    local clicked = imgui.button(label)
    if text_col then imgui.pop_style_color(1) end
    imgui.pop_style_color(3)
    return clicked
end

local function styled_header(label, style)
    imgui.push_style_color(24, style.base); imgui.push_style_color(25, style.hover); imgui.push_style_color(26,
        style.active)
    local is_open = imgui.collapsing_header(label)
    imgui.pop_style_color(3)
    return is_open
end

-- Fonction de tri alphanumérique pour les exceptions
local function sort_ids(dict)
    local keys = {}
    for k in pairs(dict) do table.insert(keys, k) end
    table.sort(keys, function(a, b)
        local num_a, num_b = tonumber(a), tonumber(b)
        if num_a and num_b then return num_a < num_b end
        return tostring(a) < tostring(b)
    end)
    return keys
end

-- =========================================================
-- FONCTION PARTAGÉE : CONTENU DE L'ONGLET 1
-- =========================================================
local show_trial_overlay = true

local sf6_btn_font = nil
local custom_ui_font = nil
local hud_overlay_font = nil
local font_attempted = false

-- =========================================================
-- FONCTION BOUTONS (Caméléon : Néon ou Natif)
-- =========================================================
-- Couleurs code couleur barres de vie SF6 (ABGR)
-- ABGR format: 0xAABBGGRR
local P1_COLORS = {
    text   = 0xFF4444FF,  -- Rouge (bordure)
    base   = 0xFF141464,  -- Rouge sombre
    hover  = 0xFF28288C,  -- Rouge moyen
    active = 0xFF3C3CB4,  -- Rouge vif
    border = 0xFFFFFFFF,  -- Texte blanc
}
local P2_COLORS = {
    text   = 0xFFFF4444,  -- Bleu (bordure)
    base   = 0xFF641414,  -- Bleu sombre
    hover  = 0xFF8C2828,  -- Bleu moyen
    active = 0xFFB43C3C,  -- Bleu vif
    border = 0xFFFFFFFF,  -- Texte blanc
}
local TRIAL_COLORS = {
    text   = 0xFF44FF44,  -- Vert (bordure)
    base   = 0xFF146414,  -- Vert sombre
    hover  = 0xFF288C28,  -- Vert moyen
    active = 0xFF3CB43C,  -- Vert vif
    border = 0xFFFFFFFF,  -- Texte blanc
}
local SWITCH_COLORS = {
    text   = 0xFF00A5FF,  -- Orange (bordure)
    base   = 0xFF0A4878,  -- Orange sombre
    hover  = 0xFF1A6CA0,  -- Orange moyen
    active = 0xFF2890CC,  -- Orange vif
    border = 0xFFFFFFFF,  -- Texte blanc
}

local function styled_sf6_button(label, is_active, width, is_floating, is_disabled, color_override)
    width = width or 0

    -- MODE DOCKÉ (Menu Debug natif)
    if not is_floating then
        local style = is_active and UI_THEME.btn_green or UI_THEME.btn_neutral
        imgui.push_style_color(21, style.base)
        imgui.push_style_color(22, style.hover)
        imgui.push_style_color(23, style.active)
        local clicked = imgui.button(label, Vector2f.new(width, 0))
        imgui.pop_style_color(3)
        return clicked
    end

    -- MODE FLOTTANT (Néon SF6)
    if sf6_btn_font then imgui.push_font(sf6_btn_font) end

    if color_override then
        -- CUSTOM COLOR always takes priority
        imgui.push_style_color(5, color_override.text)
        imgui.push_style_color(21, color_override.base)
        imgui.push_style_color(22, color_override.hover)
        imgui.push_style_color(23, color_override.active)
        imgui.push_style_color(0, color_override.border)
    elseif is_active then
        if label:upper():match("RECORD") or label:upper():match("SAVE") then
            imgui.push_style_color(5, 0xFFFFFFFF)
            imgui.push_style_color(21, 0xFF2222AA)
            imgui.push_style_color(22, 0xFF3333DD)
            imgui.push_style_color(23, 0xFF5555FF)
            imgui.push_style_color(0, 0xFFAAAAFF)
        else
            imgui.push_style_color(5, 0xFFFFFFFF)
            imgui.push_style_color(21, 0xFF228B22)
            imgui.push_style_color(22, 0xFF32CD32)
            imgui.push_style_color(23, 0xFF55FF55)
            imgui.push_style_color(0, 0xFFAAFFAA)
        end
    elseif is_disabled then
        imgui.push_style_color(5, 0xFFEEEEEE)
        imgui.push_style_color(21, 0xFF333333)
        imgui.push_style_color(22, 0xFF555555)
        imgui.push_style_color(23, 0xFF777777)
        imgui.push_style_color(0, 0xFF777777)
    else
        imgui.push_style_color(5, 0xFFFF33CC)
        imgui.push_style_color(21, 0xFF330055)
        imgui.push_style_color(22, 0xFF660088)
        imgui.push_style_color(23, 0xFF8822AA)
        imgui.push_style_color(0, 0xFFDDDDDD)
    end

    local clicked = imgui.button(label, Vector2f.new(width, 0))

    imgui.pop_style_color(5)
    if sf6_btn_font then imgui.pop_font() end
    return clicked
end

-- Petite fonction utilitaire pour calculer la largeur du bouton le plus long
local function get_max_text_width(texts, is_floating)
    local use_custom = is_floating and sf6_btn_font
    if use_custom then imgui.push_font(sf6_btn_font) end
    local max_w = 0
    for _, text in ipairs(texts) do
        local w = imgui.calc_text_size(text).x
        if w > max_w then max_w = w end
    end
    if use_custom then imgui.pop_font() end
    return max_w + (use_custom and 30 or 15) -- Marges ajustées selon le mode
end



-- =========================================================
-- SINGLE LINE MODE : FORCE POS | P1 | P2 | SLOT 1 | SLOT 2 | SLOT 3 | SLOT 4 | ☑
-- =========================================================
local function draw_single_line_content()
    local sw, sh = ctx.cached_sw, ctx.cached_sh
    local w_width = imgui.get_window_size().x
    local win_h = imgui.get_window_size().y
    local sp = 4 * (sh / 1080.0)
    local pad_x = sw * 0.01
    local pad_y = sh * 0.01

    -- Largeurs sans les boutons P2
    local rec_btn_w_base = get_max_text_width({ "STOP & SAVE (" .. sc("L") .. ")", "CANCEL (" .. sc("U") .. ")", "RECORD P1 (" .. sc("L") .. ")", "RECORD P2 (" .. sc("D") .. ")", "RESET (" .. sc("L") .. ")", "DEMO (" .. sc("D") .. ")" }, true)
    local play_btn_w_base = get_max_text_width({ "START TRIAL P1 (" .. sc("U") .. ")", "STOP TRIAL P1 (" .. sc("U") .. ")", "SWITCH POS (" .. sc("R") .. ")" }, true)
    
    local absolute_btn_w = math.max(rec_btn_w_base, play_btn_w_base)

    local cb_size = imgui.calc_text_size("W").y + 6
    local cb_reserve = cb_size + 10

    -- Répartition dynamique : 2 Dropdowns + 4 Boutons = 6 parts (L'espace vide est comblé)
    local usable_w = w_width - (pad_x * 2) - cb_reserve - (sp * 6)
    
    -- 1. Fixed width for dropdowns (based on button text size to remain clean)
    local dd_w = absolute_btn_w
    
    -- 2. The 4 buttons dynamically share ALL the remaining empty space
    local remaining_for_btns = usable_w - (dd_w * 2)
    local actual_btn_w = math.max(absolute_btn_w, remaining_for_btns / 4)

    local dynamic_rec_w = actual_btn_w
    local is_demo_active_early = (ctx.demo_state and ctx.demo_state.is_playing)
    if trial_state.is_recording or is_demo_active_early then
        -- In record/demo mode, distribute the massive 4-button space into 2
        dynamic_rec_w = (actual_btn_w * 4 + sp * 2) / 2
    end

    imgui.set_cursor_pos(Vector2f.new(-10, -10))
    imgui.push_style_color(7, 0xFF220000)
    if not pcall(function() imgui.progress_bar(0.0, Vector2f.new(w_width + 20, win_h + 20)) end) then
        pcall(function() imgui.progress_bar(0.0, Vector2f.new(w_width + 20, win_h + 20), "") end)
    end
    imgui.pop_style_color(1)

    imgui.set_cursor_pos(Vector2f.new(pad_x, pad_y))

    -- 1. FORCE POS
    imgui.push_item_width(dd_w)
    local c_launch, v_launch = imgui.combo("##Forced-Position", d2d_cfg.forced_position_idx, file_system.forced_position_options)
    if c_launch then d2d_cfg.forced_position_idx = v_launch; save_d2d_config() end
    imgui.pop_item_width()

    -- 2. DROPDOWN P1
    imgui.same_line(0, sp)
    imgui.push_item_width(dd_w)
    if #file_system.saved_combos_display_p1 == 0 then
        imgui.combo("##EmptyP1", 1, { "No P1 files" })
    else
        local f1_changed, new_idx1 = imgui.combo("##FilesP1", file_system.selected_file_idx_p1, file_system.saved_combos_display_p1)
        if f1_changed then
            file_system.selected_file_idx_p1 = new_idx1
            load_and_start_trial(0)
        end
    end
    imgui.pop_item_width()

    -- 3. BOUTONS (Dynamiques pour combler le vide)
    imgui.same_line(0, sp)
    local is_demo_active = (ctx.demo_state and ctx.demo_state.is_playing)

    if trial_state.is_recording then
        -- Mode Record
        if styled_sf6_button("STOP & SAVE (" .. sc("L") .. ")", true, dynamic_rec_w, true, false, TRIAL_COLORS) then stop_recording_and_save() end
        imgui.same_line(0, sp)
        if styled_sf6_button("CANCEL (" .. sc("U") .. ")", false, dynamic_rec_w, true, false, P1_COLORS) then cancel_recording() end
    elseif is_demo_active then
        -- MODE DEMO : 2 boutons (même largeur que record)
        if styled_sf6_button("RESTART DEMO (" .. sc("L") .. ")", false, dynamic_rec_w, true, false, TRIAL_COLORS) then
            if ctx.start_demo then ctx.start_demo() end
        end
        imgui.same_line(0, sp)
        if styled_sf6_button("QUIT DEMO (" .. sc("U") .. ")", false, dynamic_rec_w, true, false, P1_COLORS) then
            if ctx.stop_demo then ctx.stop_demo() end
        end
    else
        -- Mode Normal / Playing
        if trial_state.is_playing then
            if styled_sf6_button("RESET (" .. sc("L") .. ")", false, actual_btn_w, true, false, P1_COLORS) then
                ctx.reset_trial_steps_and_load(trial_state.playing_player)
                ctx.apply_forced_position()
            end
        else
            if styled_sf6_button("RECORD P1 (" .. sc("L") .. ")", false, actual_btn_w, true, false, P1_COLORS) then start_recording(0) end
        end

        imgui.same_line(0, sp)
        if trial_state.is_playing then
            if styled_sf6_button("STOP TRIAL (" .. sc("U") .. ")", true, actual_btn_w, true, false, TRIAL_COLORS) then
                trial_state.is_playing = false
            end
        elseif not trial_state.is_recording then
            local is_p1_active = (trial_state.is_playing and trial_state.playing_player == 0)
            if styled_sf6_button(is_p1_active and "STOP TRIAL P1 (" .. sc("U") .. ")" or "START TRIAL P1 (" .. sc("U") .. ")", is_p1_active, actual_btn_w, true, false, TRIAL_COLORS) then
                if is_p1_active then trial_state.is_playing = false
                else load_and_start_trial(0) end
            end
        end

        imgui.same_line(0, sp)
        if trial_state.is_playing then
            if styled_sf6_button("DEMO (" .. sc("D") .. ")", false, actual_btn_w, true, false, P2_COLORS) then
                if ctx.start_demo then ctx.start_demo() end
            end
        else
            if styled_sf6_button("RECORD P2 (" .. sc("D") .. ")", false, actual_btn_w, true, false, P2_COLORS) then start_recording(1) end
        end

        imgui.same_line(0, sp)
        if styled_sf6_button("SWITCH POS (" .. sc("R") .. ")", false, actual_btn_w, true, false, SWITCH_COLORS) then
            d2d_cfg.forced_position_idx = d2d_cfg.forced_position_idx + 1
            if d2d_cfg.forced_position_idx > 3 then d2d_cfg.forced_position_idx = 1 end
            ctx.save_d2d_config()
            if trial_state.is_playing then
                ctx.apply_forced_position()
                ctx.reset_trial_steps_and_load(trial_state.playing_player)
                if ctx.reset_visuals then ctx.reset_visuals() end
            end
        end
	end
    -- 7. CHECKBOX
    imgui.same_line(w_width - cb_reserve - pad_x)
    local changed, new_val = imgui.checkbox("##close_float_sl", show_trial_overlay)
    if changed then show_trial_overlay = new_val end
end

local function draw_combo_trials_content(is_floating)
    local sw, sh = ctx.cached_sw, ctx.cached_sh
    local size = imgui.get_window_size()
    local w_width = (size.x > 50) and size.x or (sw * 0.44)

    local rec_btn_w_base = get_max_text_width({ "STOP & SAVE (" .. sc("L") .. ")", "CANCEL (" .. sc("U") .. ")", "RECORD P1 (" .. sc("L") .. ")", "RECORD P2 (" .. sc("D") .. ")", "RESET (" .. sc("L") .. ")", "DEMO (" .. sc("D") .. ")" }, is_floating)
    local play_btn_w_base = get_max_text_width({ "START TRIAL P1 (" .. sc("U") .. ")", "STOP TRIAL P1 (" .. sc("U") .. ")", "SWITCH POS (" .. sc("R") .. ")" }, is_floating)

    local absolute_btn_w = math.max(rec_btn_w_base, play_btn_w_base)
    local spacing_cols = 20 * (sh / 1080.0)
    local spacing_x = 8.0

    local min_inline_w = 150 + (absolute_btn_w * 2) + (spacing_cols * 3)
    local mode_all_inline = w_width >= min_inline_w
    local mode_all_stacked = w_width < (absolute_btn_w * 1.5)
    local mode_col2_3_inline = not mode_all_inline and not mode_all_stacked

    local rec_btn_w = absolute_btn_w
    local play_btn_w = absolute_btn_w

    local col3_x, col2_x, col1_w

    if mode_all_inline then
        if trial_state.is_recording then
            -- Mode 'Replay & Recording Settings' en Record : Colonne 3 vide, Colonne 2 prend tout le reste
            col1_w = math.max(150, (w_width - (spacing_cols * 3)) / 3)
            col2_x = col1_w + spacing_cols
            col3_x = w_width -- Ignoré
            rec_btn_w = w_width - col2_x - spacing_cols
        else
            col3_x = math.max(w_width - play_btn_w - spacing_cols, 10)
            col2_x = math.max(col3_x - rec_btn_w - spacing_cols, 10)
            col1_w = math.max(col2_x - spacing_cols, 150)
        end
    else
        col1_w = w_width - (40 * (sh / 1080.0))
        if mode_col2_3_inline then
            if trial_state.is_recording then
                -- Make recording buttons dynamically fill the entire column width
                rec_btn_w = col1_w
            else
                local half_w = (col1_w - spacing_x) / 2
                rec_btn_w = half_w
                play_btn_w = half_w
            end
        elseif mode_all_stacked then
            rec_btn_w = col1_w
            play_btn_w = col1_w
        end
    end

    -- =====================================
    -- Colonne 1 : MANAGEMENT
    -- =====================================
    imgui.begin_group()
    if not is_floating then imgui.text_colored("1. MANAGEMENT", COLORS.Cyan) end

    imgui.push_item_width(col1_w)
    local c_launch, v_launch = imgui.combo("##Forced-Position", d2d_cfg.forced_position_idx, file_system.forced_position_options)
    if c_launch then
        d2d_cfg.forced_position_idx = v_launch; save_d2d_config()
    end
    imgui.pop_item_width()

    -- DROPDOWN P1 (Prend désormais toute la largeur dispo, fini le dropdown P2)
    imgui.push_item_width(col1_w)
    if #file_system.saved_combos_display_p1 == 0 then
        imgui.combo("##EmptyP1", 1, { "No P1 files" })
    else
        local f1_changed, new_idx1 = imgui.combo("##FilesP1", file_system.selected_file_idx_p1, file_system.saved_combos_display_p1)
        if f1_changed then
            file_system.selected_file_idx_p1 = new_idx1
            load_and_start_trial(0)
        end
    end
    imgui.pop_item_width()

    imgui.end_group()

    -- =====================================
    -- Colonne 2 : RECORDING
    -- =====================================
    if mode_all_inline then imgui.same_line(col2_x) else imgui.spacing(); imgui.separator(); imgui.spacing() end

    imgui.begin_group()
    if not is_floating then imgui.text_colored("2. RECORDING", COLORS.White) end
    
    local is_demo_active = (ctx.demo_state and ctx.demo_state.is_playing)
    if trial_state.is_playing or is_demo_active then
        if styled_sf6_button("RESET (" .. sc("L") .. ")", false, rec_btn_w, is_floating) then
            if is_demo_active then
                if ctx.start_demo then ctx.start_demo() end
            else
                ctx.reset_trial_steps_and_load(trial_state.playing_player)
                ctx.apply_forced_position()
            end
        end
        if mode_all_stacked then imgui.spacing() end
        if styled_sf6_button("DEMO (" .. sc("D") .. ")", is_demo_active, rec_btn_w, is_floating, false, P2_COLORS) then
            if is_demo_active then
                if ctx.stop_demo then ctx.stop_demo() end
            else
                if ctx.start_demo then ctx.start_demo() end
            end
        end
    elseif trial_state.is_recording then
        if styled_sf6_button("STOP & SAVE (" .. sc("L") .. ")", true, rec_btn_w, is_floating, false, TRIAL_COLORS) then
            stop_recording_and_save()
        end

        -- Toujours forcer l'empilement (stack) avec un espacement en mode fenêtré
        imgui.spacing()

        if styled_sf6_button("CANCEL (" .. sc("U") .. ")", false, rec_btn_w, is_floating, false, P1_COLORS) then
            cancel_recording()
        end
    else
        if styled_sf6_button("RECORD P1 (" .. sc("L") .. ")", false, rec_btn_w, is_floating, false, P1_COLORS) then
            start_recording(0)
        end
        if mode_all_stacked then imgui.spacing() end
        if styled_sf6_button("RECORD P2 (" .. sc("D") .. ")", false, rec_btn_w, is_floating, false, P2_COLORS) then
            start_recording(1)
        end
    end
    imgui.end_group()

    -- =====================================
    -- Colonne 3 : PLAYBACK
    -- =====================================
    if mode_all_stacked then imgui.spacing(); imgui.separator(); imgui.spacing()
    elseif mode_col2_3_inline then imgui.same_line(0, spacing_x)
    else imgui.same_line(col3_x) end

    imgui.begin_group()
    if not is_floating then imgui.text_colored("3. PLAYBACK (TRIAL)", COLORS.White) end

    if trial_state.is_playing or is_demo_active then
        if styled_sf6_button("STOP TRIAL (" .. sc("U") .. ")", true, play_btn_w, is_floating, false, TRIAL_COLORS) then
            trial_state.is_playing = false
            if ctx.stop_demo then ctx.stop_demo() end
        end
    elseif not trial_state.is_recording then
        local is_p1_active = (trial_state.is_playing and trial_state.playing_player == 0)
        if styled_sf6_button(is_p1_active and "STOP TRIAL P1 (" .. sc("U") .. ")" or "START TRIAL P1 (" .. sc("U") .. ")", is_p1_active, play_btn_w, is_floating, false, TRIAL_COLORS) then
            if is_p1_active then trial_state.is_playing = false
            else load_and_start_trial(0) end
        end
    end
    
    if mode_all_stacked then imgui.spacing() end
    
    -- SWITCH POS (Invisible en record)
    if not trial_state.is_recording then
        if styled_sf6_button("SWITCH POS (" .. sc("R") .. ")", false, play_btn_w, is_floating, false, SWITCH_COLORS) then
            d2d_cfg.forced_position_idx = d2d_cfg.forced_position_idx + 1
            if d2d_cfg.forced_position_idx > 3 then d2d_cfg.forced_position_idx = 1 end
            ctx.save_d2d_config()
            
            local is_demo_active = (ctx.demo_state and ctx.demo_state.is_playing)
            -- On applique physiquement la position UNIQUEMENT si un trial ou une démo est en cours
            if is_demo_active or trial_state.is_playing then
                ctx.apply_forced_position()
                if is_demo_active then
                    if ctx.start_demo then ctx.start_demo() end
                else
                    if ctx.reset_trial_steps_and_load then ctx.reset_trial_steps_and_load(trial_state.playing_player) end
                end
                if ctx.reset_visuals then ctx.reset_visuals() end
            end
        end
    end
    imgui.end_group()
    imgui.spacing()
end

-- =========================================================
-- RENDU FENÊTRE FLOTTANTE INDÉPENDANTE (Dans re.on_frame)
-- =========================================================
-- sf6_menu_state is received from ctx in init()

local function get_imgui_screen_size()
    local result = imgui.get_display_size()
    local w, h = 0, 0
    if type(result) == "userdata" then
        local ok, x = pcall(function() return result.x end)
        local ok2, y = pcall(function() return result.y end)
        if ok and ok2 then
            w = x; h = y
        else
            w = result.w or 0; h = result.h or 0
        end
    elseif type(result) == "number" then
        w, h = imgui.get_display_size()
    end
    return w, h
end

local ui_dirty = false
local ui_save_timer = 0
local last_sw, last_sh = 0, 0
local res_cooldown = 0
local force_float_resize = 0

re.on_frame(function()
    if _G.CurrentTrainerMode ~= 4 then
        sf6_menu_state.active = false
        _G.ComboTrials_HideNativeHUD = false
        return
    end

    local is_game_active = false
    local pm = sdk.get_managed_singleton("app.PauseManager")
    if pm then
        local b = pm:get_field("_CurrentPauseTypeBit")
        if b == 64 or b == 2112 then is_game_active = true end
    end

    -- Utilisation de l'API ImGui exacte pour le positionnement de la fenêtre
    local sw, sh = get_imgui_screen_size()
    if sw == nil or sh == nil or sw <= 0 or sh <= 0 then return end

    -- DÉTECTION ET COOLDOWN
    local res_changed = false
    if last_sw ~= sw or last_sh ~= sh then
        if last_sw ~= 0 then
            res_changed = true
            res_cooldown = 5 -- Freeze la position pendant 5 frames
        end
        last_sw = sw
        last_sh = sh
    end

    if res_cooldown > 0 then res_cooldown = res_cooldown - 1 end
    local is_resizing = (res_changed or res_cooldown > 0)

    if not d2d_cfg.float_pos then d2d_cfg.float_pos = { x = 0.2, y = 0.2 } end
    if not d2d_cfg.float_size then d2d_cfg.float_size = { w = 0.44, h = 0.20 } end

    -- RECHARGEMENT DES POLICES (Uniquement à la frame exacte du changement)
    if not font_attempted or res_changed then
        local font_scale = sh / 1080.0
        pcall(function()
            custom_ui_font = imgui.load_font("capcom_goji-udkakugoc80pro-db.ttf",
                math.max(10, math.floor(20 * font_scale)))
        end)
        pcall(function() sf6_btn_font = imgui.load_font("SF6_college.ttf", math.max(10, math.floor(22 * font_scale))) end)
        local hud_size = math.max(10, math.floor((d2d_cfg.hud_font_size or 20) * font_scale))
        pcall(function() hud_overlay_font = imgui.load_font("capcom_goji-udkakugoc80pro-db.ttf", hud_size) end)
        font_attempted = true
    end

    -- =========================================================
    -- HUD OVERLAY : Combo Stats sur les lignes natives (pattern HitConfirm)
    -- =========================================================
    -- Déterminer si on doit afficher notre HUD ou laisser le jeu afficher les infos natives
    local show_our_hud = false
    local line1, line2, line3 = "", "", ""
    local col1, col2, col3 = 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF

    if is_game_active and d2d_cfg.hud_show then
        -- Logic commune pour déterminer la ligne 1 (Trial Title) et sa couleur (format IMGUI ABGR)
        if trial_state.success_timer > 0 then
            line1 = "!!! SUCCESS !!!"; col1 = 0xFF00FF00
            show_our_hud = true
        elseif trial_state.is_playing and trial_state.fail_timer and trial_state.fail_timer > 0 then
            line1 = "[ " .. (trial_state.fail_reason or "FAILED") .. " ]"
            col1 = (trial_state.fail_reason and string.match(trial_state.fail_reason, "TOO")) and 0xFF0000FF or
                0xFF00A5FF
            show_our_hud = true
        elseif trial_state.is_recording then
            line1 = "[ RECORDING P" .. tostring(trial_state.recording_player + 1) .. " ]"; col1 = 0xFF5555FF
            show_our_hud = true
        elseif trial_state.is_playing then
            local is_demo_active = (ctx.demo_state and ctx.demo_state.is_playing)
            local demo_countdown = (is_demo_active and ctx.demo_state.countdown) and math.ceil(ctx.demo_state.countdown / 20) or 0

            if demo_countdown > 0 then
                line1 = "[ DEMO STARTING ]"
                col1 = 0xFFFFFF00 -- Cyan
            else
                local total_steps = #trial_state.sequence
                if total_steps > 0 then
                    -- Utilisation de l'étape visuelle retardée
                    local display_step = trial_state.ui_visual_step or 1
                    local current = math.min(display_step, total_steps)
                    line1 = string.format("[ ACTION %d / %d ]", current, total_steps)
                else
                    line1 = "[ TRIAL FOR P" .. tostring(trial_state.playing_player + 1) .. " ]"
                end

                if trial_state.floating_info then
                    line1 = line1 .. "  |  " .. trial_state.floating_info
                    col1 = trial_state.floating_color or 0xFF00FFFF
                else
                    col1 = 0xFF00FFFF -- Jaune par défaut
                end
            end
            show_our_hud = true
        end

        if trial_state.is_recording and trial_state._rec_gauges then
            -- MODE RECORDING : Affichage LIVE des deltas en cours
            local rg    = trial_state._rec_gauges
            local dmg   = math.max(0, (rg.victim_hp or 0) - (rg.min_victim_hp or rg.victim_hp or 0))
            local dr    = math.max(0, (rg.attacker_drive or 0) - (rg.min_atk_drive or rg.attacker_drive or 0))
            local sa    = math.max(0, (rg.attacker_super or 0) - (rg.min_atk_super or rg.attacker_super or 0))

            -- Line 2 : Damage live
            line2       = string.format("DAMAGE: %d", dmg)

            -- Line 3 : Drive & Super live
            local parts = {}
            if dr > 0 then table.insert(parts, string.format("DRIVE: -%.1f", dr / 10000)) end
            if sa > 0 then table.insert(parts, string.format("SUPER: -%.1f", sa / 10000)) end
            line3 = #parts > 0 and table.concat(parts, "     ") or ""
        elseif trial_state.is_playing and #trial_state.sequence > 0 and trial_state.sequence[1] then
            -- MODE TRIAL / SÉQUENCE CHARGÉE : Affichage des stats sauvegardées
            local cs = trial_state.sequence[1].combo_stats

            if cs then
                line2 = cs.damage and cs.damage > 0 and string.format("DAMAGE: %d", cs.damage) or "DAMAGE: ---"

                local parts = {}
                if cs.drive_used and cs.drive_used > 0 then
                    table.insert(parts, string.format("DRIVE: -%.1f", cs.drive_used / 10000))
                end
                if cs.super_used and cs.super_used > 0 then
                    table.insert(parts, string.format("SUPER: -%.1f", cs.super_used / 10000))
                end
                line3 = #parts > 0 and table.concat(parts, "     ") or ""
            else
                line2 = "DAMAGE: ---"
            end
        end
        -- else : ni recording ni trial → show_our_hud reste false → infos natives visibles
    end

    -- Flag global lu par Training_ScriptManager pour cacher/montrer les infos natives
    _G.ComboTrials_HideNativeHUD = show_our_hud

    if show_our_hud then
        imgui.push_style_color(2, 0)
        imgui.set_next_window_pos(Vector2f.new(0, 0))
        imgui.set_next_window_size(Vector2f.new(sw, sh))

        local hud_flags = 1 | 2 | 4 | 8 | 128 | 512 | 2048

        if imgui.begin_window("ComboTrials_HUD", true, hud_flags) then
            if hud_overlay_font then imgui.push_font(hud_overlay_font) end

            local cx = sw / 2
            local cy = sh / 2
            local line1_y = cy + (d2d_cfg.hud_global_y * sh)
            local line2_y = line1_y + (d2d_cfg.hud_spacing_y * sh)
            local line3_y = line2_y + (d2d_cfg.hud_spacing_y * sh)

            local outline_color = 0xFF444444
            local outline_thick = 0.1

            local function draw_centered(text, y, color)
                if text == "" then return end
                local safe = string.gsub(text, "%%", "%%%%")
                local w = imgui.calc_text_size(safe).x
                local x = cx - (w / 2)
                for dx = -outline_thick, outline_thick do
                    for dy = -outline_thick, outline_thick do
                        if dx ~= 0 or dy ~= 0 then
                            imgui.set_cursor_pos(Vector2f.new(x + dx, y + dy))
                            imgui.text_colored(safe, outline_color)
                        end
                    end
                end
                imgui.set_cursor_pos(Vector2f.new(x, y))
                imgui.text_colored(safe, color)
            end

            draw_centered(line1, line1_y, col1)
            draw_centered(line2, line2_y, col2)
            draw_centered(line3, line3_y, col3)

            if hud_overlay_font then imgui.pop_font() end
            imgui.end_window()
        end
        imgui.pop_style_color(1)
    end

    if show_trial_overlay and is_game_active then
        sf6_menu_state.active = true

        imgui.push_style_color(2, 0x00000000)
        imgui.push_style_color(5, 0x00000000)
        imgui.push_style_color(7, 0xAA220044)
        imgui.push_style_color(8, 0xCC6600AA)
		--WAEL1
		imgui.push_style_var(2, Vector2f.new(sw * 0.01, sh * 0.02))
		
        local target_w  = d2d_cfg.float_size.w * sw
        local target_h  = d2d_cfg.float_size.h * sh

        -- FORÇAGE DYNAMIQUE DE LA TAILLE ET POSITION
        local cond_size = (is_resizing or force_float_resize > 0) and 1 or (1 << 2)
        local cond_pos  = is_resizing and 1 or (1 << 3)

        if force_float_resize > 0 then force_float_resize = force_float_resize - 1 end

        imgui.set_next_window_size(Vector2f.new(target_w, target_h), cond_size)
        imgui.set_next_window_pos(Vector2f.new(d2d_cfg.float_pos.x * sw, d2d_cfg.float_pos.y * sh), cond_pos)

        if custom_ui_font then imgui.push_font(custom_ui_font) end

        local visible = imgui.begin_window("ComboTrialsFloating", true, 9)

        local pos = imgui.get_window_pos()
        local size = imgui.get_window_size()

        -- SAUVEGARDE BLOQUÉE PENDANT LE COOLDOWN (Empêche la corruption des coordonnées)
        if size.x > 0 and size.y > 0 and not is_resizing then
            local norm_x = pos.x / sw
            local norm_y = pos.y / sh
            local norm_w = size.x / sw
            local norm_h = size.y / sh

            if math.abs(norm_x - d2d_cfg.float_pos.x) > 0.001 or math.abs(norm_y - d2d_cfg.float_pos.y) > 0.001 or
                math.abs(norm_w - d2d_cfg.float_size.w) > 0.001 or math.abs(norm_h - d2d_cfg.float_size.h) > 0.001 then
                d2d_cfg.float_pos.x = norm_x
                d2d_cfg.float_pos.y = norm_y
                d2d_cfg.float_size.w = norm_w
                d2d_cfg.float_size.h = norm_h
                ui_dirty = true
            end
        end

        sf6_menu_state.x = pos.x
        sf6_menu_state.y = pos.y
        sf6_menu_state.w = size.x
        sf6_menu_state.h = size.y

        if visible then
            local w_width = size.x

            -- Calcul du seuil single-line
            local rec_btn_w_check = get_max_text_width({ "STOP & SAVE (" .. sc("L") .. ")", "CANCEL (" .. sc("U") .. ")", "RECORD P1 (" .. sc("L") .. ")", "RECORD P2 (" .. sc("D") .. ")" }, true)
            local play_btn_w_check = get_max_text_width({ "START TRIAL P1 (" .. sc("U") .. ")", "STOP TRIAL P1 (" .. sc("U") .. ")", "START TRIAL P2 (" .. sc("R") .. ")", "STOP TRIAL P2 (" .. sc("R") .. ")" }, true)
            local min_single_line_w = 200 + (rec_btn_w_check + play_btn_w_check) * 2 + 150 * (sh / 1080.0)

            if w_width >= min_single_line_w then
                -- SINGLE LINE : Pas de header, tout directement sur la zone sombre
                draw_single_line_content()
            else
                -- MODE NORMAL : Header + contenu classique
                -- Calculate exact actual width to synchronize header transition with UI layout
                local rec_btn_w_base = get_max_text_width({ "STOP & SAVE (" .. sc("L") .. ")", "CANCEL (" .. sc("U") .. ")", "RECORD P1 (" .. sc("L") .. ")", "RECORD P2 (" .. sc("D") .. ")", "RESET (" .. sc("L") .. ")", "DEMO (" .. sc("D") .. ")" }, true)
                local play_btn_w_base = get_max_text_width({ "START TRIAL P1 (" .. sc("U") .. ")", "STOP TRIAL P1 (" .. sc("U") .. ")", "SWITCH POS (" .. sc("R") .. ")" }, true)
                local absolute_btn_w = math.max(rec_btn_w_base, play_btn_w_base)
                local spacing_cols = 20 * (sh / 1080.0)

                local min_inline_w = 150 + (absolute_btn_w * 2) + (spacing_cols * 3)
                local mode_all_inline = w_width >= min_inline_w
                local mode_all_stacked = w_width < (absolute_btn_w * 1.5)
                local mode_col2_3_inline = not mode_all_inline and not mode_all_stacked

                local header_txt = "COMBO TRIALS : REPLAY & RECORDING SETTINGS"
                if mode_all_stacked then
                    header_txt = "COMBO TRIALS"
                elseif mode_col2_3_inline then
                    header_txt = "COMBO TRIALS SETTINGS"
                end

                local cb_width = 35 * (sh / 1080.0)
                local cb_x = w_width - cb_width / 4 - (sw * 0.015)

                local txt_size = imgui.calc_text_size(header_txt)
                local txt_w = txt_size.x
                local txt_h = txt_size.y

                local header_box_h = txt_h + (sh * 0.02)
                local title_x = (w_width - txt_w) / 2

                if (title_x + txt_w) > (cb_x - 15) then
                    title_x = (cb_x - txt_w) / 2
                    if title_x < 5 then title_x = 5 end
                end

                local items_y = (header_box_h - txt_h) / 2
                imgui.set_cursor_pos(Vector2f.new(title_x, items_y))
                imgui.text_colored(header_txt, 0xFFFFFFFF)

                imgui.set_cursor_pos(Vector2f.new(cb_x - 15, 0))
                imgui.push_style_color(7, 0xFF58002C)
                local mask_size = Vector2f.new(w_width, header_box_h)
                if not pcall(function() imgui.progress_bar(0.0, mask_size) end) then
                    pcall(function() imgui.progress_bar(0.0, mask_size, "") end)
                end
                imgui.pop_style_color(1)

                imgui.set_cursor_pos(Vector2f.new(cb_x, items_y))
                local changed, new_val = imgui.checkbox("##close_float", show_trial_overlay)
                if changed then show_trial_overlay = new_val end

                imgui.set_cursor_pos(Vector2f.new(0, header_box_h))
                imgui.spacing(); imgui.separator(); imgui.spacing()

                draw_combo_trials_content(true)
            end
        end

        imgui.end_window()

        if custom_ui_font then imgui.pop_font() end
        imgui.pop_style_color(4)
		-- WAEL2
		imgui.pop_style_var(1)
    else
        sf6_menu_state.active = false
    end

    if ui_dirty then
        ui_save_timer = ui_save_timer + 1
        if ui_save_timer > 60 then
            save_d2d_config()
            ui_dirty = false
            ui_save_timer = 0
        end
    end
end)

-- =========================================================
-- DESSIN DU MENU UI GLOBAL
-- =========================================================
local function draw_combo_trials_menu_ui()
    if _G.CurrentTrainerMode ~= 4 then return end
    if imgui.tree_node("TRAINING COMBO TRIALS") then
        local p_state = players[ui_state.viewed_player]
        imgui.spacing()

        -- ==========================================
        -- ONGLET 1 : COMBO TRIAL GLOBAL (Partagé P1/P2)
        -- ==========================================
        if styled_header("--- COMBO TRIALS (Files & Playback) ---", UI_THEME.hdr_info) then
            local changed, new_val = imgui.checkbox("Detacher en fenetre flottante", show_trial_overlay)
            if changed then show_trial_overlay = new_val end

            if not show_trial_overlay then
                imgui.separator()
                imgui.spacing()
                draw_combo_trials_content(false)
            else
                imgui.separator()
                imgui.text_colored("Cette section est actuellement detachee en fenetre flottante.", COLORS.DarkGrey)
                imgui.spacing()
            end
        end


        -- ==========================================
        -- ONGLET 2 : D2D VISUALISER
        -- ==========================================
        if styled_header("--- D2D VISUALIZER SETTINGS (Overlay) ---", UI_THEME.hdr_matrix) then
            local changed = false
            local c, v

            c, v = imgui.checkbox("Enable D2D Overlay", d2d_cfg.enabled); if c then
                d2d_cfg.enabled = v; changed = true
            end
            c, v = imgui.checkbox("Ignore Automatic Actions (Gray)", d2d_cfg.ignore_auto); if c then
                d2d_cfg.ignore_auto = v; changed = true
            end

            if d2d_cfg.ghost_filter_frames == nil then d2d_cfg.ghost_filter_frames = 4 end
            c, v = imgui.drag_int("Ghost Input Filter (Frames)", d2d_cfg.ghost_filter_frames, 1, 0, 10); if c then
                d2d_cfg.ghost_filter_frames = v; changed = true
            end
            if imgui.is_item_hovered() then
                imgui.set_tooltip(
                    "Ignores overlapping fast inputs that last less than X frames.\nHelps prevent '214+P' registering as a wrong move right before '214+PP'.\nSet to 0 to disable. Recommended: 3-4.")
            end


            c, v = imgui.checkbox("Show Combo Counter", d2d_cfg.show_combo_count); if c then
                d2d_cfg.show_combo_count = v; changed = true
            end
            imgui.spacing()

            imgui.text_colored("--- Live Log (During Record / Trial) ---", COLORS.Cyan)

            c, v = imgui.checkbox("Show Player 1##trial", d2d_cfg.show_p1); if c then d2d_cfg.show_p1 = v; changed = true end
            imgui.same_line()
            c, v = imgui.checkbox("Raw Input##trial_p1", d2d_cfg.raw_p1 or false); if c then d2d_cfg.raw_p1 = v; changed = true end
            imgui.same_line()
            c, v = imgui.checkbox("Mirror##trial_p1", d2d_cfg.mirror_p1 or false); if c then d2d_cfg.mirror_p1 = v; changed = true end
            if not d2d_cfg.raw_pos_p1 then d2d_cfg.raw_pos_p1 = { x = 0.050, y = 0.350 } end
            local tp1 = d2d_cfg.raw_p1 and d2d_cfg.raw_pos_p1 or d2d_cfg.pos_p1
            local tp1_lbl = d2d_cfg.raw_p1 and "Raw " or ""
            c, v = imgui.drag_float(tp1_lbl .. "P1 X##trial", tp1.x, 0.005, 0.0, 1.0); if c then tp1.x = v; changed = true end
            c, v = imgui.drag_float(tp1_lbl .. "P1 Y##trial", tp1.y, 0.005, 0.0, 1.0); if c then tp1.y = v; changed = true end
            if d2d_cfg.mirror_p1 then imgui.text_colored("  (Mirrored: X=" .. string.format("%.3f", 1.0 - tp1.x) .. ")", 0xFFAAAAAA) end

            c, v = imgui.checkbox("Show Player 2##trial", d2d_cfg.show_p2); if c then d2d_cfg.show_p2 = v; changed = true end
            imgui.same_line()
            c, v = imgui.checkbox("Raw Input##trial_p2", d2d_cfg.raw_p2 or false); if c then d2d_cfg.raw_p2 = v; changed = true end
            imgui.same_line()
            c, v = imgui.checkbox("Mirror##trial_p2", d2d_cfg.mirror_p2 or false); if c then d2d_cfg.mirror_p2 = v; changed = true end
            if not d2d_cfg.raw_pos_p2 then d2d_cfg.raw_pos_p2 = { x = 0.850, y = 0.350 } end
            local tp2 = d2d_cfg.raw_p2 and d2d_cfg.raw_pos_p2 or d2d_cfg.pos_p2
            local tp2_lbl = d2d_cfg.raw_p2 and "Raw " or ""
            c, v = imgui.drag_float(tp2_lbl .. "P2 X##trial", tp2.x, 0.005, 0.0, 1.0); if c then tp2.x = v; changed = true end
            c, v = imgui.drag_float(tp2_lbl .. "P2 Y##trial", tp2.y, 0.005, 0.0, 1.0); if c then tp2.y = v; changed = true end
            if d2d_cfg.mirror_p2 then imgui.text_colored("  (Mirrored: X=" .. string.format("%.3f", 1.0 - tp2.x) .. ")", 0xFFAAAAAA) end

            local t_raw_any = d2d_cfg.raw_p1 or d2d_cfg.raw_p2
            local t_max_key = t_raw_any and "raw_max_history" or "max_history"
            local t_max_lbl = t_raw_any and "Raw Max History##trial" or "Max History##trial"
            if not d2d_cfg.raw_max_history then d2d_cfg.raw_max_history = 19 end
            local c_max, v_max = imgui.drag_int(t_max_lbl, d2d_cfg[t_max_key] or 10, 1, 1, 30); if c_max then
                d2d_cfg[t_max_key] = v_max; changed = true
            end
            imgui.spacing()

            imgui.text_colored("--- Live Log (Idle / No Trial) ---", COLORS.Cyan)

            c, v = imgui.checkbox("Show Player 1##idle", d2d_cfg.idle_show_p1); if c then d2d_cfg.idle_show_p1 = v; changed = true end
            imgui.same_line()
            c, v = imgui.checkbox("Raw Input##idle_p1", d2d_cfg.idle_raw_p1 or false); if c then d2d_cfg.idle_raw_p1 = v; changed = true end
            imgui.same_line()
            c, v = imgui.checkbox("Mirror##idle_p1", d2d_cfg.idle_mirror_p1 or false); if c then d2d_cfg.idle_mirror_p1 = v; changed = true end
            if not d2d_cfg.idle_raw_p1 then
                c, v = imgui.drag_float("P1 X##idle", d2d_cfg.idle_pos_p1.x, 0.005, 0.0, 1.0); if c then d2d_cfg.idle_pos_p1.x = v; changed = true end
                c, v = imgui.drag_float("P1 Y##idle", d2d_cfg.idle_pos_p1.y, 0.005, 0.0, 1.0); if c then d2d_cfg.idle_pos_p1.y = v; changed = true end
                if d2d_cfg.idle_mirror_p1 then imgui.text_colored("  (Mirrored: X=" .. string.format("%.3f", 1.0 - d2d_cfg.idle_pos_p1.x) .. ")", 0xFFAAAAAA) end
            else
                imgui.text_colored("  (Position from Trial Raw P1)", 0xFFAAAAAA)
                if d2d_cfg.idle_mirror_p1 then
                    local src = d2d_cfg.raw_pos_p1 or d2d_cfg.pos_p1
                    imgui.text_colored("  (Mirrored: X=" .. string.format("%.3f", 1.0 - (src.x or 0.050)) .. ")", 0xFFAAAAAA)
                end
            end

            c, v = imgui.checkbox("Show Player 2##idle", d2d_cfg.idle_show_p2); if c then d2d_cfg.idle_show_p2 = v; changed = true end
            imgui.same_line()
            c, v = imgui.checkbox("Raw Input##idle_p2", d2d_cfg.idle_raw_p2 or false); if c then d2d_cfg.idle_raw_p2 = v; changed = true end
            imgui.same_line()
            c, v = imgui.checkbox("Mirror##idle_p2", d2d_cfg.idle_mirror_p2 or false); if c then d2d_cfg.idle_mirror_p2 = v; changed = true end
            if not d2d_cfg.idle_raw_p2 then
                c, v = imgui.drag_float("P2 X##idle", d2d_cfg.idle_pos_p2.x, 0.005, 0.0, 1.0); if c then d2d_cfg.idle_pos_p2.x = v; changed = true end
                c, v = imgui.drag_float("P2 Y##idle", d2d_cfg.idle_pos_p2.y, 0.005, 0.0, 1.0); if c then d2d_cfg.idle_pos_p2.y = v; changed = true end
                if d2d_cfg.idle_mirror_p2 then imgui.text_colored("  (Mirrored: X=" .. string.format("%.3f", 1.0 - d2d_cfg.idle_pos_p2.x) .. ")", 0xFFAAAAAA) end
            else
                imgui.text_colored("  (Position from Trial Raw P2)", 0xFFAAAAAA)
                if d2d_cfg.idle_mirror_p2 then
                    local src = d2d_cfg.raw_pos_p2 or d2d_cfg.pos_p2
                    imgui.text_colored("  (Mirrored: X=" .. string.format("%.3f", 1.0 - (src.x or 0.850)) .. ")", 0xFFAAAAAA)
                end
            end

            local i_raw_any = d2d_cfg.idle_raw_p1 or d2d_cfg.idle_raw_p2
            local i_max_key = i_raw_any and "idle_raw_max_history" or "idle_max_history"
            local i_max_lbl = i_raw_any and "Raw Max History##idle" or "Max History##idle"
            if not d2d_cfg.idle_raw_max_history then d2d_cfg.idle_raw_max_history = 19 end
            local c_imax, v_imax = imgui.drag_int(i_max_lbl, d2d_cfg[i_max_key] or 10, 1, 1, 30); if c_imax then
                d2d_cfg[i_max_key] = v_imax; changed = true
            end

            -- Raw Input Settings (shown only when at least one raw checkbox is active)
            local any_raw = (d2d_cfg.raw_p1 or d2d_cfg.raw_p2 or d2d_cfg.idle_raw_p1 or d2d_cfg.idle_raw_p2)
            if any_raw then
                imgui.spacing()
                imgui.text_colored("--- Raw Input Display Settings ---", COLORS.Cyan)
                if not d2d_cfg.raw then d2d_cfg.raw = {} end
                local rc = d2d_cfg.raw
                c, v = imgui.drag_float("Raw Icon Size", rc.icon_size or 0.030, 0.001, 0.01, 0.1, "%.3f"); if c then rc.icon_size = v; changed = true end
                c, v = imgui.drag_float("Raw Font Size", rc.font_size or 0.028, 0.001, 0.01, 0.1, "%.3f"); if c then rc.font_size = v; changed = true end
                c, v = imgui.drag_float("Raw Row Spacing", rc.spacing_y or 0.040, 0.001, 0.01, 0.1, "%.3f"); if c then rc.spacing_y = v; changed = true end
                c, v = imgui.drag_float("Raw Text Y Offset", rc.text_y_offset or 0.002, 0.0005, -0.02, 0.02, "%.4f"); if c then rc.text_y_offset = v; changed = true end
                c, v = imgui.drag_float("Raw Frame Col", rc.col_frame or 0.000, 0.005, -0.2, 0.5, "%.3f"); if c then rc.col_frame = v; changed = true end
                c, v = imgui.drag_float("Raw Dir Col", rc.col_dir or 0.050, 0.005, -0.2, 0.5, "%.3f"); if c then rc.col_dir = v; changed = true end
                c, v = imgui.drag_float("Raw Slot 1", rc.slot1 or 0.100, 0.005, 0.0, 0.5, "%.3f"); if c then rc.slot1 = v; changed = true end
                c, v = imgui.drag_float("Raw Slot 2", rc.slot2 or 0.140, 0.005, 0.0, 0.5, "%.3f"); if c then rc.slot2 = v; changed = true end
                c, v = imgui.drag_float("Raw Slot 3", rc.slot3 or 0.180, 0.005, 0.0, 0.5, "%.3f"); if c then rc.slot3 = v; changed = true end
                c, v = imgui.drag_float("Raw Slot 4", rc.slot4 or 0.220, 0.005, 0.0, 0.5, "%.3f"); if c then rc.slot4 = v; changed = true end
                c, v = imgui.drag_float("Raw Slot 5", rc.slot5 or 0.260, 0.005, 0.0, 0.5, "%.3f"); if c then rc.slot5 = v; changed = true end
                c, v = imgui.drag_float("Raw Slot 6", rc.slot6 or 0.300, 0.005, 0.0, 0.5, "%.3f"); if c then rc.slot6 = v; changed = true end
            end

            -- NEW: Trial Box Position & Height
            imgui.separator()

            imgui.text_colored("--- Trial Box Position & Height ---", COLORS.Cyan)
            c, v = imgui.drag_float("Trial P1 X", d2d_cfg.pos_trial_p1.x, 0.005, 0.0, 1.0); if c then
                d2d_cfg.pos_trial_p1.x = v; changed = true
            end
            c, v = imgui.drag_float("Trial P1 Y", d2d_cfg.pos_trial_p1.y, 0.005, 0.0, 1.0); if c then
                d2d_cfg.pos_trial_p1.y = v; changed = true
            end
            c, v = imgui.drag_float("Trial P2 X", d2d_cfg.pos_trial_p2.x, 0.005, 0.0, 1.0); if c then
                d2d_cfg.pos_trial_p2.x = v; changed = true
            end
            c, v = imgui.drag_float("Trial P2 Y", d2d_cfg.pos_trial_p2.y, 0.005, 0.0, 1.0); if c then
                d2d_cfg.pos_trial_p2.y = v; changed = true
            end
            c, v = imgui.drag_float("Trial Box Height", d2d_cfg.cartouche_height, 0.01, 0.1, 3.0); if c then
                d2d_cfg.cartouche_height = v; changed = true
            end
            c, v = imgui.drag_float("Trial Box Width", d2d_cfg.cartouche_width, 0.005, 0.1, 1.0); if c then
                d2d_cfg.cartouche_width = v; changed = true
            end
            c, v = imgui.drag_float("Cartouche Offset X", d2d_cfg.cartouche_offset_x, 0.001, -0.1, 0.1); if c then
                d2d_cfg.cartouche_offset_x = v; changed = true
            end
            c, v = imgui.drag_float("Cartouche Offset Y", d2d_cfg.cartouche_offset_y, 0.001, -0.1, 0.1); if c then
                d2d_cfg.cartouche_offset_y = v; changed = true
            end
            c, v = imgui.drag_int("Visible Trial Lines", d2d_cfg.trial_visible_steps, 1, 1, 30); if c then
                d2d_cfg.trial_visible_steps = v; changed = true
            end
            imgui.separator()


            c, v = imgui.drag_float("Trial Title Position X", d2d_cfg.pos_trial_header.x, 0.005, 0.0, 1.0); if c then
                d2d_cfg.pos_trial_header.x = v; changed = true
            end
            c, v = imgui.drag_float("Trial Title Position Y", d2d_cfg.pos_trial_header.y, 0.005, 0.0, 1.0); if c then
                d2d_cfg.pos_trial_header.y = v; changed = true
            end
            c, v = imgui.drag_float("Combo Stats Position X", d2d_cfg.pos_combo_stats.x, 0.005, 0.0, 1.0); if c then
                d2d_cfg.pos_combo_stats.x = v; changed = true
            end
            c, v = imgui.drag_float("Combo Stats Position Y", d2d_cfg.pos_combo_stats.y, 0.005, 0.0, 1.0); if c then
                d2d_cfg.pos_combo_stats.y = v; changed = true
            end
            imgui.separator()

            imgui.text_colored("HUD Overlay (Native Lines)", 0xFFFFAA00)
            c, v = imgui.checkbox("Show HUD Overlay", d2d_cfg.hud_show); if c then
                d2d_cfg.hud_show = v; changed = true
            end
            c, v = imgui.drag_float("HUD Global Y", d2d_cfg.hud_global_y, 0.001, -0.5, 0.0); if c then
                d2d_cfg.hud_global_y = v; changed = true
            end
            c, v = imgui.drag_float("HUD Line Spacing Y", d2d_cfg.hud_spacing_y, 0.001, 0.01, 0.1); if c then
                d2d_cfg.hud_spacing_y = v; changed = true
            end
            c, v = imgui.drag_float("HUD Font Size", d2d_cfg.hud_font_size, 0.5, 10, 60); if c then
                d2d_cfg.hud_font_size = v; changed = true; font_attempted = false
            end
            imgui.separator()
            c, v = imgui.drag_float("Icon Size", d2d_cfg.icon_size, 0.001, 0.01, 0.1); if c then
                d2d_cfg.icon_size = v; changed = true
            end
            c, v = imgui.drag_float("Special Icons Scale (DR/DI...)", d2d_cfg.special_icon_scale, 0.01, 1.0, 3.0, "x%.2f"); if c then
                d2d_cfg.special_icon_scale = v; changed = true
            end
            c, v = imgui.drag_float("Font Size", d2d_cfg.font_size, 0.001, 0.01, 0.1); if c then
                d2d_cfg.font_size = v; changed = true
            end
            c, v = imgui.drag_float("Spacing X", d2d_cfg.spacing_x, 0.001, 0.01, 0.1); if c then
                d2d_cfg.spacing_x = v; changed = true
            end
            c, v = imgui.drag_float("Spacing Y", d2d_cfg.spacing_y, 0.001, 0.01, 0.1); if c then
                d2d_cfg.spacing_y = v; changed = true
            end
            c, v = imgui.drag_float("Text Y Offset", d2d_cfg.text_y_offset, 0.001, -0.05, 0.05); if c then
                d2d_cfg.text_y_offset = v; changed = true
            end

            imgui.separator()
            imgui.text_colored("--- Animated Arrow ---", COLORS.Cyan)
            c, v = imgui.drag_float("Arrow Size", d2d_cfg.arrow_size, 0.001, 0.01, 0.1); if c then
                d2d_cfg.arrow_size = v; changed = true
            end
            c, v = imgui.drag_float("Arrow X Offset", d2d_cfg.offset_x_arrow, 0.001, -0.1, 0.1); if c then
                d2d_cfg.offset_x_arrow = v; changed = true
            end
            c, v = imgui.drag_float("Arrow Y Offset", d2d_cfg.offset_y_arrow, 0.001, -0.1, 0.1); if c then
                d2d_cfg.offset_y_arrow = v; changed = true
            end
            c, v = imgui.drag_int("Fail Display Time (frames)", d2d_cfg.fail_display_frames, 1, 0, 300); if c then
                d2d_cfg.fail_display_frames = v; changed = true
            end

            imgui.separator()

            if changed then save_d2d_config() end
            imgui.spacing()
        end

        -- ==========================================
        -- ONGLET 3 : MENU EXCEPTION EDITOR
        -- ==========================================
        if styled_header("--- EXCEPTION MANAGEMENT ---", UI_THEME.hdr_session) then
            -- L'ÉDITEUR N'APPARAÎT QUE SI ON CLIQUE SUR "GÉRER"
            if p_state.editing_id ~= -1 then
                imgui.text_colored("=== EXCEPTION SETTINGS : ID " .. p_state.editing_id .. " ===", COLORS.Cyan)
                imgui.text_colored("(Settings apply immediately in-game for testing)", COLORS.DarkGrey)
                imgui.spacing()

                local c1, n1 = imgui.checkbox("IGNORE (Hide from log)", p_state.edit_ignore)
                if c1 then
                    p_state.edit_ignore = n1; if n1 then p_state.edit_force = false end
                end

                imgui.same_line()
                local c2, n2 = imgui.checkbox("FORCE DISPLAY", p_state.edit_force)
                if c2 then
                    p_state.edit_force = n2; if n2 then p_state.edit_ignore = false end
                end

                local ch, nh = imgui.checkbox("HOLD BUTTON (Charge tracking)", p_state.edit_holdable)
                if ch then p_state.edit_holdable = nh end

                if p_state.edit_holdable then
                    imgui.indent(20)

                    if p_state.edit_hold_partial_check == nil then p_state.edit_hold_partial_check = true end
                    local chpc, nhpc = imgui.checkbox("Validate Partial during Trial", p_state.edit_hold_partial_check)
                    if chpc then p_state.edit_hold_partial_check = nhpc end
                    if imgui.is_item_hovered() then
                        imgui.set_tooltip("If unchecked, Instant vs Partial mismatches are tolerated.\nMaxed / PERFECT / FAKE / LATE are ALWAYS enforced.")
                    end

                    local changed_link, new_link = imgui.input_text("Absorb Next IDs (ex: 502,503)", p_state.edit_absorb_ids or "")
                    if changed_link then p_state.edit_absorb_ids = new_link end
                    imgui.spacing()

                    if p_state.profile_name == "Luke" then
                        imgui.text_colored("Luke Charge Profile (Leave empty for Auto Detect):", COLORS.Green)

                        local changed_min, new_min = imgui.input_text("Instant / Partial Limit (frames)",
                            p_state.edit_charge_min or "")
                        if changed_min then p_state.edit_charge_min = new_min end

                        local changed_pmin, new_pmin = imgui.input_text("Perfect Start (frames)",
                            p_state.edit_perfect_min or "")
                        if changed_pmin then p_state.edit_perfect_min = new_pmin end

                        local changed_pmax, new_pmax = imgui.input_text("Perfect End (frames)",
                            p_state.edit_perfect_max or "")
                        if changed_pmax then p_state.edit_perfect_max = new_pmax end
                    elseif p_state.profile_name == "JP" then
                        imgui.text_colored("JP Mode Active: Exceeding the threshold equals a FAKE.", COLORS.Blue)
                        local changed_min, new_min = imgui.input_text("Instant / Partial Limit (frames)",
                            p_state.edit_charge_min or "")
                        if changed_min then p_state.edit_charge_min = new_min end

                        local changed_max, new_max = imgui.input_text("FAKE Cancel Threshold (frames)",
                            p_state.edit_charge_max or "")
                        if changed_max then p_state.edit_charge_max = new_max end
                    else
                        imgui.text_colored("Charge Settings (Leave Max empty to auto-fill):", COLORS.Blue)
                        local changed_min, new_min = imgui.input_text("Instant / Partial Limit (frames)",
                            p_state.edit_charge_min)
                        if changed_min then p_state.edit_charge_min = new_min end

                        local changed_max, new_max = imgui.input_text("Maxed Threshold (frames)", p_state
                            .edit_charge_max)
                        if changed_max then p_state.edit_charge_max = new_max end
                    end

                    imgui.unindent(20)
                end

                imgui.spacing()
                local ct, nt = imgui.input_text("New Name (Leave empty to keep native)", p_state.edit_text)
                if ct then p_state.edit_text = nt end

                imgui.spacing()
                local cc, nc = imgui.checkbox("Apply to all characters (Common)", p_state.edit_is_common)
                if cc then p_state.edit_is_common = nc end

                imgui.text_colored("--- SPECIAL CONDITIONS ---", COLORS.Blue)
                local ci, ni = imgui.input_text("Ignore if previous Action ID...##ig_id_" .. p_state.editing_id,
                    p_state.edit_ignore_prev_id)
                if ci then p_state.edit_ignore_prev_id = ni end
                local cf, nf = imgui.input_text("... within the last X frames##ig_fr_" .. p_state.editing_id,
                    p_state.edit_ignore_prev_frames)
                if cf then p_state.edit_ignore_prev_frames = nf end
                imgui.spacing()

                imgui.spacing()
                if styled_button("APPLY AND SAVE", UI_THEME.btn_green) then
                    local id_s = tostring(p_state.editing_id)
                    local parsed_min = tonumber(p_state.edit_charge_min)
                    local parsed_max = tonumber(p_state.edit_charge_max)

                    local new_exc = {
                        ignore = p_state.edit_ignore,
                        force = p_state.edit_force,
                        is_holdable = p_state.edit_holdable,
                        hold_partial_check = p_state.edit_hold_partial_check,
                        absorb_ids = p_state.edit_absorb_ids,
                        charge_min = parsed_min,
                        charge_max = parsed_max,
                        perfect_min = tonumber(p_state.edit_perfect_min),
                        perfect_max = tonumber(p_state.edit_perfect_max),
                        override_name = (p_state.edit_text ~= "") and p_state.edit_text or nil,
                        ignore_prev_id = tonumber(p_state.edit_ignore_prev_id),
                        ignore_prev_frames = tonumber(p_state.edit_ignore_prev_frames) or 5
                    }

                    pcall(function() if fs and fs.create_dir then fs.create_dir("exceptions") end end)

                    if p_state.edit_is_common then
                        common_exceptions[id_s] = new_exc
                        p_state.exceptions[id_s] = nil

                        local s1 = json.dump_file("exceptions/Common.json", common_exceptions)
                        local s2 = json.dump_file(get_exc_filename(p_state.profile_name), p_state.exceptions)

                        if s1 and s2 then
                            exc_status = "✅ Common Exception SAVED."
                        else
                            exc_status = "❌ FATAL ERROR: Cannot write file!"
                        end
                    else
                        p_state.exceptions[id_s] = new_exc

                        local s1 = json.dump_file(get_exc_filename(p_state.profile_name), p_state.exceptions)

                        if s1 then
                            exc_status = "✅ Specific Exception SAVED."
                        else
                            exc_status = "❌ FATAL ERROR: Cannot write file!"
                        end
                    end

                    local new_log = {}
                    for _, l in ipairs(p_state.log) do
                        local keep = true
                        if l.id == p_state.editing_id then
                            if new_exc.ignore then
                                keep = false
                            elseif new_exc.force then
                                l.intentional = true
                            end

                            if new_exc.override_name then
                                l.motion = new_exc.override_name
                            else
                                l.motion = l.name
                            end

                            l.is_holdable = new_exc.is_holdable
                            l.charge_min = new_exc.charge_min
                            l.charge_max = new_exc.charge_max
                        end
                        if keep then table.insert(new_log, l) end
                    end
                    p_state.log = new_log

                    for _, step in ipairs(trial_state.sequence) do
                        if step.id == p_state.editing_id then
                            if new_exc.override_name then
                                step.motion = new_exc.override_name
                            else
                                step.motion = step.name or "Unknown"
                            end
                        end
                    end
                    p_state.editing_id = -1
                end

                imgui.same_line()
                if styled_button("CANCEL", UI_THEME.btn_red) then p_state.editing_id = -1 end
                imgui.separator()
            end

            -- LISTE DES EXCEPTIONS ENREGISTRÉES (AVEC LE TRI CROISSANT)
            if imgui.tree_node("Active Exceptions (" .. p_state.profile_name .. ")") then
                if exc_status ~= "" then imgui.text_colored(exc_status, COLORS.Yellow) end

                imgui.text_colored("--- SPECIFIC ---", COLORS.Green)
                local spec_keys = sort_ids(p_state.exceptions)

                if #spec_keys == 0 then
                    imgui.text_colored("None", COLORS.DarkGrey)
                else
                    for _, id_str in ipairs(spec_keys) do
                        local exc = p_state.exceptions[id_str]
                        local desc = ""
                        if exc.ignore then desc = desc .. "[IGNORE] " end
                        if exc.force then desc = desc .. "[FORCE] " end
                        if exc.is_holdable then
                            if p_state.profile_name == "Luke" then
                                local min_s = exc.perfect_min and (exc.perfect_min .. "f") or "Auto"
                                local max_s = exc.perfect_max and (exc.perfect_max .. "f") or "Auto"
                                desc = desc .. "[HOLD(Luke Perfect: " .. min_s .. "-" .. max_s .. ")] "
                            elseif p_state.profile_name == "JP" then
                                local min_s = exc.charge_min and (exc.charge_min .. "f") or "?"
                                local max_s = exc.charge_max and (exc.charge_max .. "f") or "?"
                                desc = desc .. "[HOLD(" .. min_s .. "-" .. max_s .. " FAKE)] "
                            else
                                local min_s = exc.charge_min and (exc.charge_min .. "f") or "?"
                                local max_s = exc.charge_max and (exc.charge_max .. "f") or "?"
                                desc = desc .. "[HOLD(" .. min_s .. "-" .. max_s .. ")] "
                            end
                        end
                        if exc.override_name then desc = desc .. "[NAME: " .. exc.override_name .. "] " end
                        if exc.ignore_prev_id then
                            desc = desc ..
                                "[IGN IF ID " .. exc.ignore_prev_id .. " < " .. (exc.ignore_prev_frames or 5) .. "f]"
                        end

                        imgui.text("ID " .. id_str .. " -> " .. desc)
                        imgui.same_line(450)
                        if styled_button("Edit##spec_" .. id_str, UI_THEME.btn_neutral) then
                            p_state.editing_id = tonumber(id_str)
                            p_state.edit_is_common = false
                            p_state.edit_ignore = exc.ignore or false
                            p_state.edit_force = exc.force or false
                            p_state.edit_holdable = exc.is_holdable or false
                            p_state.edit_hold_partial_check = (exc.hold_partial_check ~= false)
                            p_state.edit_absorb_ids = exc.absorb_ids or ""
                            p_state.edit_charge_min = exc.charge_min and tostring(exc.charge_min) or ""
                            p_state.edit_charge_max = exc.charge_max and tostring(exc.charge_max) or ""
                            p_state.edit_perfect_min = exc.perfect_min and tostring(exc.perfect_min) or ""
                            p_state.edit_perfect_max = exc.perfect_max and tostring(exc.perfect_max) or ""
                            p_state.edit_text = exc.override_name or ""
                            p_state.edit_ignore_prev_id = exc.ignore_prev_id and tostring(exc.ignore_prev_id) or ""
                            p_state.edit_ignore_prev_frames = exc.ignore_prev_frames and tostring(exc.ignore_prev_frames) or
                                "5"
                        end
                        imgui.same_line()
                        if styled_button("Delete##delspec_" .. id_str, UI_THEME.btn_red) then
                            p_state.exceptions[id_str] = nil
                            pcall(function() if fs and fs.create_dir then fs.create_dir("exceptions") end end)
                            json.dump_file(get_exc_filename(p_state.profile_name), p_state.exceptions)
                            exc_status = "🗑️ Specific Exception deleted from disk."
                        end
                    end
                end

                imgui.spacing()
                imgui.text_colored("--- COMMON ---", COLORS.Cyan)
                local com_keys = sort_ids(common_exceptions)

                if #com_keys == 0 then
                    imgui.text_colored("None", COLORS.DarkGrey)
                else
                    for _, id_str in ipairs(com_keys) do
                        local exc = common_exceptions[id_str]
                        local desc = ""
                        if exc.ignore then desc = desc .. "[IGNORE] " end
                        if exc.force then desc = desc .. "[FORCE] " end
                        if exc.is_holdable then
                            local min_s = exc.charge_min and (exc.charge_min .. "f") or "?"
                            local max_s = exc.charge_max and (exc.charge_max .. "f") or "?"
                            desc = desc .. "[HOLD(" .. min_s .. "-" .. max_s .. ")] "
                        end
                        if exc.override_name then desc = desc .. "[NAME: " .. exc.override_name .. "]" end

                        imgui.text("ID " .. id_str .. " -> " .. desc)
                        imgui.same_line(450)
                        if styled_button("Edit##com_" .. id_str, UI_THEME.btn_neutral) then
                            p_state.editing_id = tonumber(id_str)
                            p_state.edit_is_common = true
                            p_state.edit_ignore = exc.ignore or false
                            p_state.edit_force = exc.force or false
                            p_state.edit_holdable = exc.is_holdable or false
                            p_state.edit_hold_partial_check = (exc.hold_partial_check ~= false)
                            p_state.edit_absorb_ids = exc.absorb_ids or ""
                            p_state.edit_charge_min = exc.charge_min and tostring(exc.charge_min) or ""
                            p_state.edit_charge_max = exc.charge_max and tostring(exc.charge_max) or ""
                            p_state.edit_perfect_min = exc.perfect_min and tostring(exc.perfect_min) or ""
                            p_state.edit_perfect_max = exc.perfect_max and tostring(exc.perfect_max) or ""
                            p_state.edit_text = exc.override_name or ""
                            p_state.edit_ignore_prev_id = exc.ignore_prev_id and tostring(exc.ignore_prev_id) or ""
                            p_state.edit_ignore_prev_frames = exc.ignore_prev_frames and tostring(exc.ignore_prev_frames) or
                                "5"
                        end
                        imgui.same_line()
                        if styled_button("Delete##delcom_" .. id_str, UI_THEME.btn_red) then
                            common_exceptions[id_str] = nil
                            pcall(function() if fs and fs.create_dir then fs.create_dir("exceptions") end end)
                            json.dump_file("exceptions/Common.json", common_exceptions)
                            exc_status = "🗑️ Common Exception deleted from disk."
                        end
                    end
                end
                imgui.tree_pop()
            end

            imgui.spacing()
        end

        -- ==========================================
        -- ONGLET 4 : LIVE LOG
        -- ==========================================
        if styled_header("--- LIVE LOG : PLAYER " .. tostring(ui_state.viewed_player + 1) .. " ---", UI_THEME.hdr_rules) then
            -- PLAYER SELECTOR (Forces refresh on change)
            if styled_button(ui_state.viewed_player == 0 and "LOGGING P1 (" .. players[0].profile_name .. ")" or "WATCH LOG P1 (" .. players[0].profile_name .. ")", ui_state.viewed_player == 0 and UI_THEME.btn_green or UI_THEME.btn_neutral) then
                if ui_state.viewed_player ~= 0 then
                    ui_state.viewed_player = 0; refresh_combo_list()
                end
            end
            imgui.same_line()
            if styled_button(ui_state.viewed_player == 1 and "LOGGING P2 (" .. players[1].profile_name .. ")" or "WATCH LOG P2 (" .. players[1].profile_name .. ")", ui_state.viewed_player == 1 and UI_THEME.btn_green or UI_THEME.btn_neutral) then
                if ui_state.viewed_player ~= 1 then
                    ui_state.viewed_player = 1; refresh_combo_list()
                end
            end
            imgui.spacing()
            imgui.separator()
            imgui.spacing()

            local c_deep, n_deep = imgui.checkbox("Enable 'Deep Action Scanner' (Adds C# DNA to each hit in JSON Dump)",
                p_state.enable_deep_logging)
            if c_deep then p_state.enable_deep_logging = n_deep end
            if p_state.enable_deep_logging then
                imgui.text_colored("   /!\\ Deep Scan analyzes code massively.", COLORS.Blue)
                imgui.text_colored("       Use only for research sessions.", COLORS.Blue)
            end

            imgui.spacing()
            if styled_button("Clear Log", UI_THEME.btn_red) then p_state.log = {} end
            imgui.same_line()
            if styled_button("Dump Log to JSON", UI_THEME.btn_neutral) then
                json.dump_file("Final_Log_Dump_P" .. tostring(ui_state.viewed_player + 1) .. ".json", p_state.log)
                dump_status = "Full log saved."
            end

            if dump_status ~= "" then imgui.text_colored(dump_status, COLORS.Green) end
            imgui.spacing(); imgui.separator(); imgui.spacing()

            if #p_state.log == 0 then
                imgui.text_colored("Waiting for actions...", COLORS.Blue)
            else
                for i, log in ipairs(p_state.log) do
                    if log.intentional then
                        local charge_str = ""
                        if log.is_holdable then
                            local trans_str = ""
                            if not log.is_holding and log.transition_id and log.transition_id > 50 then
                                trans_str =
                                    " -> ID " .. log.transition_id
                            end
                            charge_str = string.format(" (%d%s)", log.hold_frames, trans_str)
                        end

                        local combo_str = ""
                        if log.combo_count ~= nil then
                            combo_str = string.format(" [Combo: %d]", log.combo_count)
                        end

                        -- Les mots clés traduits : VRAI INPUT -> REAL INPUT, Réel -> Raw
                        local left_col = string.format("REAL INPUT  | %s (ID: %d)%s%s", log.motion, log.id, charge_str,
                            combo_str)
                        local right_col = string.format("Raw: %s (%s)", log.real_input, log.frame_diff)

                        local line_color = COLORS.White
                        if log.is_holdable then
                            local live_status = log.charge_status or ""
                            -- Calcul en Temps Réel pour l'UI Texte
                            if log.is_holding then
                                if log.charge_min and log.hold_frames <= log.charge_min then
                                    live_status = "Instant"
                                elseif log.charge_max and log.hold_frames >= log.charge_max then
                                    live_status = "Maxed"
                                else
                                    live_status = "Partial"
                                end
                            end

                            if live_status:match("Partial") then
                                line_color = COLORS.Orange
                            elseif live_status:match("Maxed") or live_status == "PERFECT!" or live_status == "FAKE" then
                                line_color = COLORS.Yellow
                            end
                        end

                        imgui.text_colored(left_col, line_color)

                        imgui.same_line(450)
                        imgui.text_colored("-> " .. right_col, COLORS.Cyan)
                    else
                        if log.is_ignored then
                            local line = string.format("IGNORED   | %s (ID: %d) %s", log.name, log.id, log.ignore_reason)
                            imgui.text_colored(line, COLORS.DarkGrey)
                        else
                            local line = string.format("AUTOMATIC | %s (ID: %d)", log.name, log.id)
                            imgui.text_colored(line, COLORS.DarkGrey)
                        end
                    end

                    imgui.same_line(750)
                    if styled_button("Manage##edit_" .. log.id .. "_" .. i, UI_THEME.btn_orange) then
                        p_state.editing_id = log.id
                        local exc_char = p_state.exceptions[tostring(log.id)]
                        local exc_com = common_exceptions[tostring(log.id)]
                        local exc = exc_char or exc_com

                        if exc_char then
                            p_state.edit_is_common = false
                        elseif exc_com then
                            p_state.edit_is_common = true
                        else
                            p_state.edit_is_common = false
                        end

                        if exc then
                            p_state.edit_ignore = exc.ignore or false
                            p_state.edit_force = exc.force or false
                            p_state.edit_holdable = exc.is_holdable or false
                            p_state.edit_hold_partial_check = (exc.hold_partial_check ~= false)
                            p_state.edit_absorb_ids = exc.absorb_ids or ""
                            p_state.edit_charge_min = exc.charge_min and tostring(exc.charge_min) or ""
                            p_state.edit_charge_max = exc.charge_max and tostring(exc.charge_max) or ""
                            p_state.edit_text = exc.override_name or ""
                            p_state.edit_ignore_prev_id = exc.ignore_prev_id and tostring(exc.ignore_prev_id) or ""
                            p_state.edit_ignore_prev_frames = exc.ignore_prev_frames and tostring(exc.ignore_prev_frames) or
                                "5"
                        else
                            p_state.edit_ignore = false
                            p_state.edit_force = false
                            p_state.edit_holdable = false
                            p_state.edit_hold_partial_check = true
                            p_state.edit_absorb_ids = ""
                            p_state.edit_charge_min = ""
                            p_state.edit_charge_max = ""
                            p_state.edit_text = log.motion or log.name
                            p_state.edit_ignore_prev_id = ""
                            p_state.edit_ignore_prev_frames = "5"
                        end
                    end
                end
            end
        end

        imgui.spacing()

        -- ==========================================
        -- ONGLET 5 : DEBUG & SYSTEM INFO
        -- ==========================================
        if styled_header("--- DEBUG & SYSTEM INFO ---", UI_THEME.hdr_rules) then
            imgui.text_colored("Detected Native Game Resolution:", 0xFF00FFFF)
            local res_w = ctx.cached_sw or last_sw or 0
            local res_h = ctx.cached_sh or last_sh or 0
            imgui.indent(20)
            imgui.text(string.format("%d px width  x  %d px height", res_w, res_h))
            imgui.unindent(20)
            imgui.spacing()

            -- LIVE POSITIONS
            imgui.text_colored("Live Positions (raw sfix):", 0xFF00FFFF)
            pcall(function()
                local gB = sdk.find_type_definition("gBattle")
                if not gB then return end
                local sP = gB:get_field("Player"):get_data(nil)
                if not sP or not sP.mcPlayer then return end
                local p1x = sP.mcPlayer[0].pos.x.v or 0
                local p2x = sP.mcPlayer[1].pos.x.v or 0
                imgui.indent(20)
                imgui.text(string.format("P1: %d  (%.2f cm)", p1x, p1x / 65536.0))
                imgui.text(string.format("P2: %d  (%.2f cm)", p2x, p2x / 65536.0))
                imgui.unindent(20)
            end)
            imgui.text_colored("Saved Trial Positions:", 0xFF00FFFF)
            imgui.indent(20)
            imgui.text(string.format("start_pos_p1_raw: %s", tostring(trial_state.start_pos_p1_raw)))
            imgui.text(string.format("start_pos_p2_raw: %s", tostring(trial_state.start_pos_p2_raw)))
            imgui.text(string.format("exact_inject_r1: %s", tostring(trial_state.exact_inject_r1)))
            imgui.text(string.format("exact_inject_r2: %s", tostring(trial_state.exact_inject_r2)))
            imgui.text(string.format("pending_exact_pos: %s", tostring(trial_state.pending_exact_pos)))
            imgui.text(string.format("forced_position_idx: %d", d2d_cfg.forced_position_idx))
            imgui.unindent(20)
            imgui.spacing()

            -- BOUTON DE DUMP DE FAIL (Apparaît uniquement si un fail est en mémoire)
            --[[
            if ctx.trial_state and ctx.trial_state.last_fail_dump then
                imgui.separator()
                imgui.spacing()
                imgui.text_colored("Dernier Trial Echoue !", COLORS.Red)
                if styled_button("Dump Fail Data to JSON", UI_THEME.btn_red) then
                    if ctx.dump_last_fail then
                        local path = ctx.dump_last_fail()
                        if path then
                            print("[ComboTrials] Fail dump saved to: " .. path)
                        end
                    end
                end
                imgui.spacing()
            end
            ]]--
        end

        -- IMPORTANT : Closes the tree_node and the if block
        imgui.tree_pop()
    end
end

-- Register in floating window hub + keep standard menu entry
if _G.FloatingScriptUI then
    _G.FloatingScriptUI.register("TRAINING COMBO TRIALS", draw_combo_trials_menu_ui)
end
re.on_draw_ui(draw_combo_trials_menu_ui)

-- =========================================================
-- Public API
-- =========================================================
function M.init(shared_ctx)
    ctx = shared_ctx
    d2d_cfg = ctx.d2d_cfg
    trial_state = ctx.trial_state
    players = ctx.players
    file_system = ctx.file_system
    common_exceptions = ctx.common_exceptions
    sf6_menu_state = ctx.sf6_menu_state
    load_and_start_trial = ctx.load_and_start_trial
    start_recording = ctx.start_recording
    stop_recording_and_save = ctx.stop_recording_and_save
    cancel_recording = ctx.cancel_recording
    refresh_combo_list = ctx.refresh_combo_list
    restore_trial_vital = ctx.restore_trial_vital
    save_d2d_config = ctx.save_d2d_config
    get_exc_filename = ctx.get_exc_filename
    ui_state = ctx.ui_state
end

return M