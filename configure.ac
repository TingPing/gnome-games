AC_INIT([gnome-games], [3.18.0])
AM_INIT_AUTOMAKE([foreign subdir-objects])

# i18 support
IT_PROG_INTLTOOL(0.40.0)
GETTEXT_PACKAGE=AC_PACKAGE_NAME
AC_SUBST(GETTEXT_PACKAGE)
AC_DEFINE_UNQUOTED(GETTEXT_PACKAGE,"$GETTEXT_PACKAGE",[The name of the gettext domain])

AC_PROG_CC
AM_PROG_VALAC

# GResource
AC_PATH_PROG(GLIB_COMPILE_RESOURCES, glib-compile-resources)

# GSettings support
GLIB_GSETTINGS

GLIB_MIN_VERSION=2.38.0
AC_SUBST(GLIB_MIN_VERSION)

PKG_CHECK_MODULES(GNOME_GAMES, [
	gio-2.0
	gio-unix-2.0
	glib-2.0 >= $GLIB_MIN_VERSION
	gtk+-3.0
	libarchive
	retro-gobject-0.4
	retro-gtk-0.4
	tracker-sparql-1.0
])

AC_CONFIG_FILES([
	Makefile
	data/Makefile
	data/icons/Makefile
	po/Makefile.in
	src/Makefile
])

AC_OUTPUT
