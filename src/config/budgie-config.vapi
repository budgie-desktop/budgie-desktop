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
    [CCode (cheader_filename = "budgie-config.h")]
    public extern const string MODULE_DIRECTORY;

    [CCode (cheader_filename = "budgie-config.h")]
    public extern const string MODULE_DATA_DIRECTORY;

    [CCode (cheader_filename = "budgie-config.h")]
    public extern const string DATADIR;

    [CCode (cheader_filename = "budgie-config.h")]
    public extern const string CONFDIR;

    [CCode (cheader_filename = "budgie-config.h")]
    public extern const string VERSION;

    [CCode (cheader_filename = "budgie-config.h")]
    public extern const string WEBSITE;

    [CCode (cheader_filename = "budgie-config.h")]
    public extern const string GETTEXT_PACKAGE;

    [CCode (cheader_filename = "budgie-config.h")]
    public extern const string LOCALEDIR;
}
