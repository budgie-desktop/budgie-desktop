/*
 * This file is part of budgie-desktop
 *
 * Copyright © 2015-2018 Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

namespace Budgie {

    public class SoundWidget : Gtk.Box {

        /**
         * Logic and Mixer variables
         */
        private const string MAX_KEY = "allow-volume-above-100-percent";
        private ulong scale_id = 0;
        private Gvc.MixerControl mixer = null;
        private HashTable<uint,Gtk.ListBoxRow?> apps;
        private HashTable<string,string?> derpers;
        private HashTable<uint,Gtk.RadioButton?> devices;
        private ulong primary_notify_id = 0;
        private Gvc.MixerStream? primary_stream = null;
        private Settings settings = null;
        private string widget_type = "";

        /**
         * Widgets
         */
        private Budgie.HeaderWidget? header = null;
        private Gtk.Box? apps_area = null;
        private Gtk.ListBox? apps_listbox = null;
        private Gtk.Revealer? apps_list_revealer = null;
        private Gtk.Box? devices_area = null;
        private StartListening? listening_box = null;
        private Gtk.Revealer? listening_box_revealer = null;
        private Gtk.Box? main_layout = null;
        private Gtk.RadioButton? device_leader = null;
        private Gtk.Stack? widget_area = null;
        private Gtk.StackSwitcher? widget_area_switch = null;
        private Gtk.Scale? volume_slider = null;

        public SoundWidget(string c_widget_type) {
            Object(orientation: Gtk.Orientation.VERTICAL);
            get_style_context().add_class("audio-widget");
            widget_type = c_widget_type;

            /**
             * Shared  Logic
             */
            mixer = new Gvc.MixerControl("Budgie Volume Control");

            derpers = new HashTable<string,string?>(str_hash, str_equal); // Create our GVC Stream app derpers
            derpers.insert("Vivaldi", "vivaldi"); // Vivaldi
            derpers.insert("Vivaldi Snapshot", "vivaldi-snapshot"); // Vivaldi Snapshot
            devices = new HashTable<uint,Gtk.RadioButton?>(direct_hash,direct_equal);

            /**
             * Shared Construction
             */
            devices_area = new Gtk.Box(Gtk.Orientation.VERTICAL, 10);
            main_layout = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            volume_slider = new Gtk.Scale.with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 10);
            volume_slider.set_draw_value(false);
            volume_slider.value_changed.connect(on_scale_change);

            /**
             * Type-Specific Logic and Construction
             */
            if (widget_type == "input") { // Input
                mixer.default_source_changed.connect(on_device_changed);
                mixer.input_added.connect(on_device_added);
                mixer.input_removed.connect(on_device_removed);

                /**
                 * Create our containers
                 */
                header = new Budgie.HeaderWidget("", "microphone-sensitivity-muted-symbolic", false, volume_slider);
                main_layout.pack_start(devices_area, false, false, 0); // Add devices directly to layout
                devices_area.margin_top = 10;
                devices_area.margin_bottom = 10;
            } else { // Output
                settings = new Settings("org.gnome.desktop.sound");
                apps = new HashTable<uint,Gtk.ListBoxRow?>(direct_hash,direct_equal);

                mixer.default_sink_changed.connect(on_device_changed);
                mixer.output_added.connect(on_device_added);
                mixer.output_removed.connect(on_device_removed);
                mixer.state_changed.connect(on_state_changed);
                mixer.stream_added.connect(on_stream_added);
                mixer.stream_removed.connect(on_stream_removed);
                settings.changed[MAX_KEY].connect(on_volume_safety_changed);

                /**
                 * Create our designated areas, our stack, and switcher
                 * Proceed to add those items to our main_layout
                 */
                apps_area = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
                apps_listbox = new Gtk.ListBox();
                apps_listbox.get_style_context().remove_class(Gtk.STYLE_CLASS_LIST); // Remove List styling
                apps_listbox.selection_mode = Gtk.SelectionMode.NONE;

                apps_listbox.set_sort_func((row1, row2) => { // Alphabetize items
                    var app_1 = ((AppSoundControl) row1.get_child()).app_name;
                    var app_2 = ((AppSoundControl) row2.get_child()).app_name;
                    return (strcmp(app_1, app_2) <= 0) ? -1 : 1;
                });

                apps_list_revealer = new Gtk.Revealer();
                apps_list_revealer.set_transition_duration(250);
                apps_list_revealer.set_transition_type(Gtk.RevealerTransitionType.SLIDE_UP);
                apps_list_revealer.add(apps_listbox);

                listening_box_revealer = new Gtk.Revealer();
                listening_box_revealer.set_transition_duration(250);
                listening_box_revealer.set_transition_type(Gtk.RevealerTransitionType.SLIDE_DOWN);
                listening_box = new StartListening(); // Create our start listening box
                listening_box_revealer.add(listening_box);

                apps_area.pack_start(listening_box_revealer, true, true, 0);
                apps_area.pack_end(apps_list_revealer, true, true, 0);

                widget_area = new Gtk.Stack();
                widget_area.margin_top = 10;
                widget_area.margin_bottom = 10;
                widget_area.set_transition_duration(125); // 125ms
                widget_area.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT);

                widget_area.add_titled(apps_area, "apps", _("Apps"));
                widget_area.add_titled(devices_area, "devices", _("Devices"));

                widget_area_switch = new Gtk.StackSwitcher();
                widget_area_switch.set_stack(widget_area);
                widget_area_switch.set_homogeneous(true);

                // Add marks when sound slider can go beyond 100%
                if (settings.get_boolean(MAX_KEY)) {
                    var vol_max = mixer.get_vol_max_norm();
                    volume_slider.add_mark(vol_max, Gtk.PositionType.BOTTOM, "100%");
                }

                header = new Budgie.HeaderWidget("", "audio-volume-muted-symbolic", false, volume_slider);
                main_layout.pack_start(widget_area, false, false, 0);
                main_layout.pack_start(widget_area_switch, true, false, 0);

                listening_box_revealer.set_reveal_child(false); // Don't initially show
                apps_list_revealer.set_reveal_child(false); // Don't initially show
            }

            mixer.open();

            /**
             * Widget Expansion
             */

            var expander = new Budgie.RavenExpander(header);
            expander.expanded = (widget_type != "input");

            pack_start(expander, true, true);

            var ebox = new Gtk.EventBox();
            ebox.get_style_context().add_class("raven-background");
            expander.add(ebox);
            ebox.add(main_layout);

            show_all();

            if (widget_type == "output") {
                toggle_start_listening();
            }
        }

        /**
         * on_device_added will handle when an input or output device has been added
         */
        private void on_device_added(uint id) {
            if (devices.contains(id)) { // If we already have this device
                return;
            }

            var device = (widget_type == "input") ? this.mixer.lookup_input_id(id) : this.mixer.lookup_output_id(id);

            if (device == null) {
                return;
            }

            if (device.card == null) {
                return;
            }

            var card = device.card as Gvc.MixerCard;
            var check = new Gtk.RadioButton.with_label_from_widget(this.device_leader, "%s - %s".printf(device.description, card.name));
            (check.get_child() as Gtk.Label).set_ellipsize(Pango.EllipsizeMode.END);
            (check.get_child() as Gtk.Label).max_width_chars = 30;
            check.set_data("device_id", id);
            check.toggled.connect(on_device_selected);
            devices_area.pack_start(check, false, false, 0);
            check.show_all();

            if (this.device_leader == null) {
                this.device_leader = check;
            }

            devices.insert(id, check);
            devices_area.queue_draw();
        }

        /**
         * on_device_changed will handle when a Gvc.MixerUIDevice has been changed
         */
        private void on_device_changed(uint id) {
            Gvc.MixerStream stream = (widget_type == "input") ? mixer.get_default_source() : mixer.get_default_sink(); // Set default_stream to the respective source or sink

            if (stream == this.primary_stream) { // Didn't really change
                return;
            }

            {
                var device = mixer.lookup_device_from_stream(stream);
                var did = device.get_id();
                var check = devices.lookup(did);

                if (check != null) {
                    SignalHandler.block_by_func((void*)check, (void*)on_device_selected, this);
                    check.active = true;
                    SignalHandler.unblock_by_func((void*)check, (void*)on_device_selected, this);
                }
            }

            if (this.primary_stream != null) {
                this.primary_stream.disconnect(this.primary_notify_id);
                primary_notify_id = 0;
            }

            primary_notify_id = stream.notify.connect((n,p)=> {
                if (p.name == "volume" || p.name == "is-muted") {
                    update_volume();
                }
            });

            this.primary_stream = stream;
            update_volume();
            devices_area.queue_draw();
        }

        /**
         * on_device_removed will handle when a Gvc.MixerUIDevice has been removed
         */
        private void on_device_removed(uint id) {
            Gtk.RadioButton? btn = devices.lookup(id);

            if (btn == null) {
                warning("Removing id we don\'t know about: %u", id);
                return;
            }

            devices.steal(id);
            btn.destroy();
            devices_area.queue_draw();
        }

        /**
         * get_control_for_app will get the respective inner AppSoundControl of a ListBoxRow associated with the id
         */
        private Budgie.AppSoundControl get_control_for_app(uint id) {
            Budgie.AppSoundControl? control = null;

            if (apps.contains(id)) { // Has id
                Gtk.ListBoxRow row = apps.get(id); // Get the ListBoxRow

                if (row != null) { // Row is valid
                    control = (Budgie.AppSoundControl) row.get_child();
                }
            }

            return control;
        }

        /**
         * on_device_selected will handle when a checkbox related to an input or output device is selected
         */
        private void on_device_selected(Gtk.ToggleButton? btn) {
            if (!btn.get_active()) {
                return;
            }

            uint id = btn.get_data("device_id");
            var device = (widget_type == "input") ? mixer.lookup_input_id(id) : mixer.lookup_output_id(id);

            if (device != null) {
                if (widget_type == "input") { // Input
                    mixer.change_input(device);
                } else { // Output
                    mixer.change_output(device);
                }
            }
        }

        /**
         * When our volume slider has changed
         */
        private void on_scale_change() {
            if (primary_stream == null) {
                return;
            }

            if (primary_stream.set_volume((uint32)volume_slider.get_value())) {
                Gvc.push_volume(primary_stream);
            }
        }

        /**
         * on_state_changed will handle when the state of our Mixer or its streams have changed
         */
        private void on_state_changed(uint id) {
            var stream = mixer.lookup_stream_id(id);

            if ((stream != null) && (stream.get_card_index() == -1)) { // If this is a stream (and not a card)
                if (apps.contains(id)) { // If our apps contains this stream
                    Budgie.AppSoundControl? control = get_control_for_app(id);

                    if (control != null) {
                        if (stream.is_running()) { // If running
                            control.refresh(); // Update our control
                        } else { // If not running
                            control.destroy();
                            apps.steal(id);
                        }
                    }

                    toggle_start_listening();
                }
            }
        }

        /**
         * on_stream_added will handle when a stream (like an application) has been added
         */
        private void on_stream_added(uint id) {
            Gvc.MixerStream stream = mixer.lookup_stream_id(id); // Get our stream

            if ((stream != null) && (stream.get_card_index() == -1)) { // If this isn't a card
                string name = stream.get_name();
                string icon = stream.get_icon_name();

                if (name == null) { // If this does not have a stream name (unlike bell-window-system, for example)
                    return;
                }

                if (stream.is_event_stream) { // If this is an event stream, such as volume change sounds
                    return;
                }

                if (stream.get_volume() == 100) {  // If volume doesn't match with mixer volume
                    return;
                }

                if ((icon != "") && icon.contains("audio-input-")) { // If this is a microphone (for instances when WebRTC engine returns as input)
                    return;
                }

                if (name == "System Sounds") { // If this is System Sounds
                    return;
                }

                Gvc.MixerUIDevice device = mixer.lookup_device_from_stream(stream); // Get the associated device for this

                if (device != null && !device.is_output()) { // If this is an input device
                    return;
                }

                if (derpers.contains(name)) { // If our Gvc Stream derpers contains this application
                    icon = derpers.get(name); // Use its designated icon instead
                }

                if (name == "WEBRTC VoiceEngine") { // Discord reports as WEBRTC VoiceEngine
                    icon = "discord";
                    name = "Discord";
                }

                Budgie.AppSoundControl control = new Budgie.AppSoundControl(mixer, primary_stream, stream, icon, name); // Pass our Mixer, Stream, correct Icon and Name

                if (control != null) {
                    var list_row = new Gtk.ListBoxRow();
                    list_row.add(control); // Add our control

                    apps_listbox.insert(list_row, -1); // Add our control
                    apps.insert(id, list_row); // Add to apps
                    apps_listbox.show_all();
                    toggle_start_listening();
                }
            }
        }

        /**
         * on_stream_removed will handle when a stream (like an application) has been removed
         */
        private void on_stream_removed(uint id) {
            if (apps.contains(id)) { // If this stream exists in apps
                Gtk.ListBoxRow row = apps.get(id);

                if (row != null) { // If this row exists
                    try {
                        apps_listbox.remove(row); // Remove row from listbox
                    } catch (GLib.Error e) {
                        warning("Issue during row destroy: %s", e.message);
                    }
                }

                apps.steal(id); // Remove the apps
                toggle_start_listening();
            }
        }

        /**
         * on_volume_safety_changed will listen to changes to our above 100 percent key
         * If the volume is allowed to go over 100%, we'll update the slider range. Otherwise, we'll change or keep it at 100%
         */
        private void on_volume_safety_changed() {
            bool allow_higher_than_max = settings.get_boolean(MAX_KEY);
            var current_volume = volume_slider.get_value();
            var vol_max = mixer.get_vol_max_norm();
            var vol_max_above = mixer.get_vol_max_amplified();
            var step_size = (allow_higher_than_max) ? vol_max_above / 20 : vol_max / 20;

            int slider_start = 0;
            int slider_end = 0;
            volume_slider.get_slider_range(out slider_start, out slider_end);

            if (allow_higher_than_max && (slider_end != vol_max_above)) { // If we're allowing higher than max and currently slider is not a max of 150
                volume_slider.set_increments(step_size, step_size);
                volume_slider.set_range(0, vol_max_above);
                volume_slider.set_value(current_volume);
                volume_slider.add_mark(vol_max, Gtk.PositionType.BOTTOM, "100%");
            } else if (!allow_higher_than_max && (slider_end != vol_max)) { // If we're not allowing higher than max and slider is at max
                volume_slider.set_increments(step_size, step_size);
                volume_slider.set_range(0, vol_max);
                volume_slider.set_value(current_volume);
                volume_slider.clear_marks();
            }
        }

        /**
         * toggle_start_listening will handle showing or hiding our Start Listening box if needed
         */
        private void toggle_start_listening() {
            if (widget_type == "output") { // Output
                bool apps_exist = (apps.length != 0);
                listening_box_revealer.set_reveal_child(!apps_exist); // Show if no apps, hide if apps
                apps_list_revealer.set_reveal_child(apps_exist); // Show if apps, hide if no apps
            }
        }

        /**
         * update_volume will handle updating our volume slider and output header during device change
         */
        private void update_volume() {
            var vol = primary_stream.get_volume();
            var vol_max = mixer.get_vol_max_norm();

            if ((widget_type == "output") && settings.get_boolean(MAX_KEY)) { // Allowing max
                vol_max = mixer.get_vol_max_amplified();
            }

            /* Same maths as computed by volume.js in gnome-shell, carried over
            * from C->Vala port of budgie-panel */
            int n = (int) Math.floor(3*vol/vol_max)+1;
            string image_name;

            // Work out an icon
            string icon_prefix = (widget_type == "input") ? "microphone-sensitivity-" : "audio-volume-";

            if (primary_stream.get_is_muted() || vol <= 0) {
                image_name = "muted-symbolic";
            } else {
                switch (n) {
                    case 1:
                        image_name = "low-symbolic";
                        break;
                    case 2:
                        image_name = "medium-symbolic";
                        break;
                    default:
                        image_name = "high-symbolic";
                        break;
                }
            }

            header.icon_name = icon_prefix + image_name;

            /* Each scroll increments by 5%, much better than units..*/
            var step_size = vol_max / 20;

            if (scale_id > 0) {
                SignalHandler.block(volume_slider, scale_id);
            }

            volume_slider.set_increments(step_size, step_size);
            volume_slider.set_range(0, vol_max);
            volume_slider.set_value(vol);

            if (scale_id > 0) {
                SignalHandler.unblock(volume_slider, scale_id);
            }
        }
    }
}

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
