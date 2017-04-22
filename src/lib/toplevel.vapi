/*
 * This file is part of budgie-desktop
 * 
 * Copyright © 2015-2017 Ikey Doherty <ikey@solus-project.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 */

namespace Budgie {
    [CCode (cheader_filename = "BudgieToplevel.h")]
    public abstract class Toplevel : Gtk.Window {
        public int shadow_width {  set ; get; }
        public int intended_size { set ; get; }
        public int shadow_depth { set ;  get; }
        public bool shadow_visible { set ; get; }
        public bool theme_regions { set; get ; }
        public string uuid {  set ; get; }

        public Budgie.PanelPosition position { set; get; default = Budgie.PanelPosition.BOTTOM; }

        public abstract GLib.List<Budgie.AppletInfo?> get_applets();
        public signal void applet_added(Budgie.AppletInfo? info);
        public signal void applet_removed(string uuid);

        public signal void applets_changed();

        public abstract bool can_move_applet_left(Budgie.AppletInfo? info);
        public abstract bool can_move_applet_right(Budgie.AppletInfo? info);

        public abstract void move_applet_left(Budgie.AppletInfo? info);
        public abstract void move_applet_right(Budgie.AppletInfo? info);

        public virtual void reset_shadow();

        public abstract void add_new_applet(string id);
        public abstract void remove_applet(Budgie.AppletInfo? info);
    }

    [CCode (cheader_filename = "BudgieToplevel.h")]
    [Flags]
    public enum PanelPosition {
        NONE,
        BOTTOM,
        TOP,
        LEFT,
        RIGHT
    }

    [CCode (cheader_filename = "BudgieToplevel.h")]
    [Flags]
    public enum AppletPackType {
        START,
        END
    }

    [CCode (cheader_filename = "BudgieToplevel.h")]
    [Flags]
    public enum AppletAlignment {
        START,
        CENTER,
        END
    }
    [CCode (cheader_filename = "BudgieToplevel.h")]
    public static void set_struts(Gtk.Window? window, PanelPosition position, long panel_size);

    [CCode (cheader_filename = "BudgieToplevel.h")]
    public static string position_class_name(PanelPosition position);

    [CCode (cheader_filename = "BudgieToplevel.h")]
    public class ShadowBlock : Gtk.EventBox
    {
        public ShadowBlock(PanelPosition position);
        public PanelPosition position { set; get; }
        public int required_size { set; get; }
        public int removal { set; get; }
    }

    [CCode (cheader_filename = "BudgieToplevel.h")]
    public delegate double TweenFunc(double factor);

    [CCode (cheader_filename = "BudgieToplevel.h")]
    public delegate void AnimCompletionFunc(Animation? src);

    [CCode (cheader_filename = "BudgieToplevel.h")]
    public struct PropChange {
        string property;
        GLib.Value old;
        GLib.Value @new;
    }

    [CCode (cheader_filename = "BudgieToplevel.h")]
    [Compact]
    public class Animation : GLib.Object {
        public Animation();
        public int64 start_time;
        public int64 length;
        public unowned TweenFunc tween;
        public PropChange[] changes;
        public unowned Gtk.Widget widget;
        public GLib.Object? object;
        public uint id;
        public bool can_anim;
        public int64 elapsed;
        public bool no_reset;

        public void start(AnimCompletionFunc? compl);
        public void stop();
    }

    [CCode (cheader_filename = "BudgieToplevel.h")]
    public static double sine_ease_in_out(double p);

    [CCode (cheader_filename = "BudgieToplevel.h")]
    public static double sine_ease_in(double p);

    [CCode (cheader_filename = "BudgieToplevel.h")]
    public static double sine_ease_out(double p);

    [CCode (cheader_filename = "BudgieToplevel.h")]
    public static double elastic_ease_in(double p);

    [CCode (cheader_filename = "BudgieToplevel.h")]
    public static double elastic_ease_out(double p);

    [CCode (cheader_filename = "BudgieToplevel.h")]
    public static double back_ease_in(double p);

    [CCode (cheader_filename = "BudgieToplevel.h")]
    public static double back_ease_out(double p);

    [CCode (cheader_filename = "BudgieToplevel.h")]
    public static double expo_ease_in(double p);

    [CCode (cheader_filename = "BudgieToplevel.h")]
    public static double expo_ease_out(double p);

    [CCode (cheader_filename = "BudgieToplevel.h")]
    public static double quad_ease_in(double p);

    [CCode (cheader_filename = "BudgieToplevel.h")]
    public static double quad_ease_out(double p);

    [CCode (cheader_filename = "BudgieToplevel.h")]
    public static double quad_ease_in_out(double p);

    [CCode (cheader_filename = "BudgieToplevel.h")]
    public static double circ_ease_in(double p);

    [CCode (cheader_filename = "BudgieToplevel.h")]
    public static double circ_ease_out(double p);

    [CCode (cheader_filename = "BudgieToplevel.h")]
    public const int64 MSECOND;

    [CCode (cheader_filename = "BudgieToplevel.h")]
    public abstract class DesktopManager : GLib.Object
    {

        public signal void panels_changed();

        public virtual GLib.List<Budgie.Toplevel?> get_panels();
        public abstract uint slots_available();
        public abstract uint slots_used();
        public abstract void set_placement(string uuid, Budgie.PanelPosition position);
        public abstract void set_size(string uuid, int size);
        public abstract void create_new_panel();
        public abstract void delete_panel(string uuid);

        public abstract GLib.List<Peas.PluginInfo?> get_panel_plugins();
    }

}
