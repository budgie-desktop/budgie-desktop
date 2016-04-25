/*
 * This file is part of budgie-desktop
 * 
 * Copyright (C) 2015-2016 Ikey Doherty <ikey@solus-project.com>
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

public class CalendarWidget : Gtk.Box
{

    private Gtk.Revealer? revealer = null;
    private Gtk.Calendar? cal = null;

    public bool expanded {
        public set {
            this.revealer.set_reveal_child(value);
        }
        public get {
            return this.revealer.get_reveal_child();
        }
        default = true;
    }

    private Budgie.HeaderWidget? header = null;

    public CalendarWidget()
    {
        Object(orientation: Gtk.Orientation.VERTICAL);

        var time = new DateTime.now_local();

        /* TODO: Fix icon */
        header = new Budgie.HeaderWidget(time.format("%x"), "x-office-calendar-symbolic", false);
        pack_start(header, false, false);

        revealer = new Gtk.Revealer();
        pack_start(revealer, false, false, 0);

        cal = new Gtk.Calendar();
        cal.get_style_context().add_class("raven-calendar");
        var ebox = new Gtk.EventBox();
        ebox.add(cal);
        ebox.get_style_context().add_class("raven-background");
        revealer.add(ebox);

        header.bind_property("expanded", this, "expanded");
        expanded = true;

        revealer.notify["child-revealed"].connect_after(()=> {
            this.get_toplevel().queue_draw();
        });
		
		cal.day_selected_double_click.connect(() => {
            try {
				GLib.DateTime cal_date = new DateTime.local(cal.year, cal.month+1, cal.day, 0, 0, 0); // Define cal_date as the local DateTime of cal props 
				string local_formatted_date = cal_date.format("%x"); // Return Date formatted based on the user's locale
                Process.spawn_command_line_async("gnome-calendar --date=" + local_formatted_date); // Attempt open gnome-calendar --date=date
            } catch (Error e) {
                message("Error invoking gnome-calendar: %s", e.message);
            }			
		});
    }

} // End class

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
