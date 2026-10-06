#!/usr/bin/env bash
# vim-tmux-navigator check (@vim_navigator_check): exit 0 when C-h/j/k/l
# should go to the pane instead of switching tmux panes.
#
# Usage: is-vim.sh <pane_tty> [<incus instance>]
#
# Normally: Vim (or fzf) is in the foreground on the pane's tty, same as the
# plugin's default check. A pane attached to an incus container (@incus, set
# by incus-panes.sh) only runs `incus` on the host, so instead look for
# Neovim running anywhere in that container. incus puts container processes
# in the cgroup lxc.payload.<name> (lxc.payload.<project>_<name> outside the
# default project), which host ps can see.

vim='(\S+/)?g?\.?(view|l?n?vim?x?|fzf)(diff)?(-wrapped)?'
tty=$1
instance=$2

if [ -z "$instance" ]; then
  ps -o state= -o comm= -t "$tty" | grep -iqE "^[^TXZ ]+ +${vim}\$"
else
  ps -e -o state= -o comm= -o cgroup= |
    grep -iqE "^[^TXZ ]+ +${vim} +\S*/lxc\.payload\.([^/]*_)?${instance}(/|\$)"
fi
