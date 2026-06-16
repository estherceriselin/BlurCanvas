--[[
  BlurCanvas — Lightroom Export Filter Plugin
  Replaces LR Mogrify 2's solid-colour canvas with either:
    • A blurred + optionally darkened enlargement of the photo itself
    • An external image / seamless pattern tile

  Place this filter AFTER LR Mogrify 2 in the export filter chain.
  Leave LR Mogrify 2's own "Canvas" step DISABLED.

  Requires the ImageMagick 7 'magick' binary (the one bundled with LR Mogrify 2
  works perfectly; its path is the default below).
--]]

local LrView          = import 'LrView'
local LrFileUtils     = import 'LrFileUtils'
local LrPathUtils     = import 'LrPathUtils'
local LrDialogs       = import 'LrDialogs'
local LrTasks         = import 'LrTasks'
local LrProgressScope = import 'LrProgressScope'

local DEFAULT_MAGICK = "/Users/esther/Pictures/LRMogrify2.lrplugin/LRMogrify.extras/magick"

local BlurCanvas = {}

-- ── Export preset fields ──────────────────────────────────────────────────────

BlurCanvas.exportPresetFields = {
    { key = 'bc_enabled',       default = true          },
    { key = 'bc_mode',          default = 'blur'        },
    { key = 'bc_width',         default = 2400          },
    { key = 'bc_height',        default = 3000          },
    { key = 'bc_rotate',        default = false         },
    { key = 'bc_blur_radius',   default = 30            },
    { key = 'bc_darken',        default = false         },
    { key = 'bc_darken_amount', default = 20            },
    { key = 'bc_bg_image',      default = ''            },
    { key = 'bc_magick_path',   default = DEFAULT_MAGICK },
}

-- ── UI section ────────────────────────────────────────────────────────────────

function BlurCanvas.sectionForFilterInDialog(f, propertyTable)
    local bind  = LrView.bind
    local share = LrView.share

    local synopsis = bind {
        keys      = { 'bc_enabled', 'bc_mode', 'bc_width', 'bc_height' },
        operation = function(binder, values, fromTable)
            if not values.bc_enabled then return "Disabled" end
            local m = (values.bc_mode == 'blur') and "Blurred BG" or "Image BG"
            return string.format("%s  %d x %d px", m,
                values.bc_width or 0, values.bc_height or 0)
        end,
        fromTable = true,
    }

    return {
        title    = "Blur Canvas",
        synopsis = synopsis,

        f:column {
            spacing = f:control_spacing(),

            f:row {
                f:checkbox {
                    title = "Enable Blur Canvas",
                    value = bind 'bc_enabled',
                },
            },

            f:row {
                enabled = bind 'bc_enabled',
                f:static_text { title = "Background:", width = share 'bc_lw' },
                f:popup_menu {
                    value = bind 'bc_mode',
                    items = {
                        { title = "Blurred photo (same image)", value = 'blur'  },
                        { title = "External image or pattern",  value = 'image' },
                    },
                },
            },

            f:row {
                enabled = bind 'bc_enabled',
                f:static_text { title = "Canvas:", width = share 'bc_lw' },
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
                enabled = bind 'bc_enabled',
                f:spacer { width = share 'bc_lw' },
                f:checkbox {
                    title = "Swap W/H for landscape photos",
                    value = bind 'bc_rotate',
                },
            },

            -- Blur sub-section (visible only in blur mode)
            f:column {
                enabled = bind 'bc_enabled',
                visible = bind {
                    key       = 'bc_mode',
                    transform = function(v) return v == 'blur' end,
                },
                f:separator { fill_horizontal = 1 },
                f:row {
                    f:static_text { title = "Blur radius:", width = share 'bc_lw' },
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
                    f:static_text { title = "px sigma  (30-60 recommended)" },
                },
                f:row {
                    f:static_text { title = "Darken BG:", width = share 'bc_lw' },
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

            -- External image sub-section (visible only in image mode)
            f:column {
                enabled = bind 'bc_enabled',
                visible = bind {
                    key       = 'bc_mode',
                    transform = function(v) return v == 'image' end,
                },
                f:separator { fill_horizontal = 1 },
                f:row {
                    f:static_text { title = "Image file:", width = share 'bc_lw' },
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
                                propertyTable.bc_bg_image = r[1]
                            end
                        end,
                    },
                },
                f:row {
                    f:spacer { width = share 'bc_lw' },
                    f:static_text {
                        title = "Cover-cropped to fill the canvas exactly.",
                        font  = "<small>",
                    },
                },
            },

            -- ImageMagick binary
            f:separator { fill_horizontal = 1 },
            f:row {
                enabled = bind 'bc_enabled',
                f:static_text { title = "magick path:", width = share 'bc_lw' },
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
                            propertyTable.bc_magick_path = r[1]
                        end
                    end,
                },
            },
            f:row {
                enabled = bind 'bc_enabled',
                f:spacer { width = share 'bc_lw' },
                f:static_text {
                    title = "Default: the magick binary bundled inside LR Mogrify 2.",
                    font  = "<small>",
                },
            },
        },
    }
end

-- ── Post-process ──────────────────────────────────────────────────────────────

local function processPhoto(pt, photo, path)
    local magick = pt.bc_magick_path or DEFAULT_MAGICK
    if magick == '' then magick = DEFAULT_MAGICK end

    local mode   = pt.bc_mode  or 'blur'
    local cw     = tonumber(pt.bc_width)  or 1080
    local ch     = tonumber(pt.bc_height) or 1080

    local w, h = cw, ch
    if pt.bc_rotate and photo then
        local pw = photo:getRawMetadata('width')  or 0
        local ph = photo:getRawMetadata('height') or 0
        if pw > ph and cw < ch then
            w, h = ch, cw
        end
    end

    local ext     = LrPathUtils.extension(path)
    local tmpPath = LrPathUtils.replaceExtension(path, "bc_tmp." .. ext)

    local cmd

    if mode == 'blur' then
        local radius = tonumber(pt.bc_blur_radius)   or 30
        local darken = pt.bc_darken
        local damt   = tonumber(pt.bc_darken_amount) or 20

        local modulate = ""
        if darken and damt > 0 then
            local brightness = math.max(0, 100 - damt)
            modulate = string.format(" -modulate %d,100,100", brightness)
        end

        -- Two paren groups:
        --   Group 1: load photo, cover-scale to WxH, blur [+darken] -> background
        --   Group 2: load photo, fit within WxH                      -> foreground
        -- Then composite fg centred on bg and save.
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
            LrDialogs.message(
                "Blur Canvas",
                "Background image not found:\n\n" .. bgPath,
                "critical"
            )
            return false
        end

        -- Group 1: load bg image, cover-scale to WxH -> background
        -- Group 2: load photo, fit within WxH        -> foreground
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

    local handle = io.popen(cmd .. " 2>&1")
    local output = handle and handle:read("*a") or ""
    if handle then handle:close() end

    if LrFileUtils.exists(tmpPath) then
        LrFileUtils.delete(path)
        LrFileUtils.move(tmpPath, path)
        return true
    else
        if LrFileUtils.exists(tmpPath) then
            LrFileUtils.delete(tmpPath)
        end
        return false, "magick failed\n\n" .. output .. "\n\ncmd:\n" .. (cmd or "(nil)")
    end
end

function BlurCanvas.postProcessRenderedPhotos(functionContext, filterContext)
    local pt = filterContext.propertyTable
    if not pt or not pt.bc_enabled then return end


    local nPhotos = #filterContext.renditionsToSatisfy

    local scope = LrProgressScope({
        title           = "Blur Canvas",
        functionContext = functionContext,
    })

    local i = 0
    for rendition in filterContext:renditions({ stopIfCanceled = true }) do
        i = i + 1
        if scope:isCanceled() then break end
        scope:setPortionComplete(i - 1, nPhotos)

        local success, pathOrMsg = rendition:waitForRender()
        if not success then break end

        local ok, err = processPhoto(pt, rendition.photo, pathOrMsg)
        if not ok then
            rendition:uploadFailed(err or "Blur Canvas: magick failed")
        end

        scope:setPortionComplete(i, nPhotos)
    end

    scope:done()
end

return BlurCanvas
