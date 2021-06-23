/*
 * This file is part of budgie-desktop
 *
 * Copyright © 2016-2021 Budgie Desktop Developers
 * Copyright (C) GNOME Shell Developers (Heavy inspiration, logic theft)
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

namespace Budgie {
	/**
	* IBusManager is responsible for interfacing with the ibus daemon
	* under Budgie Desktop, enabling extra input sources to be used
	* when using the ibus XIM daemon
	*/
	public class IBusManager : GLib.Object {
		private IBus.Bus? bus = null;
		private bool ibus_available = true;

		private HashTable<string,weak IBus.EngineDesc> engines = null;
		private List<IBus.EngineDesc>? enginelist = null;

		public unowned Budgie.KeyboardManager? kbm { construct set ; public get; }

		private bool did_ibus_init = false;

		/**
		* Ensure that owning process knows we're up and running
		*/
		public signal void ready();

		/**
		* Construct a new IBusManager which will begin setting up the
		* ibus daemon, as well as registering events to connect to it
		* and monitor it.
		*/
		public IBusManager(Budgie.KeyboardManager? kbm) {
			Object(kbm: kbm);
		}

		public void do_init() {
			/* No ibus-daemon = no ibus manager */
			if (Environment.find_program_in_path("ibus-daemon") == null) {
				message("ibus-daemon unsupported on this system");
				this.ibus_available = false;
				this.ready();
				return;
			}

			this.engines = new HashTable<string,weak IBus.EngineDesc>(str_hash, str_equal);

			/* Get the bus */
			bus = new IBus.Bus();

			/* Hook up basic signals */
			bus.connected.connect(this.ibus_connected);
			bus.disconnected.connect(this.ibus_disconnected);
			bus.set_watch_dbus_signal(true);

			/* Should have ibus running already */
			if (bus.is_connected()) {
				this.ibus_connected();
			} else {
				/* Start the ibus daemon */
				this.startup_ibus();
			}
		}

		/**
		* Launch the daemon as a child process so that it dies when we die
		*/
		private void startup_ibus() {
			string[] cmdline = {"ibus-daemon", "--xim", "--daemonize"};
			try {
				new Subprocess.newv(cmdline, SubprocessFlags.NONE);
			} catch (Error e) {
				message("Failed to launch ibus: %s", e.message);
				this.ibus_available = false;
			}
		}

		/**
		* Something on ibus changed so we'll reset our state
		*/
		private void reset_ibus() {
			this.engines = new HashTable<string,weak IBus.EngineDesc>(str_hash, str_equal);
		}

		private void on_engines_get(Object? o, AsyncResult? res) {
			try {
				this.enginelist = this.bus.list_engines_async_finish(res);
				this.reset_ibus();
				/* Store reference to the engines */
				foreach (var engine in this.enginelist) {
					this.engines[engine.get_name()] = engine;
				}
			} catch (Error e) {
				message("Failed to get engines: %s", e.message);
				this.reset_ibus();
				return;
			}
			this.ready();
		}

		/**
		* We gained connection to the ibus daemon
		*/
		private void ibus_connected() {
			/*
			* Init ibus if necessary, to ensure we have the types available to
			* glib. After this, try and gain all the engines
			*/
			if (!did_ibus_init) {
				IBus.init();
				did_ibus_init = true;
			}
			this.bus.list_engines_async.begin(-1, null, on_engines_get);
		}

		/**
		* Lost connection to ibus
		*/
		private void ibus_disconnected() {
			this.reset_ibus();
		}

		/**
		* Attempt to grab the ibus engine for the given name if it
		* exists, or returns null
		*/
		public unowned IBus.EngineDesc? get_engine(string name) {
			if (this.engines == null) {
				return null;
			}
			return this.engines.lookup(name);
		}

		const int ENGINE_SET_TIMEOUT = 4000;

		/**
		* Set the ibus engine to the specified engine name
		*/
		public void set_engine(string name) {
			if (!this.ibus_available) {
				this.kbm.release_keyboard();
				return;
			}

			this.bus.set_global_engine_async.begin(name, ENGINE_SET_TIMEOUT, null, () => {
				this.kbm.release_keyboard();
			});
		}
	}
}
