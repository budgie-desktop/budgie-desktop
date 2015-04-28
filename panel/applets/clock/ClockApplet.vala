/*
 * ClockApplet.vala
 * 
 * Copyright 2014 Ikey Doherty <ikey.doherty@gmail.com>
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

public class ClockApplet : Budgie.Plugin, Peas.ExtensionBase
{
    public Budgie.Applet get_panel_widget()
    {
        return new ClockAppletImpl();
    }
}

enum ClockFormat {
    TWENTYFOUR = 0,
    TWELVE = 1;
}

public class ClockAppletImpl : Budgie.Applet
{

    protected Gtk.EventBox widget;
    protected Gtk.Label clock;
    protected Gtk.Calendar cal;
    protected Budgie.Popover pop;

    protected bool ampm = false;
    protected bool show_seconds = false;
    protected bool show_date = false;

    private DateTime time;
    private int day;

    protected Settings settings;

    public ClockAppletImpl()
    {
        settings = new Settings("org.gnome.desktop.interface");
        widget = new Gtk.EventBox();
        clock = new Gtk.Label("");
        cal = new Gtk.Calendar();
        time = new DateTime.now_local();
        widget.add(clock);

        // check current month
        cal.month_changed.connect(() => {
            if(cal.month+1 == time.get_month())
                cal.mark_day(time.get_day_of_month());
            else
                cal.unmark_day(time.get_day_of_month());
        });

        // Interesting part - calender in a popover :)
        pop = new Budgie.Popover();

        /**
         *  Clock Settings
         */
        Budgie.Popover settings_pop = new Budgie.Popover();
        Gtk.Box settings_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 5);

        Gtk.CheckButton 24hour = new Gtk.CheckButton.with_label("24-Hour format");
        Gtk.CheckButton seconds = new Gtk.CheckButton.with_label("Show seconds");
        Gtk.CheckButton date = new Gtk.CheckButton.with_label("Show date");
        Gtk.Entry formatstring = new Gtk.Entry();

        24hour.toggled.connect((check)=> {
            if(check.get_active())
                formatstring.set_text("24h");
            else
                formatstring.set_text("12h");
        });

        settings.bind("clock-format", formatstring, "text", SettingsBindFlags.DEFAULT);
        settings.bind("clock-show-seconds", seconds, "active", SettingsBindFlags.DEFAULT);
        settings.bind("clock-show-date", date, "active", SettingsBindFlags.DEFAULT);

        settings_box.pack_start(24hour, false, false, 0);
        settings_box.pack_start(seconds, false, false, 0);
        settings_box.pack_start(date, false, false, 0);
        settings_pop.add(settings_box);

        widget.button_release_event.connect((e)=> {
            if (e.button == 1) {
                pop.present(clock);
                return true;
            } else if (e.button == 3) {
                settings_pop.present(clock);
                return true;
            }
            return false;
        });
        pop.add(cal);
        Timeout.add_seconds_full(GLib.Priority.LOW, 1, update_clock);

        settings.changed.connect(on_settings_change);
        on_settings_change("clock-format");
        on_settings_change("clock-show-seconds");
        on_settings_change("clock-show-date");
        update_clock();
        add(widget);
        show_all();
        position_changed.connect(on_position_change);
    }

    protected void on_position_change(Budgie.PanelPosition position)
    {
        switch (position) {
            case Budgie.PanelPosition.LEFT:
                clock.set_angle(90);
                break;
            case Budgie.PanelPosition.RIGHT:
                clock.set_angle(-90);
                break;
            default:
                clock.set_angle(0);
                break;
        }
    }

    protected void on_settings_change(string key)
    {
        switch (key) {
            case "clock-format":
                ClockFormat f = (ClockFormat)settings.get_enum(key);
                ampm = f == ClockFormat.TWELVE;
                break;
            case "clock-show-seconds":
                show_seconds = settings.get_boolean(key);
                break;
            case "clock-show-date":
                show_date = settings.get_boolean(key);
                break;
        }
        /* Lazy update on next clock sync */
    }

    /**
     * This is called once every second, updating the time
     */
    protected bool update_clock()
    {
        time = new DateTime.now_local();
        int current_day = time.get_day_of_month();
        int current_month = time.get_month();
        int current_year = time.get_year();
        string format;

        // update calendar if day change
        if(day != current_day) {
            cal.unmark_day(day);
            cal.select_month(current_month-1, current_year);
            cal.mark_day(current_day);
            day = current_day;
        }

        if (ampm) {
            format = "%l:%M";
        } else {
            format = "%H:%M";
        }
        if (show_seconds) {
            format += ":%S";
        }
        if (ampm) {
            format += " %p";
        }
        string ftime = " <big>%s</big> ".printf(format);
        if (show_date) {
            ftime += " <big>%x</big>";
        }

        var ctime = time.format(ftime);
        clock.set_markup(ctime);

        return true;
    }

} // End class

[ModuleInit]
public void peas_register_types(TypeModule module) 
{
    // boilerplate - all modules need this
    var objmodule = module as Peas.ObjectModule;
    objmodule.register_extension_type(typeof(Budgie.Plugin), typeof(ClockApplet));
}
