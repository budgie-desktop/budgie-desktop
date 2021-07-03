/*
 * This file is part of budgie-desktop
 *
 * Copyright © 2015-2021 Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

using LibUUID;

namespace Budgie {
	public const string DBUS_NAME = "org.budgie_desktop.Panel";
	public const string DBUS_OBJECT_PATH = "/org/budgie_desktop/Panel";

	public const string MIGRATION_1_APPLETS[] = {
		"User Indicator",
		"Raven Trigger",
	};

	/**
	* Available slots
	*/
	[Compact]
	class Screen : GLib.Object {
		public PanelPosition slots;
		public Gdk.Rectangle area;
	}

	/**
	* Permit a slot for each edge of the screen
	*/
	public const uint MAX_SLOTS = 4;

	/**
	* Root prefix for fixed schema
	*/
	public const string ROOT_SCHEMA = "com.solus-project.budgie-panel";

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
	public const string APPLET_SCHEMA = "com.solus-project.budgie-panel.applet";

	/**
	* Prefix for all relocatable applet settings
	*/
	public const string APPLET_PREFIX = "/com/solus-project/budgie-panel/applets";

	/**
	* Schema ID for Raven settings
	*/
	public const string RAVEN_SCHEMA = "com.solus-project.budgie-raven";

	/**
	* Known panels
	*/
	public const string ROOT_KEY_PANELS = "panels";

	/** Panel position */
	public const string PANEL_KEY_POSITION = "location";

	/** Panel transparency */
	public const string PANEL_KEY_TRANSPARENCY = "transparency";

	/** Panel applets */
	public const string PANEL_KEY_APPLETS = "applets";

	/** Night mode/dark theme */
	public const string PANEL_KEY_DARK_THEME = "dark-theme";

	/** Panel size */
	public const string PANEL_KEY_SIZE = "size";

	/** Autohide policy */
	public const string PANEL_KEY_AUTOHIDE = "autohide";

	/** Shadow */
	public const string PANEL_KEY_SHADOW = "enable-shadow";

	/** Dock mode */
	public const string PANEL_KEY_DOCK_MODE = "dock-mode";

	/** Theme regions permitted? */
	public const string PANEL_KEY_REGIONS = "theme-regions";

	/** Current migration level in settings */
	public const string PANEL_KEY_MIGRATION = "migration-level";

	/** Layout to select when reset/init for the first time */
	public const string PANEL_KEY_LAYOUT = "layout";

	/** Position that Raven should have when opening */
	public const string RAVEN_KEY_POSITION = "raven-position";

	/**
	* The current migration level of Budgie, or format change, if you will.
	*/
	public const int BUDGIE_MIGRATION_LEVEL = 1;


	[DBus (name="org.budgie_desktop.Panel")]
	public class PanelManagerIface {
		private Budgie.PanelManager? manager = null;

		[DBus (visible=false)]
		public PanelManagerIface(Budgie.PanelManager? manager) {
			this.manager = manager;
		}

		public string get_version() throws DBusError, IOError {
			return Budgie.VERSION;
		}

		public void ActivateAction(int action) throws DBusError, IOError {
			this.manager.activate_action(action);
		}

		public void OpenSettings() throws DBusError, IOError {
			this.manager.open_settings();
		}
	}

	public class PanelManager : DesktopManager {
		private PanelManagerIface? iface;
		bool setup = false;
		bool reset = false;

		/* Keep track of our SessionManager */
		private LibSession.SessionClient? sclient;

		HashTable<int,Screen?> screens;
		HashTable<string,Budgie.Panel?> panels;

		int primary_monitor = 0;
		Settings settings;
		Settings raven_settings;
		Peas.Engine engine;
		Peas.ExtensionSet extensions;
		FileMonitor monitor;

		HashTable<string,Peas.PluginInfo?> plugins;
		HashTable<string, string> plugin_names;
		HashTable<string, Peas.PluginInfo?> maybe_uninstalled_plugins;

		private Budgie.Raven? raven = null;
		RavenPosition raven_position;

		private Budgie.ThemeManager theme_manager;

		/* Manage all of the Budgie settings */
		private Budgie.SettingsWindow? settings_window = null;

		Wnck.Screen wnck_screen;
		List<unowned Wnck.Window> window_list;

		private string default_layout = "default";

		/**
		* Updated when specific names are queried
		*/
		private bool migrate_load_requirements_met = false;

		public void activate_action(int action) {
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

		private void end_session(bool quit) {
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

		private async bool register_with_session() {
			try {
				sclient = yield LibSession.register_with_session("budgie-panel");
			} catch (Error e) {
				return false;
			}

			sclient.QueryEndSession.connect(() => {
				end_session(false);
			});
			sclient.EndSession.connect(() => {
				end_session(false);
			});
			sclient.Stop.connect(() => {
				end_session(true);
			});
			return true;
		}

		public PanelManager(bool reset) {
			Object();
			this.reset = reset;
			screens = new HashTable<int,Screen?>(direct_hash, direct_equal);
			panels = new HashTable<string,Budgie.Panel?>(str_hash, str_equal);
			plugins = new HashTable<string,Peas.PluginInfo?>(str_hash, str_equal);
			plugin_names = new HashTable<string, string>(str_hash, str_equal);
			maybe_uninstalled_plugins = new HashTable<string, Peas.PluginInfo?>(str_hash, str_equal);
		}

		/**
		* Initial setup of the dynamic transparency routine
		* Executed after the initial setup of the panel manager
		*/
		private void do_dynamic_transparency_setup() {
			wnck_screen = Wnck.Screen.get_default();
			window_list = new List<unowned Wnck.Window>();

			wnck_screen.get_windows().foreach((window) => {
				window_list.append(window);
				window.state_changed.connect(() => {
					if (window.is_skip_pager() || window.is_skip_tasklist()) {
						return;
					}
					check_windows();
				});
			});

			wnck_screen.window_opened.connect(window_opened);
			wnck_screen.window_closed.connect(window_closed);
			wnck_screen.active_window_changed.connect(active_window_changed);
			wnck_screen.active_workspace_changed.connect(check_windows);
		}

		private void active_window_changed() {
			// Handle transparency
			check_windows();

			check_window_intersections(wnck_screen.get_active_window());
		}

		/*
		* Callback for newly opened, not yet tracked windows
		*/
		private void window_opened(Wnck.Window window) {
			unowned List<weak Wnck.Window>? element = window_list.find(window);
			if (element != null) {
				return;
			}

			window_list.append(window);

			window.state_changed.connect(() => {
				if (window.is_skip_pager() || window.is_skip_tasklist()) {
					return;
				}
				check_windows();
			});

			window.geometry_changed.connect_after((window) => {
				if (window.is_skip_pager() || window.is_skip_tasklist()) {
					return;
				}
				this.check_window_intersections(window);
			});

			check_windows();
		}

		/*
		* Callback for closed windows
		*/
		private void window_closed(Wnck.Window window) {
			unowned List<weak Wnck.Window>? element = window_list.find(window);
			if (element == null) {
				return;
			}

			window_list.remove_all(window);
			check_windows();
		}

		/**
		* Determine if the given panel and window intersect in geometry.
		* The panel is buffered by a predetermined pad amount which allows
		* for intelligent hiding behavior, i.e. when the window gets close to
		* the panel, it should start the hide.
		*/
		private bool window_intersects_panel(Budgie.Toplevel? panel, Wnck.Window? window) {
			const int pad_amount = 15;
			Gdk.Rectangle win = Gdk.Rectangle();
			Gdk.Rectangle pan = Gdk.Rectangle();

			if (window == null && this.window_list.length() == 0) {
				return false;
			}

			if (window != wnck_screen.get_active_window()) {
				return false;
			}

			if (window.is_skip_pager() || window.is_skip_tasklist()) {
				return false;
			}

			// Figure out where the window is
			window.get_geometry(out win.x, out win.y, out win.width, out win.height);

			// Figure out where the toplevel is
			panel.get_position(out pan.x, out pan.y);
			panel.get_size(out pan.width, out pan.height);

			// Pad our values to get some "near" behavior
			pan.x -= pad_amount;
			pan.width += 2 * pad_amount;

			pan.y -= pad_amount;
			pan.height += 2 * pad_amount;

			return win.intersect(pan, null);
		}

		/**
		* Check all windows against all panels for intersections
		*
		* An intersection is classified by a buffer zone match to allow dodging
		* "near" windows automatically.
		*/
		void check_window_intersections(Wnck.Window? window) {
			Budgie.Panel? panel = null;
			var iter = HashTableIter<string,Budgie.Panel?>(panels);

			while (iter.next(null, out panel)) {
				// Let the panel know it has been intersected
				if (panel.autohide != AutohidePolicy.INTELLIGENT) {
					continue;
				}
				bool b = panel.intersected;
				bool bn = this.window_intersects_panel(panel, window);
				if (b == bn) {
					continue;
				}
				panel.intersected = bn;
			}
		}

		/**
		* Determine if the window is on the primary screen, i.e. where the main
		* budgie panels will show
		*/
		bool window_on_primary(Wnck.Window? window) {
			Gdk.Rectangle area = Gdk.Rectangle();
			window.get_geometry(out area.x, out area.y, out area.width, out area.height);
			var primary = screens.lookup(this.primary_monitor);
			return area.intersect(primary.area, null);
		}

		/*
		* Decide wether or not the panel should be opaque
		* The panel should be opaque when:
		* - Raven is open
		* - a window fills these requirements:
		*   - Maximized horizontally or verically
		*   - Not minimized/iconified
		*   - On the current active workspace
		*/
		public void check_windows() {
			if (raven.get_expanded()) {
				set_panel_transparent(false, true);
				return;
			}
			bool found = false;

			window_list.foreach((window) => {
				bool is_maximized = (window.is_maximized_horizontally() || window.is_maximized_vertically());
				if (window.get_workspace() != wnck_screen.get_active_workspace()) {
					return;
				}
				if (window.is_skip_pager() || window.is_skip_tasklist()) {
					return;
				}
				if (!this.window_on_primary(window)) {
					return;
				}
				if ((is_maximized && !window.is_minimized())) {
					found = true;
					return;
				}
			});

			set_panel_transparent(!found);
		}

		/*
		* Control the transparency for panels with dynamic transparency on
		*/
		void set_panel_transparent(bool transparent, bool raven_force = false) {
			Budgie.Panel? panel = null;
			var iter = HashTableIter<string,Budgie.Panel?>(panels);
			while (iter.next(null, out panel)) {
				if (panel.transparency == PanelTransparency.DYNAMIC) {
					panel.set_transparent(transparent);
				}
				if (panel.autohide == AutohidePolicy.AUTOMATIC) {
					panel.set_occluded(raven_force ? transparent : !transparent);
				}
			}
		}

		/**
		* Attempt to reset the given path
		*/
		public void reset_dconf_path(Settings? settings) {
			if (settings == null) {
				return;
			}
			string path = settings.path;
			Settings.sync();
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
			Settings.sync();
		}

		public Budgie.AppletInfo? get_applet(string key) {
			return null;
		}

		string create_panel_path(string uuid) {
			return "%s/{%s}/".printf(Budgie.TOPLEVEL_PREFIX, uuid);
		}

		string create_applet_path(string uuid) {
			return "%s/{%s}/".printf(Budgie.APPLET_PREFIX, uuid);

		}

		/**
		* Discover all possible monitors, and move things accordingly.
		* In future we'll support per-monitor panels, but for now everything
		* must be in one of the edges on the primary monitor
		*/
		public void on_monitors_changed() {
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
			Gdk.Rectangle raven_screen;

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

			raven_screen = primary.area;
			if (top != null) {
				raven_screen.y += (top.intended_size - 5);
				raven_screen.height -= (top.intended_size - 5);
			}
			if (bottom != null) {
				raven_screen.height -= bottom.intended_size - 5;
			}


			this.raven.update_geometry(raven_screen);
		}

		private void on_bus_acquired(DBusConnection conn) {
			try {
				iface = new PanelManagerIface(this);
				conn.register_object(Budgie.DBUS_OBJECT_PATH, iface);
			} catch (Error e) {
				stderr.printf("Error registering PanelManager: %s\n", e.message);
				Process.exit(1);
			}
		}

		public void on_name_acquired(DBusConnection conn, string name) {
			this.setup = true;
			/* Well, off we go to be a panel manager. */
			do_setup();
			do_dynamic_transparency_setup();
		}

		/**
		* Reset the entire panel configuration
		*/
		void do_reset() {
			message("Resetting budgie-panel configuration to defaults");
			Settings s = new Settings(Budgie.ROOT_SCHEMA);
			this.default_layout = s.get_string(PANEL_KEY_LAYOUT);
			this.reset_dconf_path(s);
			// Preserve the default layout once more
			s = new Settings(Budgie.ROOT_SCHEMA);
			s.set_string(PANEL_KEY_LAYOUT, this.default_layout);
		}

		/**
		* Reset after a failed load
		*/
		void do_live_reset() {
			message("Resetting budgie-panel configuration due to failed load");

			string[]? toplevel_ids = null;

			foreach (var toplevel in this.get_panels()) {
				toplevel_ids += toplevel.uuid;
			}

			if (toplevel_ids != null) {
				foreach (var toplevel_id in toplevel_ids) {
					this.delete_panel(toplevel_id);
				}
			}

			this.do_reset();
		}

		/**
		* Initial setup, once we've owned the dbus name
		* i.e. no risk of dying
		*/
		void do_setup() {
			if (this.reset) {
				this.do_reset();
			}
			var scr = Gdk.Screen.get_default();
			primary_monitor = scr.get_primary_monitor();
			scr.monitors_changed.connect(this.on_monitors_changed);
			scr.size_changed.connect(this.on_monitors_changed);

			settings = new Settings(Budgie.ROOT_SCHEMA);

			// Listen to the Raven position setting for changes
			raven_settings = new Settings(RAVEN_SCHEMA);
			raven_position = (RavenPosition)raven_settings.get_enum(RAVEN_KEY_POSITION);
			raven_settings.changed[RAVEN_KEY_POSITION].connect(() => {
				RavenPosition new_position = (RavenPosition)raven_settings.get_enum(RAVEN_KEY_POSITION);
				if (new_position != raven_position) {
					raven_position = new_position;

					// Raven needs to know about its new position
					update_screen();
				}
			});
			
			this.default_layout = settings.get_string(PANEL_KEY_LAYOUT);
			theme_manager = new Budgie.ThemeManager();
			raven = new Budgie.Raven(this);
			raven.request_settings_ui.connect(this.on_settings_requested);

			/* Ensure we only have wnck initialised once otherwise everything goes cranky */
			Wnck.set_client_type(Wnck.ClientType.PAGER);

			this.on_monitors_changed();

			/* Some applets might want raven */
			raven.setup_dbus();

			setup_plugins();

			int current_migration_level = settings.get_int(PANEL_KEY_MIGRATION);
			if (!load_panels()) {
				message("Creating default panel layout");

				// TODO: Add gsetting for this name
				create_default(this.default_layout);

			} else {
				/* Migration required */
				perform_migration(current_migration_level);
			}

			/* Whatever route we took, set the migration level to the current now */
			settings.set_int(PANEL_KEY_MIGRATION, BUDGIE_MIGRATION_LEVEL);

			register_with_session.begin((o, res) => {
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
		private void perform_migration(int current_migration_level) {
			Budgie.Panel? top = null;
			Budgie.Panel? last = null;

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

			/* Ask this panel to perform migratory tasks(add applets) */
			((Budgie.Panel) last).perform_migration(current_migration_level);
		}

		/**
		* Initialise the plugin engine, paths, loaders, etc.
		*/
		void setup_plugins() {
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
			engine.load_plugin.connect_after((i) => {
				Peas.Extension? e = extensions.get_extension(i);
				if (e == null) {
					critical("Failed to find extension for: %s", i.get_name());
					return;
				}
				on_extension_added(i, e);
			});
			engine.unload_plugin.connect_after((i) => {
				plugins.remove(i.get_name());
			});

			// Start watching the plugins directory so we can load/unload plugins without
			// having to restart Budgie
			var directory = File.new_for_path(Budgie.MODULE_DIRECTORY);
			try {
				monitor = directory.monitor_directory(FileMonitorFlags.NONE, null);
				monitor.changed.connect(on_files_changed);
			} catch (IOError err) {
				warning("Failed to create file monitor on plugin directory: %s", err.message);
			}
		}

		/**
		* Handles dynamically loading and unloading plugins.
		*
		* When a plugin directory is created, we'll trigger a rescan of the
		* plugins and add any new ones.
		*
		* When a plugin directory is deleted, all we can do is check to see if
		* it's currently loaded (meaning it's actually on a panel somewhere) and
		* unload it. Libpeas does not actually have a way to "uninstall" a plugin
		* further than that, so it will still show up in the Settings applet list
		* until Budgie is restarted.
		*/
		void on_files_changed(File src, File? dest, FileMonitorEvent event) {
			switch (event) {
				case FileMonitorEvent.CREATED: // Plugin was added, trigger a rescan
					// Some, if not all, package managers where Budgie can be expected
					// to be used will delete the previous changed files and move the
					// new ones in during an update. Remove the entry in our map so that
					// it doesn't mistakingly get deleted from people's panels.
					var name = plugin_names.get(src.get_path());
					if (name != null) {
						maybe_uninstalled_plugins.remove(name);
					}

					// Rescan plugins in both cases of a new plugin or a plugin update.
					// We do this after a delay to ensure that they get picked up and loaded.
					Timeout.add_seconds(10, () => {
						engine.rescan_plugins();
						return false;
					});
					break;
				case FileMonitorEvent.DELETED: // Plugin was removed, unload it from panels
					var name = plugin_names.get(src.get_path());
					if (name != null) { // Path is in our map, maybe unload it
						var info = plugins.get(name);
						if (info != null) {
							maybe_uninstalled_plugins.insert(name, info);

							// Wait a few seconds to see if the plugin was re-added, such as
							// during a package update
							Timeout.add_seconds(10, () => {
								maybe_unload_plugin(name, src.get_path());
								return false;
							});
						}
					}
					break;
				default: // We only care about files being created or deleted
					break;
			}
		}

		/**
		 * Removes an applet from any panels and unloads it if it is in
		 * our collection of applets that might be uninstalled.
		 */
		void maybe_unload_plugin(string name, string path) {
			var plugin = maybe_uninstalled_plugins.get(name);
			if (plugin != null) {
				// Remove any loaded instances of this applet from all panels
				foreach (var panel in panels.get_values()) {
					foreach (unowned var applet in panel.get_applets()) {
						if (applet.name == name) {
							panel.remove_applet(applet);
						}
					}
				}

				engine.try_unload_plugin(plugin);
				plugins.remove(name);
				plugin_names.remove(path);
				maybe_uninstalled_plugins.remove(name);
			}
		}

		/**
		* Indicate that a plugin that was being waited for, is now available
		*/
		public signal void extension_loaded(string name);

		/**
		* Handle extension loading
		*/
		void on_extension_added(Peas.PluginInfo? info, Object p) {
			if (plugins.contains(info.get_name())) {
				return;
			}
			plugins.insert(info.get_name(), info);
			plugin_names.insert(info.get_module_dir(), info.get_name());
			extension_loaded(info.get_name());
		}

		public bool is_extension_loaded(string name) {
			if (name in MIGRATION_1_APPLETS) {
				migrate_load_requirements_met = true;
			}
			return plugins.contains(name);
		}

		/**
		* Determine if the extension is known to be valid
		*/
		public bool is_extension_valid(string name) {
			if (name in MIGRATION_1_APPLETS) {
				migrate_load_requirements_met = true;
			}
			if (this.get_plugin_info(name) == null) {
				return false;
			}
			return true;
		}

		public override List<Peas.PluginInfo?> get_panel_plugins() {
			List<Peas.PluginInfo?> ret = new List<Peas.PluginInfo?>();
			foreach (unowned Peas.PluginInfo? info in this.engine.get_plugin_list()) {
				ret.append(info);
			}
			return ret;
		}

		/**
		* PeasEngine.get_plugin_info == completely broken
		*/
		private unowned Peas.PluginInfo? get_plugin_info(string name) {
			foreach (unowned Peas.PluginInfo? info in this.engine.get_plugin_list()) {
				if (info.get_name() == name) {
					return info;
				}
			}
			return null;
		}

		public void modprobe(string name) {
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
		public Budgie.AppletInfo? load_applet_instance(string? uuid, out string name, Settings? psettings = null) {
			var path = this.create_applet_path(uuid);
			Settings? settings = null;
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
			Budgie.Applet applet = ((Budgie.Plugin) extension).get_panel_widget(uuid);
			return new Budgie.AppletInfo(pinfo, uuid, applet, settings);
		}

		/**
		* Attempt to create a fresh applet instance
		*/
		public Budgie.AppletInfo? create_new_applet(string name, string uuid) {
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
		public PanelPosition get_first_position(int monitor) {
			if (!screens.contains(monitor)) {
				error("No screen for monitor: %d - This should never happen!", monitor);
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
		public override uint slots_available() {
			return MAX_SLOTS - panels.size();
		}

		/**
		* Determine how many slots have been used
		*/
		public override uint slots_used() {
			return panels.size();
		}

		/**
		* Load a panel by the given UUID, and optionally configure it
		*/
		void load_panel(string uuid, bool configure = false) {
			if (panels.contains(uuid)) {
				return;
			}

			string path = this.create_panel_path(uuid);
			PanelPosition position;
			PanelTransparency transparency;
			AutohidePolicy policy;
			int size;

			var settings = new Settings.with_path(Budgie.TOPLEVEL_SCHEMA, path);
			Budgie.Panel? panel = new Budgie.Panel(this, uuid, settings);
			panels.insert(uuid, panel);

			if (!configure) {
				return;
			}

			position = (PanelPosition)settings.get_enum(Budgie.PANEL_KEY_POSITION);
			transparency = (PanelTransparency)settings.get_enum(Budgie.PANEL_KEY_TRANSPARENCY);
			policy = (AutohidePolicy)settings.get_enum(Budgie.PANEL_KEY_AUTOHIDE);

			panel.transparency = transparency;
			panel.autohide = policy;

			size = settings.get_int(Budgie.PANEL_KEY_SIZE);
			panel.intended_size = (int)size;
			this.show_panel(uuid, position, transparency);
		}

		void show_panel(string uuid, PanelPosition position, PanelTransparency transparency) {
			Budgie.Panel? panel = panels.lookup(uuid);
			unowned Screen? scr;

			if (panel == null) {
				warning("Asked to show non-existent panel: %s", uuid);
				return;
			}

			scr = screens.lookup(this.primary_monitor);
			scr.slots |= position;
			this.set_placement(uuid, position);
			this.set_transparency(uuid, transparency);
		}

		/**
		* Set size of the given panel
		*/
		public override void set_size(string uuid, int size) {
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
		public override void set_placement(string uuid, PanelPosition position) {
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
				warning("Attempting to move panel to the same position it's already in: %s %s %s", uuid, old.to_string(), position.to_string());
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
		* Set panel transparency
		*/
		public override void set_transparency(string uuid, PanelTransparency transparency) {
			Budgie.Panel? panel = panels.lookup(uuid);

			if (panel == null) {
				warning("Trying to set transparency on non-existent panel: %s", uuid);
				return;
			}

			panel.update_transparency(transparency);
		}


		public override void set_autohide(string uuid, Budgie.AutohidePolicy policy) {
			Budgie.Panel? panel = panels.lookup(uuid);

			if (panel == null) {
				warning("Trying to set autohide on non-existent panel: %s", uuid);
				return;
			}
			panel.set_autohide_policy(policy);

			// Raven needs to know about the autohide mode
			this.update_screen();
		}

		/**
		* Set panel dock mode
		*/
		public override void set_dock_mode(string uuid, bool dock_mode) {
			Budgie.Panel? panel = panels.lookup(uuid);

			if (panel == null) {
				warning("Trying to set dock mode on non-existent panel: %s", uuid);
				return;
			}

			panel.dock_mode = dock_mode;

			// Raven needs to know about the dock mode
			this.update_screen();
		}

		/**
		* Force update geometry for all panels
		*/
		void update_screen() {
			Budgie.Toplevel? top = null;
			Budgie.Toplevel? bottom = null;
			Budgie.Toplevel? right = null;
			Budgie.Toplevel? left = null;
			Gdk.Rectangle raven_screen;

			string? key = null;
			Budgie.Panel? val = null;
			Screen? area = screens.lookup(primary_monitor);
			var iter = HashTableIter<string,Budgie.Panel?>(panels);

			// First loop, edges that conflict with Raven
			while (iter.next(out key, out val)) {
				switch (val.position) {
				case Budgie.PanelPosition.TOP:
					top = val;
					break;
				case Budgie.PanelPosition.BOTTOM:
					bottom = val;
					break;
				case Budgie.PanelPosition.RIGHT:
					right = val;
					break;
				case Budgie.PanelPosition.LEFT:
					left = val;
					break;
				default:
					continue;
				}
			}

			var iter2 = HashTableIter<string,Budgie.Panel?>(panels);

			string? key2 = null;
			Budgie.Panel? val2 = null;

			while (iter2.next(out key2, out val2)) {
				switch (val2.position) {
				case Budgie.PanelPosition.LEFT:
				case Budgie.PanelPosition.RIGHT:
					Gdk.Rectangle geom = Gdk.Rectangle();
					geom.x = area.area.x;
					geom.y = area.area.y;
					geom.width = area.area.width;
					geom.height = area.area.height;
					if (this.is_panel_huggable(top)) {
						geom.y += top.intended_size - 5;
						geom.height -= top.intended_size - 5;
					}
					if (this.is_panel_huggable(bottom)) {
						geom.height -= bottom.intended_size - 5;
					}
					val2.update_geometry(geom, val2.position, val2.intended_size);
					break;
				default:
					val2.update_geometry(area.area, val2.position, val2.intended_size);
					break;
				}
			}

			raven_screen = area.area;
			if (top != null && !top.dock_mode && top.autohide == AutohidePolicy.NONE) {
				raven_screen.y += (top.intended_size - 5);
				raven_screen.height -= (top.intended_size - 5);
			}

			if (bottom != null && !bottom.dock_mode && bottom.autohide == AutohidePolicy.NONE) {
				raven_screen.height -= bottom.intended_size - 5;
			}

			// Set which side of the screen Raven should appear on
			switch (raven_position) {
				case RavenPosition.LEFT:
					/* Stick/maybe hug left */
					raven.screen_edge = Gtk.PositionType.LEFT;
					if (left != null) {
						raven_screen.x += left.intended_size;
					}
					break;
				case RavenPosition.RIGHT:
					/* Stick/maybe hug right */
					raven.screen_edge = Gtk.PositionType.RIGHT;
					if (right != null) {
						raven_screen.width -= (right.intended_size);
					}
					break;
				case RavenPosition.AUTOMATIC:
				default:
					set_raven_position(left, right, ref raven_screen);
					break;
			}

			/* Let Raven update itself accordingly */
			raven.update_geometry(raven_screen);
			this.panels_changed();
		}

		bool is_panel_huggable(Budgie.Toplevel? panel) {
			if (panel == null) {
				return false;
			}
			if (panel.autohide != AutohidePolicy.NONE) {
				return false;
			}
			if (panel.dock_mode) {
				return false;
			}
			return true;
		}

		/**
		 * Use the current panel layouts to figure out Raven's position.
		 *
		 * This function sets which side of the screen Raven should be on,
		 * as well as Raven's position or width (if it's on the right side).
		 */
		void set_raven_position(Toplevel? left, Toplevel? right, ref Gdk.Rectangle raven_screen) {
			if (left != null && right == null) {
				if (this.is_panel_huggable(left)) {
					/* Hug left */
					raven.screen_edge = Gtk.PositionType.LEFT;
					raven_screen.x += left.intended_size;
				} else {
					/* Stick right */
					raven.screen_edge = Gtk.PositionType.RIGHT;
				}
			} else if (right != null && left == null) {
				if (this.is_panel_huggable(right)) {
					/* Hug right */
					raven_screen.width -= (right.intended_size);
					raven.screen_edge = Gtk.PositionType.RIGHT;
				} else {
					/* Stick left */
					raven.screen_edge = Gtk.PositionType.LEFT;
				}
			} else if (is_panel_huggable(left) && !is_panel_huggable(right)) {
				/* Hug left */
				raven.screen_edge = Gtk.PositionType.LEFT;
				raven_screen.x += left.intended_size;
			} else if (is_panel_huggable(right) && !is_panel_huggable(left)) {
				/* Hug right */
				raven_screen.width -= (right.intended_size);
				raven.screen_edge = Gtk.PositionType.RIGHT;
			} else {
				/* Stick/maybe hug right */
				raven.screen_edge = Gtk.PositionType.RIGHT;
				if (right != null) {
					raven_screen.width -= (right.intended_size);
				}
			}
		}

		/**
		* Load all known panels
		*/
		bool load_panels() {
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

		public override void create_new_panel() {
			create_panel();
		}

		public override void delete_panel(string uuid) {
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

			this.panel_deleted(uuid);

			var spath = this.create_panel_path(panel.uuid);
			panels.steal(panel.uuid);
			set_panels();
			update_screen();
			panel.destroy_children();
			panel.destroy();


			var psettings = new Settings.with_path(Budgie.TOPLEVEL_SCHEMA, spath);
			this.reset_dconf_path(psettings);
		}

		void create_panel(string? name = null, KeyFile? new_defaults = null) {
			PanelPosition position = PanelPosition.NONE;
			PanelTransparency transparency = PanelTransparency.NONE;
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
							case "left":
								position = PanelPosition.LEFT;
								break;
							case "right":
								position = PanelPosition.RIGHT;
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

			string path = this.create_panel_path(uuid);
			var settings = new GLib.Settings.with_path(Budgie.TOPLEVEL_SCHEMA, path);
			transparency = (PanelTransparency)settings.get_enum(Budgie.PANEL_KEY_TRANSPARENCY);

			show_panel(uuid, position, transparency);

			if (new_defaults == null || name == null) {
				this.panel_added(uuid, panels.lookup(uuid));
				return;
			}
			/* TODO: Add size clamp */
			if (size > 0) {
				set_size(uuid, size);
			}

			var panel = panels.lookup(uuid);
			/* TODO: Pass off the configuration here.. */
			panel.create_default_layout(name, new_defaults);
			this.panel_added(uuid, panel);
		}

		/**
		* Update our known panels
		*/
		void set_panels() {
			unowned Budgie.Panel? panel;
			unowned string? key;
			string[]? keys = null;

			var iter = HashTableIter<string,Budgie.Panel?>(panels);
			while (iter.next(out key, out panel)) {
				keys += key;
			}

			this.settings.set_strv(Budgie.ROOT_KEY_PANELS, keys);
		}

		void create_default(string layout_name) {
			if (layout_name == "default") {
				this.create_system_default();
				return;
			}

			// /etc/budgie-desktop/layouts then /usr/share/budgie-desktop/layouts
			string[] panel_dirs = {
				Budgie.CONFDIR,
				Budgie.DATADIR
			};

			foreach (string panel_dir in panel_dirs) {
				string path = "file://%s/budgie-desktop/layouts/%s.layout".printf(panel_dir, layout_name);
				if (this.load_default_from_config(path)) {
					return;
				}
			}

			warning("Failed to find layout '%s'", layout_name);

			// Absolute fallback = built in INI config
			this.load_default_from_config("resource:///com/solus-project/budgie/panel/panel.ini");
		}


		/**
		* Create new default panel layout
		*/
		void create_system_default() {
			/**
			* Try in order, and load the first one that exists:
			* - /etc/budgie-desktop/panel.ini
			* - /usr/share/budgie-desktop/panel.ini
			* - Built in panel.ini
			*/
			string[] system_configs = {
				@"file://$(Budgie.CONFDIR)/budgie-desktop/panel.ini",
				@"file://$(Budgie.DATADIR)/budgie-desktop/panel.ini",
				""
			};

			foreach (string? filepath in system_configs) {
				if (this.load_default_from_config(filepath)) {
					return;
				}
			}

			this.load_default_from_config("resource:///com/solus-project/budgie/panel/panel.ini");
		}


		/**
		* Attempt to load the configuration from the given URL
		*/
		bool load_default_from_config(string uri) {
			File f = null;
			KeyFile config_file = new KeyFile();
			StringBuilder builder = new StringBuilder();
			string? line = null;
			PanelPosition pos;

			try {
				f = File.new_for_uri(uri);
				if (!f.query_exists()) {
					return false;
				}
				var dis = new DataInputStream(f.read());
				while ((line = dis.read_line()) != null) {
					builder.append_printf("%s\n", line);
				}
				config_file.load_from_data(builder.str, builder.len, KeyFileFlags.NONE);
			} catch (Error e) {
				warning("Failed to load default config: %s", e.message);
				return false;
			}

			try {
				if (!config_file.has_key("Panels", "Panels")) {
					warning("Config is missing required Panels section");
					return false;
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
				this.do_live_reset();
				return false;
			}
			return true;
		}

		private void on_name_lost(DBusConnection conn, string name) {
			if (setup) {
				message("Replaced existing budgie-panel");
			} else {
				message("Another panel is already running. Use --replace to replace it");
			}
			Gtk.main_quit();
		}

		public void serve(bool replace = false) {
			var flags = BusNameOwnerFlags.ALLOW_REPLACEMENT;
			if (replace) {
				flags |= BusNameOwnerFlags.REPLACE;
			}
			Bus.own_name(BusType.SESSION, Budgie.DBUS_NAME, flags,
				on_bus_acquired, on_name_acquired, on_name_lost);
		}

		public override List<Budgie.Toplevel?> get_panels() {
			var list = new List<Budgie.Toplevel?>();
			unowned string? key;
			unowned Budgie.Panel? panel;
			var iter = HashTableIter<string?,Budgie.Panel?>(panels);
			while (iter.next(out key, out panel)) {
				list.append((Budgie.Toplevel)panel);
			}
			return list;
		}

		/* Raven asked for the settings to be shown */
		private void on_settings_requested() {
			this.open_settings();
		}

		/**
		* Open up the settings window on screen
		*/
		public void open_settings() {
			Idle.add(() => {
				if (this.settings_window == null) {
					this.settings_window = new Budgie.SettingsWindow(this);
					this.settings_window.destroy.connect(() => {
						this.settings_window = null;
					});

					/* Say hullo to the settings_window */
					foreach (var panel in this.get_panels()) {
						this.panel_added(panel.uuid, panel);
					}
				}
				this.settings_window.present();
				this.settings_window.grab_focus();
				Gdk.Window? window = this.settings_window.get_window();
				if (window != null) {
					window.focus(Gdk.CURRENT_TIME);
				}
				return false;
			});
		}
	}
}
