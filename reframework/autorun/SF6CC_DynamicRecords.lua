-- SF6CC_DynamicRecords.lua
-- Independent ImGui panel for SF6 native recording slots and reversal settings.

local imgui = imgui
local re = re
local d2d = d2d

local DynamicRecords = require("func/DynamicRecords")

local options = {
    only_import_valid = false,
    clear_empty_slots = true,
    reject_fighter_mismatch = true,
    force_apply_after_import = true,
}

local status_msg = "Ready."
local status_ok = true
local last_slots = nil
local last_snapshot = nil
local last_fighter_id = nil
local config_entries = {}
local config_labels = { "（暂无配置）" }
local selected_config_index = 1
local config_list_loaded = false

local function set_status(ok, msg)
    status_ok = ok == true
    status_msg = tostring(msg or "")
end

local function selected_config()
    if #config_entries == 0 then return nil end
    return config_entries[selected_config_index]
end

local function single_line_title(value)
    local text = tostring(value or ""):gsub("[\r\n\t]+", " ")
    return text:match("^%s*(.-)%s*$") or ""
end

local function config_title(entry)
    if not entry then return "未命名配置" end
    local metadata = DynamicRecords.read_config_metadata(entry.path)
    if type(metadata) == "table" then
        local title = single_line_title(metadata.title)
        if title ~= "" then return title end
        local description = single_line_title(metadata.description)
        if description ~= "" then return description end
        local fighter_name = tostring(metadata.fighter_name or "")
        if fighter_name ~= "" then return fighter_name .. " 训练配置" end
    end
    return "未命名配置"
end

local function refresh_config_list(select_path, silent)
    local ok, entries_or_err = pcall(DynamicRecords.list_configs)
    if not ok then
        if not silent then set_status(false, "配置列表刷新失败: " .. tostring(entries_or_err)) end
        return false
    end

    config_entries = entries_or_err or {}
    config_labels = {}
    selected_config_index = 1
    for index, entry in ipairs(config_entries) do
        local prefix = entry.legacy and "[旧目录] " or ""
        config_labels[index] = prefix .. config_title(entry)
            .. "##SF6CCConfigEntry" .. tostring(index)
        if select_path and entry.path == select_path then selected_config_index = index end
    end
    if #config_labels == 0 then config_labels[1] = "（暂无配置）" end
    config_list_loaded = true
    if not silent then
        set_status(true, "配置列表已刷新，共识别 " .. tostring(#config_entries) .. " 个 JSON")
    end
    return true
end

local function refresh_slots(silent)
    local ok, slots_or_err, err_or_nil, snapshot_or_nil = pcall(function()
        local slots, err, snapshot = DynamicRecords.get_slot_summaries()
        return slots, err, snapshot
    end)

    if not ok then
        set_status(false, "Refresh failed: " .. tostring(slots_or_err))
        return false
    end

    local slots = slots_or_err
    local err = err_or_nil
    local snapshot = snapshot_or_nil
    if not slots then
        last_slots = nil
        last_snapshot = nil
        set_status(false, "Refresh failed: " .. tostring(err))
        return false
    end

    last_slots = slots
    last_snapshot = snapshot
    if not silent then set_status(true, "Refreshed") end
    return true
end

local function run_action(label, fn, on_success)
    local ok, success, msg, path, payload = pcall(fn)
    if not ok then
        set_status(false, label .. " crashed: " .. tostring(success))
        return
    end
    set_status(success == true, msg)
    if success == true and on_success then
        local callback_ok, callback_err = pcall(on_success, path, payload)
        if not callback_ok then
            set_status(false, label .. " succeeded, UI refresh failed: " .. tostring(callback_err))
        end
    end
    refresh_slots(true)
end

local function import_selected_config()
    local entry = selected_config()
    if not entry then
        set_status(false, "请先导出或选择一个配置")
        return
    end
    run_action("Import", function()
        return DynamicRecords.import_from_file(entry.path, options)
    end)
end

local function status_color()
    if status_ok then return 0xFF00FF00 end
    return 0xFF0000FF
end

local function draw_paths()
    local paths = DynamicRecords.paths_for_display()
    imgui.text("Configs: " .. paths.configs)
    imgui.text("Backups: " .. paths.backups)
    imgui.text("Editor: " .. tostring(paths.editor or ""))
    imgui.text("Legacy: " .. paths.legacy)
    imgui.text("Config glob matches: " .. tostring(paths.config_glob_count or 0))
    imgui.text("Config glob: " .. tostring(paths.config_glob or ""))
end

local function draw_config_selector()
    if not config_list_loaded then refresh_config_list(nil, true) end

    imgui.text("训练配置")
    local changed, new_index = imgui.combo(
        "##SF6CCTrainingConfigList", selected_config_index, config_labels)
    if changed and #config_entries > 0 then
        selected_config_index = new_index
        import_selected_config()
    end
    imgui.same_line()
    if imgui.small_button("刷新列表") then refresh_config_list(nil, false) end

    local entry = selected_config()
    if entry then
        imgui.text_colored(tostring(entry.filename or entry.path or ""), 0xFF888888)
    end
end

local function draw_primary_actions()
    if imgui.button("导出配置") then
        run_action("Export", function()
            return DynamicRecords.export_new()
        end, function(path)
            refresh_config_list(path, true)
        end)
    end
    imgui.same_line()

    if imgui.button("导入配置") then
        import_selected_config()
    end
    imgui.same_line()

    if imgui.button("清空") then
        run_action("Clear", function()
            return DynamicRecords.clear_current_configuration()
        end, function()
            refresh_slots(true)
        end)
    end
end

local function draw_debug_actions()
    if imgui.button("刷新") then
        refresh_slots(false)
    end
    imgui.same_line()

    if imgui.button("备份当前完整配置") then
        run_action("Backup", function()
            return DynamicRecords.backup_current()
        end)
    end
    imgui.same_line()

    if imgui.button("恢复最近备份") then
        run_action("Restore", function()
            return DynamicRecords.restore_latest_backup(options)
        end)
    end
end

local function draw_options()
    local changed

    changed, options.only_import_valid = imgui.checkbox("只导入有效槽", options.only_import_valid)
    imgui.same_line()
    changed, options.clear_empty_slots = imgui.checkbox("清空空槽", options.clear_empty_slots)
    imgui.same_line()
    changed, options.reject_fighter_mismatch = imgui.checkbox("角色 ID 不匹配时拒绝", options.reject_fighter_mismatch)
    imgui.same_line()
    changed, options.force_apply_after_import = imgui.checkbox("导入后 ForceApply", options.force_apply_after_import)
end

local function draw_slots_table(slots)
    if not slots then
        imgui.text_colored("没有可显示的槽位数据。", 0xFF888888)
        return
    end

    if imgui.begin_table("SF6CCDynamicRecordsSlots", 6, 1 << 0) then
        imgui.table_setup_column("槽", 0, 30)
        imgui.table_setup_column("有效", 0, 50)
        imgui.table_setup_column("启用", 0, 50)
        imgui.table_setup_column("帧数", 0, 60)
        imgui.table_setup_column("权重", 0, 60)
        imgui.table_setup_column("输入帧", 0, 70)
        imgui.table_headers_row()

        for _, slot in ipairs(slots) do
            imgui.table_next_row()

            imgui.table_next_column()
            imgui.text(tostring(slot.slot or "-"))

            imgui.table_next_column()
            imgui.text_colored(slot.is_valid and "yes" or "no", slot.is_valid and 0xFF00FF00 or 0xFF888888)

            imgui.table_next_column()
            imgui.text_colored(slot.is_active and "on" or "off", slot.is_active and 0xFF00FF00 or 0xFF888888)

            imgui.table_next_column()
            imgui.text(tostring(slot.frame or 0))

            imgui.table_next_column()
            imgui.text(tostring(slot.weight or 0))

            imgui.table_next_column()
            imgui.text(tostring(slot.input_num or 0))
        end

        imgui.end_table()
    end
end

local function draw_reversal_table(reversals)
    if type(reversals) ~= "table" then
        imgui.text_colored("没有可显示的反击设置。", 0xFF888888)
        return
    end

    local groups = {
        { key = "down", label = "倒地反击" },
        { key = "guard", label = "格挡反击" },
        { key = "damage", label = "受击反击" },
    }

    for _, group in ipairs(groups) do
        if imgui.tree_node(group.label .. "##SF6CCReversalDebug" .. group.key) then
            local entries = reversals[group.key]
            if type(entries) == "table" then
                for _, entry in ipairs(entries) do
                    imgui.text("槽 " .. tostring(entry.slot or "-")
                        .. " | active=" .. tostring(entry.active)
                        .. " | type=" .. tostring(entry.type)
                        .. " | skill=" .. tostring(entry.skill_index)
                        .. " | delay=" .. tostring(entry.delay_frame)
                        .. " | count=" .. tostring(entry.count)
                        .. " | meaty=" .. tostring(entry.meaty_frame))
                end
            else
                imgui.text_colored("组数据不可用。", 0xFF888888)
            end
            imgui.tree_pop()
        end
    end
end

local function draw_debug_panel()
    local ctx = DynamicRecords.get_context()
    local fighter_id = ctx.fighter_id
    local fighter_name = ctx.fighter_name or ""
    local source_player = ctx.source_player or "P2"

    if fighter_id ~= last_fighter_id then
        last_fighter_id = fighter_id
        last_slots = nil
        last_snapshot = nil
    end

    imgui.text("当前角色: " .. tostring(fighter_name)
        .. " / fighter_id=" .. tostring(fighter_id or "?")
        .. " / source=" .. tostring(source_player))

    if ctx.error and fighter_id == nil then
        imgui.text_colored("Context: " .. tostring(ctx.error), 0xFF0000FF)
    end

    draw_debug_actions()
    draw_options()
    imgui.separator()
    draw_paths()
    imgui.separator()

    if not last_slots then refresh_slots(true) end
    draw_slots_table(last_slots)

    imgui.separator()
    draw_reversal_table(last_snapshot and last_snapshot.reversals or nil)

    imgui.separator()
    imgui.text("状态: ")
    imgui.same_line()
    imgui.text_colored(status_msg, status_color())
end

local function draw_panel()
    local ctx = DynamicRecords.get_context()
    local fighter_name = tostring(ctx.fighter_name or "未知")
    imgui.text("当前角色 [" .. fighter_name .. "]")

    draw_config_selector()
    draw_primary_actions()

    if imgui.tree_node("高级 / 调试") then
        draw_debug_panel()
        imgui.tree_pop()
    end
    imgui.text_colored("提醒：具体配置请在网站上配置和保存", 0xFF888888)
end

re.on_draw_ui(function()
    if imgui.tree_node("小吞MOD: 训练配置管理") then
        draw_panel()
        imgui.tree_pop()
    end
end)

-- Native training menu annotations. Text is loaded from the imported JSON and
-- is hidden automatically when its recorded input/action binding goes stale.
local overlay_mode = nil
local overlay_state = nil
local overlay_frame = 0

local RECORD_OVERLAY = {
    base_x_pct = 0.325,
    base_y_pct = 0.257,
    step_y_pct = 0.0555,
    box_w_pct = 0.155,
    box_h_pct = 0.041,
}

local REVERSAL_OVERLAY = {
    base_x_pct = 0.288,
    base_y_pct = 0.201,
    step_y_pct = 0.0555,
    box_w_pct = 0.155,
    box_h_pct = 0.041,
}

local function is_native_training_menu_open()
    local pause_manager = sdk.get_managed_singleton("app.PauseManager")
    if not pause_manager then return false end
    local pause_bit = pause_manager:get_field("_CurrentPauseTypeBit")
    return pause_bit ~= nil and pause_bit ~= 64 and pause_bit ~= 2112
end

local function detect_native_training_page()
    if not is_native_training_menu_open() then return nil end
    local manager = sdk.get_managed_singleton("app.training.TrainingManager")
    if not manager then return nil end
    local parent = manager:call("get_CurrentParentData")
    if not parent then return nil end
    local func_type = tonumber(parent:get_field("_FuncType"))
    if func_type == 4 then
        local record_func = manager:call("get_RecordFunc")
        local t_data = record_func and record_func:get_field("_tData") or nil
        local record_setting = t_data and t_data:get_field("RecordSetting") or nil
        local record_type = record_setting and tonumber(record_setting:get_field("RecordType")) or nil
        if record_type == 1 then return "record" end
        return nil
    end
    if func_type == 5 then return "reversal" end
    return nil
end

re.on_frame(function()
    overlay_mode = nil
    local ok, mode = pcall(detect_native_training_page)
    if ok then overlay_mode = mode end
    if not overlay_mode then
        overlay_state = nil
        return
    end

    overlay_frame = overlay_frame + 1
    if overlay_state and overlay_frame % 6 ~= 0 then return end
    local state_ok, state = pcall(DynamicRecords.get_overlay_state)
    overlay_state = state_ok and state or nil
end)

if d2d and d2d.register then
    local overlay_font = nil
    local overlay_font_px = 0
    local shrink_fonts = {}

    local function d2d_init()
        overlay_font = d2d.Font.new("msyhbd.ttc", 22)
        overlay_font_px = 22
    end

    local function get_font(pixel_size)
        if pixel_size < 10 then pixel_size = 10 end
        if not overlay_font or math.abs(pixel_size - overlay_font_px) > 1 then
            overlay_font = d2d.Font.new("msyhbd.ttc", pixel_size)
            overlay_font_px = pixel_size
            shrink_fonts = {}
        end
        return overlay_font
    end

    local function draw_annotation_rows(config, labels, count)
        if type(labels) ~= "table" then return end
        local screen_w, screen_h = d2d.surface_size()
        if not screen_w or screen_w <= 0 or not screen_h or screen_h <= 0 then return end

        local pixel_size = math.floor(screen_h * 0.020)
        local base_font = get_font(pixel_size)
        if not base_font then return end
        local x = screen_w * config.base_x_pct
        local y0 = screen_h * config.base_y_pct
        local step = screen_h * config.step_y_pct
        local box_w = screen_w * config.box_w_pct
        local box_h = screen_h * config.box_h_pct

        for index = 1, count do
            local label = tostring(labels[index] or "")
            if label ~= "" then
                local font = base_font
                local text_w, text_h = font:measure(label)
                if text_w > box_w - 8 then
                    local smaller = math.max(10, math.floor(pixel_size * (box_w - 8) / text_w))
                    if not shrink_fonts[smaller] then
                        shrink_fonts[smaller] = d2d.Font.new("msyhbd.ttc", smaller)
                    end
                    font = shrink_fonts[smaller]
                    _, text_h = font:measure(label)
                end
                -- The native row text sits slightly below the geometric center.
                -- 5 / 1080 keeps the corrected row alignment proportional at
                -- other resolutions instead of hardcoding a pixel offset.
                local y = y0 + (index - 1) * step + (box_h - text_h) / 2
                    - screen_h * 0.005 + screen_h * (5 / 1080)
                d2d.text(font, label, x + 4, y, 0xFFC9C7C7)
            end
        end
    end

    local function d2d_draw()
        if not overlay_mode or type(overlay_state) ~= "table" then return end
        if overlay_mode == "record" then
            draw_annotation_rows(RECORD_OVERLAY, overlay_state.record_slots, 8)
            return
        end

        local type_to_group = { [0] = "down", [1] = "guard", [2] = "damage" }
        local group = type_to_group[tonumber(overlay_state.reversal_type)]
        if group then
            draw_annotation_rows(
                REVERSAL_OVERLAY,
                overlay_state.reversals and overlay_state.reversals[group],
                10)
        end
    end

    d2d.register(d2d_init, d2d_draw)
end
