return {
    LrSdkVersion        = 6.0,
    LrSdkMinimumVersion = 5.0,

    LrToolkitIdentifier = "com.esther.blurcanvas",
    LrPluginName        = "Blur Canvas",

    LrExportFilterProvider = {
        title = "Blur Canvas",
        file  = "BlurCanvasFilterProvider.lua",
        id    = "com.esther.blurcanvas.filter",
    },

    LrPluginMenuItems = {
        {
            title = "Apply Blur Canvas to Folder...",
            file  = "BlurCanvasMenu.lua",
            id    = "com.esther.blurcanvas.menu",
        },
    },

    LrLibraryMenuItems = {
        {
            title = "Apply Blur Canvas to Folder...",
            file  = "BlurCanvasMenu.lua",
            id    = "com.esther.blurcanvas.libmenu",
        },
    },

    VERSION = { major = 1, minor = 1, revision = 0, display = "1.1" },
}
