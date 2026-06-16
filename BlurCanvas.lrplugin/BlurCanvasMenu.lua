--[[
  BlurCanvas — Plugin Extras menu item
  File > Plugin Extras > Apply Blur Canvas to Folder...

  Picks a folder of already-exported JPEGs/PNGs/TIFFs and applies the
  blur-canvas effect in-place using ImageMagick 7's magick binary.
--]]

local LrView          = import 'LrView'
local LrDialogs       = import 'LrDialogs'
local LrFileUtils     = import 'LrFileUtils'
local LrPathUtils     = import 'LrPathUtils'
local LrPrefs         = import 'LrPrefs'
local LrProgressScope = import 'LrProgressScope'
local LrFunctionContext = import 'LrFunctionContext'
local LrTasks         = import 'LrTasks'

local DEFAULT_MAGICK = "/Users/esther/Pictures/LRMogrify2.lrplugin/LRMogrify.extras/magick"

-- ── Persist settings between runs ─────────────────────────────────────────────

local prefs = LrPrefs.prefsForPlugin()

local function loadPrefs()
    return {
        bc_mode          = prefs.bc_mode          or 'blur',
        bc_width         = prefs.bc_width          or 2400,
        bc_height        = prefs.bc_height         or 3000,
        bc_rotate        = prefs.bc_rotate         or false,
        bc_blur_radius   = prefs.bc_blur_radius    or 30,
        bc_darken        = prefs.bc_darken         or false,
        bc_darken_amount = prefs.bc_darken_amount  or 20,
        bc_bg_image      = prefs.bc_bg_image       or '',
        bc_magick_path   = prefs.bc_magick_path    or DEFAULT_MAGICK,
        bc_folder        = prefs.bc_folder         or '',
    }
end

local function savePrefs(pt)
    prefs.bc_mode          = pt.bc_mode
    prefs.bc_width         = pt.bc_width
    prefs.bc_height        = pt.bc_height
    prefs.bc_rotate        = pt.bc_rotate
    prefs.bc_blur_radius   = pt.bc_blur_radius
    prefs.bc_darken        = pt.bc_darken
    prefs.bc_darken_amount = pt.bc_darken_amount
    prefs.bc_bg_image      = pt.bc_bg_image
    prefs.bc_magick_path   = pt.bc_magick_path
    prefs.bc_folder        = pt.bc_folder
end

-- ── Find image files in a folder ───────────────────────────────────────────────

local function findImages(folder)
    -- Use /usr/bin/find which is always present on macOS
    local cmd = string.format(
        '/usr/bin/find "%s" -maxdepth 1 -type f \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.tif" -o -iname "*.tiff" \\) | /usr/bin/sort',
        folder
    )
    local handle = io.popen(cmd)
    if not handle then return {} end
    local output = handle:read("*a")
    handle:close()

    local files = {}
    for line in output:gmatch("[^\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= '' then
            files[#files + 1] = trimmed
        end
    end
    return files
end

-- ── Process one image file ─────────────────────────────────────────────────────

local function processFile(pt, photo, path)
    local magick = pt.bc_magick_path or DEFAULT_MAGICK
    if magick == '' then magick = DEFAULT_MAGICK end

    local mode = pt.bc_mode or 'blur'
    local cw   = tonumber(pt.bc_width)  or 1080
    local ch   = tonumber(pt.bc_height) or 1080

    local w, h = cw, ch
    if pt.bc_rotate then
        -- Detect landscape from file dimensions via magick identify
        local idCmd = string.format('"%s" identify -format "%%w %%h" "%s" 2>/dev/null',
            magick, path)
        local idHandle = io.popen(idCmd)
        if idHandle then
            local dims = idHandle:read("*a")
            idHandle:close()
            local pw, ph = dims:match("(%d+)%s+(%d+)")
            pw, ph = tonumber(pw) or 0, tonumber(ph) or 0
            if pw > ph and cw < ch then
                w, h = ch, cw
            end
        end
    end

    local ext     = LrPathUtils.extension(path)
    local tmpPath = path:sub(1, #path - #ext - 1) .. ".bc_tmp." .. ext

    local cmd
    if mode == 'blur' then
        local radius = tonumber(pt.bc_blur_radius)   or 30
        local damt   = tonumber(pt.bc_darken_amount) or 20
        local modulate = ""
        if pt.bc_darken and damt > 0 then
            modulate = string.format(" -modulate %d,100,100",
                math.max(0, 100 - damt))
        end
        cmd = string.format(
            '"%s"'
            .. ' \\( "%s" -resize %dx%d^ -gravity Center -extent %dx%d -blur 0x%d%s \\)'
            .. ' \\( "%s" -resize %dx%d \\)'
            .. ' -gravity Center -composite "%s"',
            magick,
            path, w, h, w, h, radius, modulate,
            path, w, h,
            tmpPath
        )
    else
        local bgPath = pt.bc_bg_image or ''
        if bgPath == '' or not LrFileUtils.exists(bgPath) then
            return false, "Background image not found: " .. bgPath
        end
        cmd = string.format(
            '"%s"'
            .. ' \\( "%s" -resize %dx%d^ -gravity Center -extent %dx%d \\)'
            .. ' \\( "%s" -resize %dx%d \\)'
            .. ' -gravity Center -composite "%s"',
            magick,
            bgPath, w, h, w, h,
            path, w, h,
            tmpPath
        )
    end

    local handle = io.popen(cmd .. " 2>/tmp/blurcanvas.log")
    if handle then handle:read("*a"); handle:close() end

    if LrFileUtils.exists(tmpPath) then
        LrFileUtils.delete(path)
        LrFileUtils.move(tmpPath, path)
        return true, nil
    else
        -- Read any error from the log
        local logHandle = io.popen("cat /tmp/blurcanvas.log 2>/dev/null")
        local logMsg = logHandle and logHandle:read("*a") or ""
        if logHandle then logHandle:close() end
        return false, "magick produced no output.\n\n" .. logMsg
    end
end

-- ── Settings dialog ────────────────────────────────────────────────────────────

local function showDialog(pt)
    local f    = LrView.osFactory()
    local bind = LrView.bind
    local share = LrView.share

    local result = LrDialogs.presentModalDialog({
        title   = "Apply Blur Canvas to Folder",
        contents = f:column {
            spacing = f:dialog_spacing(),

            -- Folder picker row
            f:row {
                f:static_text { title = "Folder:", width = share 'lw' },
                f:edit_field {
                    value          = bind 'bc_folder',
                    width_in_chars = 35,
                    immediate      = true,
                },
                f:push_button {
                    title  = "Choose...",
                    action = function()
                        local r = LrDialogs.runOpenPanel({
                            title                = "Choose Export Folder",
                            canChooseFiles       = false,
                            canChooseDirectories = true,
                            multipleSelection    = false,
                        })
                        if r and r[1] then
                            pt.bc_folder = r[1]
                        end
                    end,
                },
            },

            f:separator { fill_horizontal = 1 },

            -- Background mode
            f:row {
                f:static_text { title = "Background:", width = share 'lw' },
                f:popup_menu {
                    value = bind 'bc_mode',
                    items = {
                        { title = "Blurred photo (same image)", value = 'blur'  },
                        { title = "External image or pattern",  value = 'image' },
                    },
                },
            },

            -- Canvas size
            f:row {
                f:static_text { title = "Canvas:", width = share 'lw' },
                f:edit_field {
                    value           = bind 'bc_width',
                    width_in_digits = 5,
                    precision       = 0,
                    min             = 1,
                    max             = 10000,
                    immediate       = true,
                },
                f:static_text { title = " x " },
                f:edit_field {
                    value           = bind 'bc_height',
                    width_in_digits = 5,
                    precision       = 0,
                    min             = 1,
                    max             = 10000,
                    immediate       = true,
                },
                f:static_text { title = "px" },
            },

            f:row {
                f:spacer { width = share 'lw' },
                f:checkbox {
                    title = "Swap W/H for landscape photos",
                    value = bind 'bc_rotate',
                },
            },

            -- Blur sub-section
            f:column {
                visible = bind {
                    key       = 'bc_mode',
                    transform = function(v) return v == 'blur' end,
                },
                f:separator { fill_horizontal = 1 },
                f:row {
                    f:static_text { title = "Blur radius:", width = share 'lw' },
                    f:slider {
                        value    = bind 'bc_blur_radius',
                        min      = 5,
                        max      = 120,
                        integral = true,
                        width    = 130,
                    },
                    f:edit_field {
                        value           = bind 'bc_blur_radius',
                        width_in_digits = 4,
                        precision       = 0,
                        min             = 1,
                        max             = 200,
                        immediate       = true,
                    },
                    f:static_text { title = "px sigma  (30–60 recommended)" },
                },
                f:row {
                    f:static_text { title = "Darken BG:", width = share 'lw' },
                    f:checkbox { title = "", value = bind 'bc_darken' },
                    f:edit_field {
                        value           = bind 'bc_darken_amount',
                        width_in_digits = 3,
                        precision       = 0,
                        min             = 0,
                        max             = 100,
                        immediate       = true,
                        enabled         = bind 'bc_darken',
                    },
                    f:static_text { title = "% darker" },
                },
            },

            -- External image sub-section
            f:column {
                visible = bind {
                    key       = 'bc_mode',
                    transform = function(v) return v == 'image' end,
                },
                f:separator { fill_horizontal = 1 },
                f:row {
                    f:static_text { title = "Image file:", width = share 'lw' },
                    f:edit_field {
                        value          = bind 'bc_bg_image',
                        width_in_chars = 30,
                        immediate      = true,
                    },
                    f:push_button {
                        title  = "Choose...",
                        action = function()
                            local r = LrDialogs.runOpenPanel({
                                title                = "Choose Background Image",
                                canChooseFiles       = true,
                                canChooseDirectories = false,
                                allowedFileTypes     = { "jpg", "jpeg", "png", "tif", "tiff" },
                                multipleSelection    = false,
                            })
                            if r and r[1] then
                                pt.bc_bg_image = r[1]
                            end
                        end,
                    },
                },
            },

            -- magick binary
            f:separator { fill_horizontal = 1 },
            f:row {
                f:static_text { title = "magick path:", width = share 'lw' },
                f:edit_field {
                    value          = bind 'bc_magick_path',
                    width_in_chars = 30,
                    immediate      = true,
                },
                f:push_button {
                    title  = "Choose...",
                    action = function()
                        local r = LrDialogs.runOpenPanel({
                            title                = "Choose 'magick' binary",
                            canChooseFiles       = true,
                            canChooseDirectories = false,
                            multipleSelection    = false,
                        })
                        if r and r[1] then
                            pt.bc_magick_path = r[1]
                        end
                    end,
                },
            },
            f:row {
                f:spacer { width = share 'lw' },
                f:static_text {
                    title = "Default: the magick binary bundled inside LR Mogrify 2.",
                    font  = "<small>",
                },
            },
        },

        actionVerb  = "Apply",
        cancelVerb  = "Cancel",
        propertyTable = pt,
    })

    return result
end

-- ── Entry point ────────────────────────────────────────────────────────────────

LrFunctionContext.callWithContext("BlurCanvasMenu", function(context)
    LrTasks.startAsyncTask(function()

        local pt = loadPrefs()

        -- Wrap pt in an observable property table for the dialog bindings
        local LrBinding = import 'LrBinding'
        local observable = LrBinding.makePropertyTable(context)
        for k, v in pairs(pt) do
            observable[k] = v
        end

        local result = showDialog(observable)
        if result ~= 'ok' then return end

        -- Copy observable back to plain table for processing
        for k in pairs(pt) do
            pt[k] = observable[k]
        end

        -- Validate folder
        local folder = pt.bc_folder or ''
        if folder == '' or not LrFileUtils.exists(folder) then
            LrDialogs.message("Blur Canvas", "Please choose a valid folder.", "critical")
            return
        end

        savePrefs(pt)

        -- Find files
        local files = findImages(folder)
        if #files == 0 then
            LrDialogs.message("Blur Canvas",
                "No JPEG/PNG/TIFF files found in:\n" .. folder)
            return
        end

        -- Process with progress
        local nFailed = 0
        local firstError = nil

        LrFunctionContext.callWithContext("BlurCanvasProgress", function(progressCtx)
            local scope = LrProgressScope({
                title           = string.format("Blur Canvas — processing %d file(s)", #files),
                functionContext = progressCtx,
            })

            for i, path in ipairs(files) do
                if scope:isCanceled() then break end
                scope:setCaption(LrPathUtils.leafName(path))
                scope:setPortionComplete(i - 1, #files)

                local ok, err = processFile(pt, nil, path)
                if not ok then
                    nFailed = nFailed + 1
                    if not firstError then
                        firstError = path .. "\n" .. (err or "unknown error")
                    end
                end

                scope:setPortionComplete(i, #files)
            end

            scope:done()
        end)

        -- Summary
        local succeeded = #files - nFailed
        if nFailed == 0 then
            LrDialogs.message("Blur Canvas",
                string.format("Done! %d file(s) processed.", succeeded))
        else
            LrDialogs.message("Blur Canvas",
                string.format("%d succeeded, %d failed.\n\nFirst error:\n%s",
                    succeeded, nFailed, firstError or ""),
                "warning")
        end

    end)
end)
