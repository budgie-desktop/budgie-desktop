/*
 * budgie-session-dialog-main.c
 * 
 * Copyright 2014 Ikey Doherty <ikey.doherty@gmail.com>
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

#include "budgie-session-dialog.h"

#include <stdlib.h>

gint main(gint argc, gchar **argv)
{
        BudgieSessionDialog *dialog;

        gtk_init(&argc, &argv);

        dialog = budgie_session_dialog_new();
        gtk_widget_show_all(GTK_WIDGET(dialog));
        g_signal_connect(dialog, "delete-event", gtk_main_quit, NULL);
        gtk_main();
        
        return EXIT_SUCCESS;
}
