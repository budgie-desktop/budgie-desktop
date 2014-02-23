/*
 * icon-tasklist.c
 * 
 * Copyright 2013 Ikey Doherty <ikey.doherty@gmail.com>
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA 02110-1301, USA.
 * 
 * 
 */
#include <libwnck/libwnck.h>

#include "icon-tasklist.h"
#include "budgie-panel.h"

/* IconTasklist object */
struct _IconTasklist {
        GtkBox parent;
        WnckScreen *screen;
};

/* IconTasklist class definition */
struct _IconTasklistClass {
        GtkBoxClass parent_class;
};

G_DEFINE_TYPE(IconTasklist, icon_tasklist, GTK_TYPE_BOX)

/* Boilerplate GObject code */
static void icon_tasklist_class_init(IconTasklistClass *klass);
static void icon_tasklist_init(IconTasklist *self);
static void icon_tasklist_dispose(GObject *object);

/* Private functionality */
static gboolean button_draw(GtkWidget *widget,
                            cairo_t *cr,
                            gpointer userdata);
static gboolean button_clicked(GtkWidget *widget,
                               GdkEvent *event,
                               gpointer data);

static void window_opened(WnckScreen *screen,
                          WnckWindow *window,
                          gpointer userdata);
static void window_closed(WnckScreen *screen,
                          WnckWindow *window,
                          gpointer userdata);
static void active_changed(WnckScreen *screen,
                           WnckWindow *prev_window,
                           gpointer userdata);

static void update_window_icon(GtkImage *image,
                               WnckWindow *window);

static void window_update_icon(WnckWindow *window,
                               gpointer userdata);
static void window_update_title(WnckWindow *window,
                                gpointer userdata);

/* Initialisation */
static void icon_tasklist_class_init(IconTasklistClass *klass)
{
        GObjectClass *g_object_class;

        g_object_class = G_OBJECT_CLASS(klass);
        g_object_class->dispose = &icon_tasklist_dispose;
}

static void icon_tasklist_init(IconTasklist *self)
{
        wnck_set_client_type(WNCK_CLIENT_TYPE_PAGER);
        self->screen = wnck_screen_get_default();
        g_signal_connect(self->screen, "window-opened",
                G_CALLBACK(window_opened), self);
        g_signal_connect(self->screen, "window-closed",
                G_CALLBACK(window_closed), self);
        g_signal_connect(self->screen, "active-window-changed",
                G_CALLBACK(active_changed), self);

        wnck_screen_force_update(self->screen);
        /* Align to the center vertically */
        gtk_widget_set_valign(GTK_WIDGET(self), GTK_ALIGN_START);
}

static void icon_tasklist_dispose(GObject *object)
{
        /* Destruct */
        G_OBJECT_CLASS (icon_tasklist_parent_class)->dispose (object);
        wnck_shutdown();
}

/* Utility; return a new IconTasklist */
GtkWidget *icon_tasklist_new(void)
{
        IconTasklist *self;

        self = g_object_new(ICON_TASKLIST_TYPE, NULL, "orientation", GTK_ORIENTATION_HORIZONTAL);
        return GTK_WIDGET(self);
}

static gboolean button_draw(GtkWidget *widget,
                            cairo_t *cr,
                            gpointer userdata)
{
        GtkAllocation alloc;
        GtkStyleContext *style;

        style = gtk_widget_get_style_context(widget);
        gtk_style_context_remove_class(style, GTK_STYLE_CLASS_BUTTON);
        gtk_style_context_add_class(style, BUDGIE_STYLE_PANEL_ICON);
        gtk_widget_get_allocation(widget, &alloc);

        gtk_render_background(style, cr, 0, 0, alloc.width, alloc.height);
        gtk_render_frame(style, cr, 0, 0, alloc.width, alloc.height);

        /* Draw children of the button (i.e image) */
        gtk_container_propagate_draw(GTK_CONTAINER(widget),
                gtk_bin_get_child(GTK_BIN(widget)),
                cr);

        return TRUE;
}

static gboolean button_clicked(GtkWidget *widget,
                               GdkEvent *event,
                               gpointer data)
{
        WnckWindow *bwindow = NULL;
        GtkWidget *menu = NULL;
        guint32 timestamp = gtk_get_current_event_time();

        /* Only interested in presses */
        if(event->type != GDK_BUTTON_PRESS && event->type != GDK_TOUCH_END)
                return FALSE;

        bwindow = (WnckWindow*)g_object_get_data(G_OBJECT(widget),
                                                 "bwindow");
        /* Something happen! return here. */
        if(!bwindow)
                return TRUE;

        if (event->button.button == 3) {
                menu = (GtkWidget*)g_object_get_data(G_OBJECT(widget), "bmenu");
                gtk_menu_popup(GTK_MENU(menu), NULL, NULL, NULL,
                        NULL, event->button.button, timestamp);
                return TRUE;
        }
        if(wnck_window_is_minimized(bwindow)) {
                wnck_window_unminimize(bwindow, timestamp);
                wnck_window_activate(bwindow, timestamp);
        } else {
                if(wnck_window_is_active(bwindow))
                        wnck_window_minimize(bwindow);
                else
                        wnck_window_activate(bwindow, timestamp);
        }
        return TRUE;
}

static gboolean scroll_handler(GtkWidget *widget,
                          GdkEvent *event,
                          gpointer data)
{
    WnckScreen *screen = data;
    WnckWindow *active;
    GList *windows, *to_activate;
    GdkEventScroll scroll = event->scroll; 

    guint32 timestamp = gtk_get_current_event_time();

    windows = wnck_screen_get_windows(screen);
    active = wnck_screen_get_active_window(screen);
    to_activate = g_list_find(windows,active);

    if (scroll.direction)
        to_activate = g_list_previous(to_activate);
    else
        to_activate = g_list_next(to_activate);
    /* if there is no next or previous window don't do nothing*/
    if (to_activate)
        wnck_window_activate(WNCK_WINDOW(to_activate->data), timestamp);
    return TRUE;
}

static void window_opened(WnckScreen *screen,
                          WnckWindow *window,
                          gpointer userdata)
{
        GtkWidget *button = NULL;
        GtkWidget *image = NULL;
        GtkWidget *menu = NULL;
        const gchar *title;
        IconTasklist *self = ICON_TASKLIST(userdata);

        /* Don't add buttons for tasklist skipping apps */
        if (wnck_window_is_skip_tasklist(window))
                return;

        title = wnck_window_get_name(window);
        image = gtk_image_new();
        update_window_icon(GTK_IMAGE(image), window);

        /* Force sizes */
        gtk_image_set_pixel_size(GTK_IMAGE(image), -1);
        g_object_set(image, "icon-size", GTK_ICON_SIZE_BUTTON, NULL);

        button = gtk_toggle_button_new();
        gtk_button_set_relief(GTK_BUTTON(button), GTK_RELIEF_NONE);
        gtk_container_add(GTK_CONTAINER(button), image);

        /* Set title as tooltip */
        gtk_widget_set_tooltip_text(button, title);

        /* Press it if its active */
        if (wnck_window_is_active(window))
                gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(button), TRUE);

        /* Store a reference to this window for destroy ops, etc. */
        g_object_set_data(G_OBJECT(button), "bwindow", window);

        /* Add an action menu */
        menu = wnck_action_menu_new(window);
        g_object_set_data(G_OBJECT(button), "bmenu", menu);

        /* When the window changes, update the button
         * Icon change is separate so we dont keep reloading images and wasting resources */
        g_signal_connect(window, "name-changed", G_CALLBACK(window_update_title), button);
        g_signal_connect(window, "icon-changed", G_CALLBACK(window_update_icon), button);

        /* Override drawing of this button */
        g_signal_connect(button, "draw", G_CALLBACK(button_draw), self);

        /* Clicking the button */
        g_signal_connect(button, "button-press-event",
                         G_CALLBACK(button_clicked),
                         self);
        g_signal_connect(button, "touch-event",
                         G_CALLBACK(button_clicked),
                         self);
        gtk_widget_set_events (GTK_WIDGET(button),GDK_SCROLL_MASK);
        g_signal_connect(button, "scroll-event", 
                         G_CALLBACK(scroll_handler),
                         screen);

        gtk_box_pack_start(GTK_BOX(self), button, FALSE, FALSE, 0);
        gtk_widget_show_all(button);
}

static void window_closed(WnckScreen *screen,
                          WnckWindow *window,
                          gpointer userdata)
{
        IconTasklist *self = ICON_TASKLIST(userdata);
        GList *list, *elem;
        GtkWidget *toggle;
        GtkWidget *menu;
        WnckWindow *bwindow;

        /* If a buttons window matches the closing window, destroy the button */
        list = gtk_container_get_children(GTK_CONTAINER(self));
        for (elem = list; elem; elem = elem->next) {
                if (!GTK_IS_TOGGLE_BUTTON(elem->data))
                        continue;
                toggle = GTK_WIDGET(elem->data);
                bwindow = (WnckWindow*)g_object_get_data(G_OBJECT(toggle), "bwindow");
                if (bwindow == window) {
                        menu = (GtkWidget*)g_object_get_data(G_OBJECT(toggle), "bmenu");
                        gtk_widget_destroy(menu);
                        gtk_widget_destroy(toggle);
                }
        }
}

static void active_changed(WnckScreen *screen,
                           WnckWindow *prev_window,
                           gpointer userdata)
{
        IconTasklist *self = ICON_TASKLIST(userdata);
        GList *list, *elem;
        GtkWidget *toggle;
        WnckWindow *bwindow, *active;

        active = wnck_screen_get_active_window(screen);

        /* don't update our state for these guys (i.e. menu) */
        if (active && (wnck_window_is_skip_pager(active) ||
                wnck_window_is_skip_tasklist(active)))
                return;

        /* If a buttons window matches the closing window, destroy the button */
        list = gtk_container_get_children(GTK_CONTAINER(self));
        for (elem = list; elem; elem = elem->next) {
                if (!GTK_IS_TOGGLE_BUTTON(elem->data))
                        continue;
                toggle = GTK_WIDGET(elem->data);
                bwindow = (WnckWindow*)g_object_get_data(G_OBJECT(toggle), "bwindow");
                /* Deselect previous window */
                if (!active)
                        gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(toggle), FALSE);
                else
                        gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(toggle),
                                bwindow == active);
        }
}

static void update_window_icon(GtkImage *image,
                               WnckWindow *window)
{
        GdkPixbuf *pixbuf;
        const gchar *icon, *title;

        icon = wnck_window_get_icon_name(window);
        title = wnck_window_get_name(window);

        if (wnck_window_has_icon_name(window) && !g_str_equal(title, icon)) {
                gtk_image_set_from_icon_name(image, icon, GTK_ICON_SIZE_BUTTON);
        } else {
                pixbuf = wnck_window_get_icon(window);
                gtk_image_set_from_pixbuf(image, pixbuf);
        }
}

static void window_update_title(WnckWindow *window,
                                gpointer userdata)
{
        gtk_widget_set_tooltip_text(GTK_WIDGET(userdata), wnck_window_get_name(window));
}

static void window_update_icon(WnckWindow *window,
                               gpointer userdata)
{
        GtkImage *image;

        image = GTK_IMAGE(gtk_bin_get_child(GTK_BIN(userdata)));
        update_window_icon(image, window);
}
