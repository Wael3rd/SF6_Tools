-- =========================================================
-- ImGuiCanvas.lua
-- Small compatibility canvas backed only by REFramework ImGui.
-- Ported from SF6_TOOLS_CC (API kept identical so SF6CC renderers
-- port drop-in). Geometry/text need only the Lua DrawList API;
-- PNG images additionally need the reframework-imgui-texture native
-- plugin and degrade to no-ops without it.
-- =========================================================

local M = {}

local state = {
    draw_list = nil,
    tick = 0,
    last_log_tick = {},
    fonts = {}
}

local LOG_INTERVAL = 600

local function is_finite(value)
    return type(value) == "number"
        and value == value
        and value > -math.huge
        and value < math.huge
end

local function log_rate_limited(key, message)
    local last_tick = state.last_log_tick[key]
    if last_tick ~= nil and (state.tick - last_tick) < LOG_INTERVAL then return end
    state.last_log_tick[key] = state.tick
    if log and log.warn then
        pcall(log.warn, "[ImGuiCanvas] " .. tostring(message))
    end
end

local function valid_rect(x, y, width, height)
    return is_finite(x)
        and is_finite(y)
        and is_finite(width)
        and is_finite(height)
        and width > 0
        and height > 0
end

local function vector_xy(value)
    if value == nil then return nil, nil end
    local ok, x, y = pcall(function()
        return value.x or value.w, value.y or value.h
    end)
    if ok and is_finite(x) and is_finite(y) then return x, y end
    return nil, nil
end

function M.begin_frame()
    state.tick = state.tick + 1
    state.draw_list = nil

    if not imgui or type(imgui.get_background_draw_list) ~= "function" then
        log_rate_limited("draw_list_api", "imgui.get_background_draw_list unavailable.")
        return false
    end

    local ok, draw_list = pcall(imgui.get_background_draw_list)
    if not ok or draw_list == nil then
        log_rate_limited("draw_list", "Could not get the background DrawList: " .. tostring(draw_list))
        return false
    end

    state.draw_list = draw_list
    return true
end

function M.surface_size()
    local width, height = 1920, 1080
    if imgui and type(imgui.get_display_size) == "function" then
        local ok, first, second = pcall(imgui.get_display_size)
        if ok then
            if is_finite(first) and is_finite(second) then
                width, height = first, second
            else
                local x, y = vector_xy(first)
                if x and y then width, height = x, y end
            end
        end
    end
    if not is_finite(width) or width <= 0 then width = 1920 end
    if not is_finite(height) or height <= 0 then height = 1080 end
    return width, height
end

function M.fill_rect(x, y, width, height, color)
    if state.draw_list == nil or not valid_rect(x, y, width, height) then return false end
    if not is_finite(color) then color = 0xFFFFFFFF end

    local ok, err = pcall(function()
        state.draw_list:add_rect_filled(
            Vector2f.new(x, y),
            Vector2f.new(x + width, y + height),
            color,
            0.0,
            0
        )
    end)
    if not ok then
        log_rate_limited("fill_rect", "add_rect_filled failed: " .. tostring(err))
    end
    return ok
end

function M.outline_rect(x, y, width, height, thickness, color)
    if state.draw_list == nil or not valid_rect(x, y, width, height) then return false end
    if not is_finite(thickness) or thickness <= 0 then thickness = 1.0 end
    if not is_finite(color) then color = 0xFFFFFFFF end

    local ok, err = pcall(function()
        state.draw_list:add_rect(
            Vector2f.new(x, y),
            Vector2f.new(x + width, y + height),
            color,
            0.0,
            0,
            thickness
        )
    end)
    if not ok then
        log_rate_limited("outline_rect", "add_rect failed: " .. tostring(err))
    end
    return ok
end

function M.line(x1, y1, x2, y2, thickness, color)
    if state.draw_list == nil
        or not is_finite(x1) or not is_finite(y1)
        or not is_finite(x2) or not is_finite(y2) then
        return false
    end
    if not is_finite(thickness) or thickness <= 0 then thickness = 1.0 end
    if not is_finite(color) then color = 0xFFFFFFFF end

    local ok, err = pcall(function()
        state.draw_list:add_line(
            Vector2f.new(x1, y1),
            Vector2f.new(x2, y2),
            color,
            thickness
        )
    end)
    if not ok then
        log_rate_limited("line", "add_line failed: " .. tostring(err))
    end
    return ok
end

local Font = {}
Font.__index = Font

local function push_font(font)
    if not font or not font.object or type(imgui.push_font) ~= "function" then return false end
    local ok = pcall(imgui.push_font, font.object)
    return ok
end

local function pop_font(pushed)
    if pushed and type(imgui.pop_font) == "function" then
        pcall(imgui.pop_font)
    end
end

function Font:measure(text)
    local value = tostring(text or "")
    local pushed = push_font(self)
    local ok, measured = pcall(imgui.calc_text_size, value)
    pop_font(pushed)
    if ok then
        local width, height = vector_xy(measured)
        if width and height then return width, height end
    end
    return #value * self.size * 0.55, self.size
end

M.Font = {}

function M.Font.new(filename, size)
    filename = tostring(filename or "")
    size = math.max(1, math.floor(tonumber(size) or 1))
    local key = filename .. ":" .. tostring(size)
    if state.fonts[key] then return state.fonts[key] end

    if not imgui or type(imgui.load_font) ~= "function" then
        log_rate_limited("font_api", "imgui.load_font unavailable.")
        return nil
    end

    local ok, object = pcall(imgui.load_font, filename, size)
    if not ok or object == nil then
        log_rate_limited("font_" .. key, "Font load failed: " .. filename .. " " .. tostring(object))
        return nil
    end

    local font = setmetatable({
        object = object,
        filename = filename,
        size = size
    }, Font)
    state.fonts[key] = font
    return font
end

function M.text(font, text, x, y, color)
    if state.draw_list == nil or font == nil or text == nil
        or not is_finite(x) or not is_finite(y) then
        return false
    end
    if not is_finite(color) then color = 0xFFFFFFFF end

    local value = tostring(text)
    local pushed = push_font(font)
    local ok, err = pcall(function()
        state.draw_list:add_text(Vector2f.new(x, y), color, value)
    end)
    pop_font(pushed)
    if not ok then
        log_rate_limited("text", "add_text failed: " .. tostring(err))
    end
    return ok
end

M.Image = {}

function M.Image.new(relative_path)
    local image = {
        path = tostring(relative_path or ""),
        handle = nil
    }

    if type(texture) ~= "table" or type(texture.load) ~= "function" then
        log_rate_limited("texture_api", "reframework-imgui-texture API not loaded.")
        return image
    end

    local ok, handle, load_error = pcall(texture.load, image.path)
    if ok and handle then
        image.handle = handle
    else
        log_rate_limited(
            "texture_load_" .. image.path,
            "PNG load failed " .. image.path .. ": " .. tostring(ok and load_error or handle)
        )
    end
    return image
end

function M.image(image, x, y, width, height)
    if image == nil or not valid_rect(x, y, width, height) then return false end

    if image.handle == nil and type(texture) == "table" and type(texture.load) == "function" then
        local ok, handle = pcall(texture.load, image.path)
        if ok and handle then image.handle = handle end
    end

    if image.handle == nil or type(texture) ~= "table" or type(texture.draw) ~= "function" then
        log_rate_limited("texture_draw_" .. tostring(image.path), "PNG draw API unavailable: " .. tostring(image.path))
        return false
    end

    local ok, drawn, draw_error = pcall(texture.draw, image.handle, x, y, width, height)
    if not ok then
        log_rate_limited("texture_call_" .. image.path, "PNG draw call failed: " .. tostring(drawn))
        return false
    end
    if not drawn and draw_error ~= "PNG 正在等待 ImGui 字体图集上传" then
        -- Permanent PNG failures are already logged once by the native bridge.
        return false
    end
    return drawn == true
end

function M.register(initialize, draw)
    local initialized = false
    re.on_frame(function()
        if not M.begin_frame() then return end

        if not initialized then
            local ok, err = pcall(initialize)
            if not ok then
                log_rate_limited("initialize", "Initialization failed: " .. tostring(err))
                return
            end
            initialized = true
        end

        local ok, err = pcall(draw)
        if not ok then
            log_rate_limited("draw", "Frame draw failed: " .. tostring(err))
        end
    end)
end

return M
