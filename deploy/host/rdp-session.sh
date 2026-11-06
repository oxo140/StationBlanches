#!/bin/sh
set -eu
# Une session Xfce et un bus privés ne doivent pas prendre la place du kiosque local.
export SB_RDP_SESSION=1
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=XFCE
export DESKTOP_SESSION=xfce
export XDG_CONFIG_HOME="$HOME/.config/station-blanche/rdp"
export XDG_CACHE_HOME="$HOME/.cache/station-blanche/rdp"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
unset DBUS_SESSION_BUS_ADDRESS SESSION_MANAGER
exec dbus-run-session -- xfce4-session
