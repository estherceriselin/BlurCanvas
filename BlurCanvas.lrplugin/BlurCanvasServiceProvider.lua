--[[
  BlurCanvas — Lightroom Export Service Provider
  Select "Blur Canvas" as the export service instead of "Export to Hard Drive".
  All standard LR export settings (format, quality, resize, metadata, destination,
  naming) remain available; this plugin adds the blur-canvas post-processing step.

  Requires the ImageMagick 7 'magick' binary.
--]]

local LrView          = import 'LrView'
local LrFileUtils     = import 'LrFileUtils'
local LrPathUtils     = import 'LrPathUtils'
local LrDialogs       = import 'LrDialogs'
local LrTasks         = import 'LrTasks'
local LrProgressScope = import 'LrProgressScope'

local DEFAULT_MAGICK = "/Users/esther/Pictures/LRMogrify2.lrplugin/LRMogrify.extras/magick"

local M = {}

-- ── Export preset fields ──────────────────────────────────────────────────────

M.exportPresetFields = {
    { key = 'bc_enabled',       default = true           },
    { key = 'bc_mode',          default = 'blur'         },
    { key = 'bc_width',         default = 2400           },
    { key = 'bc_height',        default = 3000           },
    { key = 'bc_rotate',        default = false          },
    { key = 'bc_blur_radius',   default = 30             },
    { key = 'bc_darken',        default = false          },
    { key = 'bc_darken_amount', default = 20             },
    { key = 'bc_bg_image',      default = ''             },
    { key = 'bc_magick_path',   default = DEFAULT_MAGICK },
}

-- ── UI ────────────────────────────────────────────────────────────────────────

function M.sectionsForTopOfDialog(f, propertyTable)
    local bind  = LrView.bind
    local share = LrView.share

    return {
        {
            title = "Blur Canvas",

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

                -- Blur sub-section
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

                -- External image sub-section
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
                },

                -- magick binary
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
                                title             = "Choose 'magick' binary",
                                canChooseFiles    = true,
                                canChooseDirectories = false,
                                multipleSelection = false,
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
        },
    }
end

-- ── Export ────────────────────────────────────────────────────────────────────

function M.processRenderedPhotos(functionContext, exportContext)
    local settings = exportContext.propertyTable
    if not settings.bc_enabled then return end

    local magick = settings.bc_magick_path or DEFAULT_MAGICK
    if magick == '' then magick = DEFAULT_MAGICK end

    local mode = settings.bc_mode or 'blur'
    local cw   = tonumber(settings.bc_width)  or 1080
    local ch   = tonumber(settings.bc_height) or 1080

    local exportSession = exportContext.exportSession
    local nPhotos       = exportSession:countRenditions()

    local scope = LrProgressScope({
        title           = "Blur Canvas",
        functionContext = functionContext,
    })

    local i = 0
    for _, rendition in exportSession:renditions({ stopIfCanceled = true }) do
        i = i + 1
        if scope:isCanceled() then break end
        scope:setPortionComplete(i - 1, nPhotos)

        -- waitForRender() triggers LR to render the photo to a temp file
        -- and returns that temp path on success.
        local success, pathOrMessage = rendition:waitForRender()

        LrDialogs.message("BC-wfr",
            "success=" .. tostring(success) .. "  path=" .. tostring(pathOrMessage))

        if not success then break end

        local srcPath  = pathOrMessage          -- temp rendered file from LR
        local destPath = rendition.destinationPath
        local photo    = rendition.photo

        local w, h = cw, ch
        if settings.bc_rotate and photo then
            local pw = photo:getRawMetadata('width')  or 0
            local ph = photo:getRawMetadata('height') or 0
            if pw > ph and cw < ch then w, h = ch, cw end
        end

        local cmd
        if mode == 'blur' then
            local radius = tonumber(settings.bc_blur_radius)   or 30
            local damt   = tonumber(settings.bc_darken_amount) or 20
            local modulate = ""
            if settings.bc_darken and damt > 0 then
                modulate = string.format(" -modulate %d,100,100",
                    math.max(0, 100 - damt))
            end
            cmd = string.format(
                '"%s"'
                .. ' \\( "%s" -resize %dx%d^ -gravity Center -extent %dx%d -blur 0x%d%s \\)'
                .. ' \\( "%s" -resize %dx%d \\)'
                .. ' -gravity Center -composite "%s"',
                magick,
                srcPath, w, h, w, h, radius, modulate,
                srcPath, w, h,
                destPath
            )
        else
            local bgPath = settings.bc_bg_image or ''
            if bgPath ~= '' and LrFileUtils.exists(bgPath) then
                cmd = string.format(
                    '"%s"'
                    .. ' \\( "%s" -resize %dx%d^ -gravity Center -extent %dx%d \\)'
                    .. ' \\( "%s" -resize %dx%d \\)'
                    .. ' -gravity Center -composite "%s"',
                    magick,
                    bgPath, w, h, w, h,
                    srcPath, w, h,
                    destPath
                )
            end
        end

        if cmd then
            local handle = io.popen(cmd .. ' 2>/tmp/blurcanvas.log')
            if handle then handle:read("*a"); handle:close() end

            if not LrFileUtils.exists(destPath) then
                LrDialogs.message("BC-magick-fail",
                    "magick produced no output\ncmd=" .. cmd)
            end
        end

        scope:setPortionComplete(i, nPhotos)
    end

    scope:done()
end

return M
