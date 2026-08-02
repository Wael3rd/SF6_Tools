-- =========================================================
-- SF6_ImGuiCanvasProbe.lua
-- Validation probe for the ImGui canvas backend (phase 1 of the
-- pure-ImGui adoption). Answers, per dinput8 build:
--   1. Which ImGui Lua APIs exist on this runtime?
--   2. Does the geometry/text canvas actually draw?
--   3. Is the reframework-imgui-texture native plugin present?
-- Draws a small test pattern (top-left) only while enabled from the
-- REFramework menu. Zero per-frame cost when disabled.
-- =========================================================

local re = re
local imgui = imgui

local Canvas = require("func/ImGuiCanvas")

local enabled = false
local stats = { frames = 0, fill = 0, outline = 0, line = 0, text = 0, cjk = 0, image = 0 }
local test_font = nil
local test_font_cjk = nil
local test_image = nil

-- Static API surface report (computed once, cheap)
local api_report = nil
local function build_api_report()
    if api_report then return api_report end
    local function has(fn) return type(fn) == "function" and "YES" or "no" end
    api_report = {
        { "imgui.get_background_draw_list", has(imgui and imgui.get_background_draw_list) },
        { "imgui.get_window_draw_list",     has(imgui and imgui.get_window_draw_list) },
        { "imgui.get_display_size",         has(imgui and imgui.get_display_size) },
        { "imgui.load_font",                has(imgui and imgui.load_font) },
        { "imgui.calc_text_size",           has(imgui and imgui.calc_text_size) },
        { "imgui.push_font / pop_font",     has(imgui and imgui.push_font) .. " / " .. has(imgui and imgui.pop_font) },
        { "texture plugin (imgui-texture)", (type(texture) == "table" and type(texture.load) == "function") and "YES" or "no" },
    }
    return api_report
end

re.on_frame(function()
    if not enabled then return end
    if not Canvas.begin_frame() then return end
    stats.frames = stats.frames + 1

    local x, y = 40, 120
    if Canvas.fill_rect(x, y, 220, 90, 0xAA202030) then stats.fill = stats.fill + 1 end
    if Canvas.outline_rect(x, y, 220, 90, 2.0, 0xFF57A5FF) then stats.outline = stats.outline + 1 end
    if Canvas.line(x, y + 100, x + 220, y + 100, 3.0, 0xFF43D17C) then stats.line = stats.line + 1 end

    if test_font == nil then
        test_font = Canvas.Font.new("SF6_college.ttf", 22) or false
    end
    if test_font then
        if Canvas.text(test_font, "ImGui canvas OK (latin font)", x + 10, y + 10, 0xFFE8B44A) then
            stats.text = stats.text + 1
        end
    end

    -- CJK path: same glyphs but through the CJK-capable font file (the
    -- "????" with SF6_college is expected — it has no Chinese glyphs).
    if test_font_cjk == nil then
        test_font_cjk = Canvas.Font.new("NotoSansSC-Regular.otf", 22) or false
    end
    if test_font_cjk then
        if Canvas.text(test_font_cjk, "中文测试 OK (Noto Sans SC)", x + 10, y + 38, 0xFF7CD143) then
            stats.cjk = stats.cjk + 1
        end
    end

    -- Image path: expected to no-op without the native plugin (logs once).
    if test_image == nil then
        test_image = Canvas.Image.new("buttonsAndArrows/mp.png")
    end
    if Canvas.image(test_image, x + 10, y + 45, 32, 32) then stats.image = stats.image + 1 end
end)

re.on_draw_ui(function()
    if imgui.tree_node("IMGUI CANVAS PROBE") then
        imgui.text("Validates the pure-ImGui backend on THIS dinput8 build.")
        imgui.spacing()

        imgui.text("--- API surface ---")
        for _, row in ipairs(build_api_report()) do
            imgui.text(string.format("%-34s %s", row[1], row[2]))
        end
        imgui.spacing()

        local changed, value = imgui.checkbox("Draw test pattern (top-left overlay)", enabled)
        if changed then
            enabled = value
            if not value then
                stats = { frames = 0, fill = 0, outline = 0, line = 0, text = 0, cjk = 0, image = 0 }
            end
        end

        if enabled then
            imgui.text("--- Live results (calls succeeded / frames) ---")
            imgui.text(string.format("frames: %d", stats.frames))
            imgui.text(string.format("fill_rect: %d   outline_rect: %d   line: %d", stats.fill, stats.outline, stats.line))
            imgui.text(string.format("text: %d   cjk (Noto Sans SC): %d   image (needs plugin): %d", stats.text, stats.cjk, stats.image))
            if stats.frames > 0 and stats.fill == 0 then
                imgui.text_colored("DrawList obtained but drawing fails -> report this build.", 0xFF6969FF)
            elseif stats.frames == 0 then
                imgui.text_colored("begin_frame() never succeeds -> no background DrawList on this build.", 0xFF6969FF)
            end
        end
        imgui.tree_pop()
    end
end)
