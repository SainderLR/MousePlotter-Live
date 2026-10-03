# Start the MousePlotter menu on tty1 after the automatic login. The menu's
# own shell option sets MP_MENU, so it gets a normal shell.
if [ "$(tty)" = /dev/tty1 ] && [ -z "${MP_MENU:-}" ]; then
	export MP_MENU=1
	exec /usr/local/bin/mouseplotter-menu
fi
