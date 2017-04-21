/*
 * This file is part of budgie-desktop
 * 
 * Copyright © 2015-2017 Ikey Doherty <ikey@solus-project.com>
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */
 
using LibUUID;

namespace Budgie
{

public const string DBUS_NAME        = "org.budgie_desktop.Panel";
public const string DBUS_OBJECT_PATH = "/org/budgie_desktop/Panel";

public const string MIGRATION_1_APPLETS[] = {
    "User Indicator",
    "Raven Trigger",
};

/**
 * Available slots
 */
[Compact]
class Screen : Object {
    public PanelPosition slots;
    public Gdk.Rectangle area;
}

/**
 * Maximum slots set to 2 because Raven has a side in this.
 */
public const uint MAX_SLOTS         = 2;

/**
 * Root prefix for fixed schema
 */
public const string ROOT_SCHEMA     = "com.solus-project.budgie-panel";

/**
 * Relocatable schema ID for toplevel panels
 */
public const string TOPLEVEL_SCHEMA = "com.solus-project.budgie-panel.panel";

/**
 * Prefix for all relocatable panel settings
 */
public const string TOPLEVEL_PREFIX = "/com/solus-project/budgie-panel/panels";


/**
 * Relocatable schema ID for applets
 */
public const string APPLET_SCHEMA   = "com.solus-project.budgie-panel.applet";

/**
 * Prefix for all relocatable applet settings
 */
public const string APPLET_PREFIX   = "/com/solus-project/budgie-panel/applets";

/**
 * Known panels
 */
public const string ROOT_KEY_PANELS     = "panels";

/** Panel position */
public const string PANEL_KEY_POSITION   = "location";

/** Panel applets */
public const string PANEL_KEY_APPLETS    = "applets";

/** Night mode/dark theme */
public const string PANEL_KEY_DARK_THEME = "dark-theme";

/** Panel size */
public const string PANEL_KEY_SIZE       = "size";

/** Shadow */
public const string PANEL_KEY_SHADOW     = "enable-shadow";

/** Theme regions permitted? */
public const string PANEL_KEY_REGIONS    = "theme-regions";

/** Current migration level in settings */
public const string PANEL_KEY_MIGRATION  = "migration-level";

/**
 * The current migration level of Budgie, or format change, if you will.
 */
public const int BUDGIE_MIGRATION_LEVEL = 1;


[DBus (name = "org.budgie_desktop.Panel")]
public class PanelManagerIface
{

    private Budgie.PanelManager? manager = null;

    [DBus (visible = false)]
    public PanelManagerIface(Budgie.PanelManager? manager)
    {
        this.manager = manager;
    }

    public string get_version()
    {
        return Budgie.VERSION;
    }

    public void ActivateAction(int action)
    {
        this.manager.activate_action(action);
    }
        
}

public class PanelManager : DesktopManager
{
    private PanelManagerIface? iface;
    bool setup = false;
    bool reset = false;

    /* Keep track of our SessionManager */
    private LibSession.SessionClient? sclient;

    HashTable<int,Screen?> screens;
    HashTable<string,Budgie.Panel?> panels;

    int primary_monitor = 0;
    Settings settings;
    Peas.Engine engine;
    Peas.ExtensionSet extensions;

    HashTable<string, Peas.PluginInfo?> plugins;

    private Budgie.Raven? raven = null;

    private Budgie.ThemeManager theme_manager;

    /**
     * Updated when specific names are queried
     */
    private bool migrate_load_requirements_met = false;

    public void activate_action(int action)
    {
        unowned string? uuid = null;
        unowned Budgie.Panel? panel = null;

        var iter = HashTableIter<string?,Budgie.Panel?>(panels);
        /* Only let one panel take the action, and one applet per panel */
        while (iter.next(out uuid, out panel)) {
            if (panel.activate_action(action)) {
                break;
            }
        }
    }

    private void end_session(bool quit)
    {
        if (quit) {
            Gtk.main_quit();
            return;
        }
        try {
            sclient.EndSessionResponse(true, "");
        } catch (Error e) {
            warning("Unable to respond to session manager! %s", e.message);
        }
    }

    private async bool register_with_session()
    {
        try {
            sclient = yield LibSession.register_with_session("budgie-panel");
        } catch (Error e) {
            return false;
        }

        sclient.QueryEndSession.connect(()=> {
            end_session(false);
        });
        sclient.EndSession.connect(()=> {
            end_session(false);
        });
        sclient.Stop.connect(()=> {
            end_session(true);
        });
        return true;
    }

    public PanelManager(bool reset)
    {
        Object();
        this.reset = reset;
        screens = new HashTable<int,Screen?>(direct_hash, direct_equal);
        panels = new HashTable<string,Budgie.Panel?>(str_hash, str_equal);
        plugins = new HashTable<string,Peas.PluginInfo?>(str_hash, str_equal);
    }

    /**
     * Attempt to reset the given path
     */
    public void reset_dconf_path(Settings? settings)
    {
        if (settings == null) {
            return;
        }
        string path = settings.path;
        settings.sync();
        if (settings.path == null) {
            return;
        }
        string argv[] = { "dconf", "reset", "-f", path};
        message("Resetting dconf path: %s", path);
        try {
            Process.spawn_command_line_sync(string.joinv(" ", argv), null, null, null);
        } catch (Error e) {
            warning("Failed to reset dconf path %s: %s", path, e.message);
        }
        settings.sync();
    }

    public Budgie.AppletInfo? get_applet(string key)
    {
        return null;
    }

    string create_panel_path(string uuid)
    {
        return "%s/{%s}/".printf(Budgie.TOPLEVEL_PREFIX, uuid);
    }

    string create_applet_path(string uuid)
    {
        return "%s/{%s}/".printf(Budgie.APPLET_PREFIX, uuid);

    }

    /**
     * Discover all possible monitors, and move things accordingly.
     * In future we'll support per-monitor panels, but for now everything
     * must be in one of the edges on the primary monitor
     */
    public void on_monitors_changed()
    {
        var scr = Gdk.Screen.get_default();
        var mon = scr.get_primary_monitor();
        HashTableIter<string,Budgie.Panel?> iter;
        unowned string uuid;
        unowned Budgie.Panel panel;
        unowned Screen? primary;
        unowned Budgie.Panel? top = null;
        unowned Budgie.Panel? bottom = null;

        screens.remove_all();

        /* When we eventually get monitor-specific panels we'll find the ones that
         * were left stray and find new homes, or temporarily disable
         * them */
        for (int i = 0; i < scr.get_n_monitors(); i++) {
            Gdk.Rectangle usable_area;
            scr.get_monitor_geometry(i, out usable_area);
            Budgie.Screen? screen = new Budgie.Screen();
            screen.area = usable_area;
            screen.slots = PanelPosition.NONE;
            screens.insert(i, screen);
        }

        primary = screens.lookup(mon);

        /* Fix all existing panels here */
        iter = HashTableIter<string,Budgie.Panel?>(panels);
        while (iter.next(out uuid, out panel)) {
            /* Force existing panels to update to new primary display */
            panel.update_geometry(primary.area, panel.position);
            if (panel.position == Budgie.PanelPosition.TOP) {
                top = panel;
            } else if (panel.position == Budgie.PanelPosition.BOTTOM) {
                bottom = panel;
            }
            /* Re-take the position */
            primary.slots |= panel.position;
        }
        this.primary_monitor = mon;

        this.raven.update_geometry(primary.area, top, bottom);
    }

    private void on_bus_acquired(DBusConnection conn)
    {
        try {
            iface = new PanelManagerIface(this);
            conn.register_object(Budgie.DBUS_OBJECT_PATH, iface);
        } catch (Error e) {
            stderr.printf("Error registering PanelManager: %s\n", e.message);
            Process.exit(1);
        }
    }

    public void on_name_acquired(DBusConnection conn, string name)
    {
        this.setup = true;
        /* Well, off we go to be a panel manager. */
        do_setup();
    }

    /**
     * Reset the entire panel configuration
     */
    void do_reset()
    {
        GLib.message("Resetting budgie-panel configuration to defaults");
        Settings s = new Settings(Budgie.ROOT_SCHEMA);
        this.reset_dconf_path(s);
    }

    /**
     * Initial setup, once we've owned the dbus name
     * i.e. no risk of dying
     */
    void do_setup()
    {
        if (this.reset) {
            this.do_reset();
        }
        var scr = Gdk.Screen.get_default();
        primary_monitor = scr.get_primary_monitor();
        scr.monitors_changed.connect(this.on_monitors_changed);
        scr.size_changed.connect(this.on_monitors_changed);

        settings = new GLib.Settings(Budgie.ROOT_SCHEMA);
        theme_manager = new Budgie.ThemeManager();
        raven = new Budgie.Raven(this);

        this.on_monitors_changed();

        /* Some applets might want raven */
        raven.setup_dbus();

        setup_plugins();

        int current_migration_level = settings.get_int(PANEL_KEY_MIGRATION);
        if (!load_panels()) {
            message("Creating default panel layout");
            create_default();
        } else {
            /* Migration required */
            perform_migration(current_migration_level);
        }

        /* Whatever route we took, set the migration level to the current now */
        settings.set_int(PANEL_KEY_MIGRATION, BUDGIE_MIGRATION_LEVEL);

        register_with_session.begin((o,res)=> {
            bool success = register_with_session.end(res);
            if (!success) {
                message("Failed to register with Session manager");
            }
        });
    }

    /**
     * Attempts to perform the relevant migration operations by
     * finding a migratable panel and calling its migratory function
     */
    private void perform_migration(int current_migration_level)
    {
        Budgie.Toplevel? top = null;
        Budgie.Toplevel? last = null;

        /* Minimum migration level met, proceed as normal. */
        if (current_migration_level >= BUDGIE_MIGRATION_LEVEL) {
            return;
        }

        /* Manual configuration from user met the expected migration path. Proceed as normal. */
        if (migrate_load_requirements_met) {
            message("Budgie Migration skipped due to user meeting migration requirements");
            return;
        }

        message("Budgie Migration initiated");

        string? key = null;
        Budgie.Panel? val = null;
        Screen? area = screens.lookup(primary_monitor);
        var iter = HashTableIter<string,Budgie.Panel?>(panels);
        while (iter.next(out key, out val)) {
            if (val.position == Budgie.PanelPosition.TOP) {
                top = val;
            }
            last = val;
        }

        /* Prefer the top panel for consistency */
        if (top != null) {
            last = top;
        }

        /* Ask this panel to perform migratory tasks (add applets) */
        (last as Budgie.Panel).perform_migration(current_migration_level);
    }

    /**
     * Initialise the plugin engine, paths, loaders, etc.
     */
    void setup_plugins()
    {
        engine = Peas.Engine.get_default();
        engine.enable_loader("python3");

        /* Ensure libpeas doesn't freak the hell out for Python extensions */
        try {
            var repo = GI.Repository.get_default();
            repo.require("Peas", "1.0", 0);
            repo.require("PeasGtk", "1.0", 0);
            repo.require("Budgie", "1.0", 0);
        } catch (Error e) {
            message("Error loading typelibs: %s", e.message);
        }

        /* System path */
        var dir = Environment.get_user_data_dir();
        engine.add_search_path(Budgie.MODULE_DIRECTORY, Budgie.MODULE_DATA_DIRECTORY);

        /* User path */
        var user_mod = Path.build_path(Path.DIR_SEPARATOR_S, dir, "budgie-desktop", "plugins");
        var hdata = Path.build_path(Path.DIR_SEPARATOR_S, dir, "budgie-desktop", "data");
        engine.add_search_path(user_mod, hdata);

        /* Legacy path */
        var hmod = Path.build_path(Path.DIR_SEPARATOR_S, dir, "budgie-desktop", "modules");
        if (FileUtils.test(hmod, FileTest.EXISTS)) {
            warning("Using legacy path %s, please migrate to %s", hmod, user_mod);
            message("Legacy %s path will not be supported in next major version", hmod);
            engine.add_search_path(hmod, hdata);
        }
        engine.rescan_plugins();

        extensions = new Peas.ExtensionSet(engine, typeof(Budgie.Plugin));

        extensions.extension_added.connect(on_extension_added);
        engine.load_plugin.connect_after((i)=> {
            Peas.Extension? e = extensions.get_extension(i);
            if (e == null) {
                critical("Failed to find extension for: %s", i.get_name());
                return;
            }
            on_extension_added(i, e);
        });
    }

    /**
     * Indicate that a plugin that was being waited for, is now available
     */
    public signal void extension_loaded(string name);

    /**
     * Handle extension loading
     */
    void on_extension_added(Peas.PluginInfo? info, Object p)
    {
        if (plugins.contains(info.get_name())) {
            return;
        }
        plugins.insert(info.get_name(), info);
        extension_loaded(info.get_name());
    }

    public bool is_extension_loaded(string name)
    {
        if (name in MIGRATION_1_APPLETS) {
            migrate_load_requirements_met = true;
        }
        return plugins.contains(name);
    }

    /**
     * Determine if the extension is known to be valid
     */
    public bool is_extension_valid(string name)
    {
        if (name in MIGRATION_1_APPLETS) {
            migrate_load_requirements_met = true;
        }
        if (this.get_plugin_info(name) == null) {
            return false;
        }
        return true;
    }

    public override GLib.List<Peas.PluginInfo?> get_panel_plugins()
    {
        GLib.List<Peas.PluginInfo?> ret = new GLib.List<Peas.PluginInfo?>();
        foreach (unowned Peas.PluginInfo? info in this.engine.get_plugin_list()) {
            ret.append(info);
        }
        return ret;
    }

    /**
     * PeasEngine.get_plugin_info == completely broken
     */
    private unowned Peas.PluginInfo? get_plugin_info(string name)
    {
        foreach (unowned Peas.PluginInfo? info in this.engine.get_plugin_list()) {
            if (info.get_name() == name) {
                return info;
            }
        }
        return null;
    }

    public void modprobe(string name)
    {
        Peas.PluginInfo? i = this.get_plugin_info(name);
        if (i == null) {
            warning("budgie_panel_modprobe called for non existent module: %s", name);
            return;
        }
        this.engine.try_load_plugin(i);
    }

    /**
     * Attempt to load plugin, will set the plugin-name on failure
     */
    public Budgie.AppletInfo? load_applet_instance(string? uuid, out string name, GLib.Settings? psettings = null)
    {
        var path = this.create_applet_path(uuid);
        GLib.Settings? settings = null;
        if (psettings == null) {
            settings = new Settings.with_path(Budgie.APPLET_SCHEMA, path);
        } else {
            settings = psettings;
        }
        var pname = settings.get_string(Budgie.APPLET_KEY_NAME);
        Peas.PluginInfo? pinfo = plugins.lookup(pname);

        /* Not yet loaded */
        if (pinfo == null) {
            pinfo = this.get_plugin_info(pname);
            if (pinfo == null) {
                warning("Trying to load invalid plugin: %s %s", pname, uuid);
                name = null;
                return null;
            }
            engine.try_load_plugin(pinfo);
            name = pname;
            return null;
        }
        var extension = extensions.get_extension(pinfo);
        if (extension == null) {
            name = pname;
            return null;
        }
        name = null;
        Budgie.Applet applet = (extension as Budgie.Plugin).get_panel_widget(uuid);
        var info = new Budgie.AppletInfo(pinfo, uuid, applet, settings);

        return info;
    }

    /**
     * Attempt to create a fresh applet instance
     */
    public Budgie.AppletInfo? create_new_applet(string name, string uuid)
    {
        string? unused = null;
        if (!plugins.contains(name)) {
            return null;
        }
        var path = this.create_applet_path(uuid);
        var settings = new Settings.with_path(Budgie.APPLET_SCHEMA, path);
        settings.set_string(Budgie.APPLET_KEY_NAME, name);
        return this.load_applet_instance(uuid, out unused, settings);
    }

    /**
     * Find the next available position on the given monitor
     */
    public PanelPosition get_first_position(int monitor)
    {
        if (!screens.contains(monitor)) {
            error("No screen for monitor: %d - This should never happen!", monitor);
            return PanelPosition.NONE;
        }
        Screen? screen = screens.lookup(monitor);

        if ((screen.slots & PanelPosition.TOP) == 0) {
            return PanelPosition.TOP;
        } else if ((screen.slots & PanelPosition.BOTTOM) == 0) {
            return PanelPosition.BOTTOM;
        } else if ((screen.slots & PanelPosition.LEFT) == 0) {
            return PanelPosition.LEFT;
        } else if ((screen.slots & PanelPosition.RIGHT) == 0) {
            return PanelPosition.RIGHT;
        } else {
            return PanelPosition.NONE;
        }
    }

    /**
     * Determine how many slots are available
     */
    public override uint slots_available()
    {
        return MAX_SLOTS - panels.size();
    }

    /**
     * Determine how many slots have been used
     */
    public override uint slots_used()
    {
        return panels.size();
    }

    /**
     * Load a panel by the given UUID, and optionally configure it
     */
    void load_panel(string uuid, bool configure = false)
    {
        if (panels.contains(uuid)) {
            return;
        }

        string path = this.create_panel_path(uuid);
        PanelPosition position;
        int size;

        var settings = new GLib.Settings.with_path(Budgie.TOPLEVEL_SCHEMA, path);
        Budgie.Panel? panel = new Budgie.Panel(this, uuid, settings);
        panels.insert(uuid, panel);

        if (!configure) {
            return;
        }

        position = (PanelPosition)settings.get_enum(Budgie.PANEL_KEY_POSITION);
        size = settings.get_int(Budgie.PANEL_KEY_SIZE);
        panel.intended_size = (int)size;
        this.show_panel(uuid, position);
    }

    static string? pos_text(PanelPosition pos) {
        switch (pos) {
            case PanelPosition.TOP:
                return "top";
            case PanelPosition.BOTTOM:
                return "bottom";
            case PanelPosition.LEFT:
                return "left";
            case PanelPosition.RIGHT:
                return "right";
            default:
                return "none";
        }
    }

    void show_panel(string uuid, PanelPosition position)
    {
        Budgie.Panel? panel = panels.lookup(uuid);
        unowned Screen? scr;

        if (panel == null) {
            warning("Asked to show non-existent panel: %s", uuid);
            return;
        }

        scr = screens.lookup(this.primary_monitor);
        scr.slots |= position;
        this.set_placement(uuid, position);
    }

    /**
     * Set size of the given panel
     */
    public override void set_size(string uuid, int size)
    {
        Budgie.Panel? panel = panels.lookup(uuid);

        if (panel == null) {
            warning("Asked to resize non-existent panel: %s", uuid);
            return;
        }

        panel.intended_size = size;
        this.update_screen();
    }

    /**
     * Enforce panel placement
     */
    public override void set_placement(string uuid, PanelPosition position)
    {
        Budgie.Panel? panel = panels.lookup(uuid);
        string? key = null;
        Budgie.Panel? val = null;
        Budgie.Panel? conflict = null;

        if (panel == null) {
            warning("Trying to move non-existent panel: %s", uuid);
            return;
        }
        Screen? area = screens.lookup(primary_monitor);

        PanelPosition old = panel.position;

        if (old == position) {
            warning("Attempting to move panel to the same position it's already in: %s", uuid);
            return;
        }

        /* Attempt to find a conflicting position */
        var iter = HashTableIter<string,Budgie.Panel?>(panels);
        while (iter.next(out key, out val)) {
            if (val.position == position) {
                conflict = val;
                break;
            }
        }

        panel.hide();
        if (conflict != null) {
            conflict.hide();
            conflict.update_geometry(area.area, old);
            conflict.show();
            panel.hide();
            panel.update_geometry(area.area, position);
            panel.show();
        } else {
            area.slots ^= old;
            area.slots |= position;
            panel.update_geometry(area.area, position);
        }

        /* This does mean re-configuration a couple of times that could
         * be avoided, but it's just to ensure proper functioning..
         */
        this.update_screen();
        panel.show();
    }

    /**
     * Force update geometry for all panels
     */
    void update_screen()
    {
        Budgie.Toplevel? top = null;
        Budgie.Toplevel? bottom = null;

        string? key = null;
        Budgie.Panel? val = null;
        Screen? area = screens.lookup(primary_monitor);
        var iter = HashTableIter<string,Budgie.Panel?>(panels);
        while (iter.next(out key, out val)) {
            if (val.position == Budgie.PanelPosition.TOP) {
                top = val;
            } else if (val.position == Budgie.PanelPosition.BOTTOM) {
                bottom = val;
            }
            val.update_geometry(area.area, val.position, val.intended_size);
        }

        /* Let Raven update itself accordingly */
        raven.update_geometry(area.area, top, bottom);
        this.panels_changed();
    }

    /**
     * Load all known panels
     */
    bool load_panels()
    {
        string[] panels = this.settings.get_strv(Budgie.ROOT_KEY_PANELS);
        if (panels.length == 0) {
            return false;
        }

        foreach (string uuid in panels) {
            this.load_panel(uuid, true);
        }

        this.update_screen();
        return true;
    }

    public override void create_new_panel()
    {
        create_panel();
    }

    public override void delete_panel(string uuid)
    {
        if (this.slots_used() <= 1) {
            warning("Asked to delete final panel");
            return;
        }

        unowned Budgie.Panel? panel = panels.lookup(uuid);
        if (panel == null) {
            warning("Asked to delete non-existent panel: %s", uuid);
            return;
        }
        Screen? area = screens.lookup(primary_monitor);
        area.slots ^= panel.position;

        var spath = this.create_panel_path(panel.uuid);
        panels.steal(panel.uuid);
        set_panels();
        update_screen();
        panel.destroy_children();
        panel.destroy();


        var psettings = new Settings.with_path(Budgie.TOPLEVEL_SCHEMA, spath);
        this.reset_dconf_path(psettings);
    }

    void create_panel(string? name = null, KeyFile? new_defaults = null)
    {
        PanelPosition position = PanelPosition.NONE;
        int size = -1;

        if (this.slots_available() < 1) {
            warning("Asked to create panel with no slots available");
            return;
        }

        if (name != null && new_defaults != null) {
            try {
                /* Determine new panel position */
                if (new_defaults.has_key(name, "Position")) {
                    switch (new_defaults.get_string(name, "Position").down()) {
                        case "top":
                            position = PanelPosition.TOP;
                            break;
                        default:
                            position = PanelPosition.BOTTOM;
                            break;
                    }
                }
                if (new_defaults.has_key(name, "Size")) {
                    size = new_defaults.get_integer(name, "Size");
                }
            } catch (Error e) {
                warning("create_panel(): %s", e.message);
            }
        } else {
            position = get_first_position(this.primary_monitor);
            if (position == PanelPosition.NONE) {
                critical("No slots available, this should not happen");
                return;
            }
        }

        var uuid = LibUUID.new(UUIDFlags.LOWER_CASE|UUIDFlags.TIME_SAFE_TYPE);
        load_panel(uuid, false);

        set_panels();
        show_panel(uuid, position);

        if (new_defaults == null || name == null) {
            return;
        }
        /* TODO: Add size clamp */
        if (size > 0) {
            set_size(uuid, size);
        }

        var panel = panels.lookup(uuid);
        /* TODO: Pass off the configuration here.. */
        panel.create_default_layout(name, new_defaults);
    }

    /**
     * Update our known panels
     */
    void set_panels()
    {
        unowned Budgie.Panel? panel;
        unowned string? key;
        string[]? keys = null;

        var iter = HashTableIter<string,Budgie.Panel?>(panels);
        while (iter.next(out key, out panel)) {
            keys += key;
        }

        this.settings.set_strv(Budgie.ROOT_KEY_PANELS, keys);
    }

    /**
     * Create new default panel layout
     */
    void create_default()
    {
        File f = null;
        KeyFile config_file = new KeyFile();
        StringBuilder builder = new StringBuilder();
        string? line = null;
        PanelPosition pos;

        /**
         * Try in order, and load the first one that exists:
         *  - /etc/budgie-desktop/panel.ini
         *  - /usr/share/budgie-desktop/panel.ini
         *  - Built in panel.ini
         */
        string[] system_configs = {
                @"file://$(Budgie.CONFDIR)/budgie-desktop/panel.ini",
                @"file://$(Budgie.DATADIR)/budgie-desktop/panel.ini",
                "resource:///com/solus-project/budgie/panel/panel.ini"
        };

        foreach (string? filepath in system_configs) {
            try {
                f = File.new_for_uri(filepath);
                if (!f.query_exists()) {
                    continue;
                }
                var dis = new DataInputStream(f.read());
                while ((line = dis.read_line()) != null) {
                    builder.append_printf("%s\n", line);
                }
                config_file.load_from_data(builder.str, builder.len, KeyFileFlags.NONE);
                break;
            } catch (Error e) {
                warning("Failed to load default config: %s", e.message);
            }
        }

        try {
            if (!config_file.has_key("Panels", "Panels")) {
                critical("Config is missing required Panels section");
            }

            var panels = config_file.get_string_list("Panels", "Panels");

            /* Begin creating named panels */
            foreach (var panel in panels) {
                panel = panel.strip();
                pos = PanelPosition.TOP;
                if (!config_file.has_group(panel)) {
                    warning("Missing Panel config: %s", panel);
                    continue;
                }
                create_panel(panel, config_file);
            }
        } catch (Error e) {
            warning("Error configuring panels!");
        }

    }

    private void on_name_lost(DBusConnection conn, string name)
    {
        if (setup) {
            message("Replaced existing budgie-panel");
        } else {
            message("Another panel is already running. Use --replace to replace it");
        }
        Gtk.main_quit();
    }

    public void serve(bool replace = false)
    {
        var flags = BusNameOwnerFlags.ALLOW_REPLACEMENT;
        if (replace) {
            flags |= BusNameOwnerFlags.REPLACE;
        }
        Bus.own_name(BusType.SESSION, Budgie.DBUS_NAME, flags,
            on_bus_acquired, on_name_acquired, on_name_lost);
    }

    public override GLib.List<Budgie.Toplevel?> get_panels()
    {
        var list = new GLib.List<Budgie.Toplevel?>();
        unowned string? key;
        unowned Budgie.Panel? panel;
        var iter = HashTableIter<string?,Budgie.Panel?>(panels);
        while (iter.next(out key, out panel)) {
            list.append((Budgie.Toplevel)panel);
        }
        return list;
    }
}

} /* End namespace */

/*
 * Editor modelines  -  https://www.wireshark.org/tools/modelines.html
 *
 * Local variables:
 * c-basic-offset: 4
 * tab-width: 4
 * indent-tabs-mode: nil
 * End:
 *
 * vi: set shiftwidth=4 tabstop=4 expandtab:
 * :indentSize=4:tabSize=4:noTabs=true:
 */
