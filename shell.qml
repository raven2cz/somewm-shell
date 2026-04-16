import QtQuick
import Quickshell
import "core" as Core
import "modules" as Modules
import "modules/dashboard" as DashboardModule
import "modules/osd" as OsdModule
import "modules/weather" as WeatherModule
import "modules/wallpapers" as WallpapersModule
import "modules/collage" as CollageModule
import "modules/controlpanel" as ControlPanelModule
import "modules/dock" as DockModule
import "modules/hotedges" as HotEdgesModule

ShellRoot {
    // Dashboard — Caelestia-style overlay with border strip + panel
    Modules.ModuleLoader {
        moduleName: "dashboard"
        sourceComponent: Component { DashboardModule.Dashboard {} }
    }

    // OSD is always enabled (system-level, not user-toggleable)
    OsdModule.OSD {}

    Modules.ModuleLoader {
        moduleName: "weather"
        sourceComponent: Component { WeatherModule.WeatherPanel {} }
    }

    Modules.ModuleLoader {
        moduleName: "wallpapers"
        sourceComponent: Component { WallpapersModule.WallpaperPanel {} }
    }

    Modules.ModuleLoader {
        moduleName: "collage"
        sourceComponent: Component { CollageModule.Collage {} }
    }

    // Control panel — quick volume/mic/brightness popout
    Modules.ModuleLoader {
        moduleName: "controlpanel"
        sourceComponent: Component { ControlPanelModule.ControlPanel {} }
    }

    // Dock — running apps with icons, left-side popout
    Modules.ModuleLoader {
        moduleName: "dock"
        sourceComponent: Component { DockModule.Dock {} }
    }

    // Hot screen edges
    HotEdgesModule.HotEdges {}

    // Force NotifStore singleton instantiation at shell startup so its
    // IpcHandler (somewm-shell:notifications) registers even when no
    // consumer panel is visible yet. Without this, the handler is lazy
    // and `qs ipc -c somewm call somewm-shell:notifications refresh`
    // returns "Target not found" until the sidebar/dashboard is opened.
    // A method call is required — property access gets optimized away
    // by the JS engine and leaves the singleton uninstantiated.
    Component.onCompleted: Core.NotifStore.refresh()
}
