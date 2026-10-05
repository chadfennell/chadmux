#!/usr/bin/env bash
# Tag every tmux pane with the incus instance it's attached to.
#
# For each pane, walk the process tree under #{pane_pid} looking for
# `incus shell|exec|console <instance>` and store the instance name in the
# pane option @incus (unset when there is none). tmux.conf reads #{@incus}.
#
# Prints nothing, so it can run as a #() job from the status line.

ps -e -o pid=,ppid=,args= | awk -v panes="$(tmux list-panes -a -F '#{pane_id} #{pane_pid} #{@incus}')" '
  # Instance name from an incus command line, or "" if it is not attached to one.
  function instance(args,    n, a, i, cmd) {
    n = split(args, a, /[ \t]+/)
    for (i = 1; i <= n; i++) {
      if (a[i] ~ /(^|\/)incus$/) break
    }
    for (i++; i <= n; i++) {
      if (cmd == "") {
        if (a[i] == "--project") { i++; continue }
        if (a[i] ~ /^-/) continue
        if (a[i] != "shell" && a[i] != "exec" && a[i] != "console") return ""
        cmd = a[i]
        continue
      }
      if (a[i] == "--") return ""
      # Flags that take a separate value
      if (a[i] ~ /^(--project|--cwd|--env|--user|--group|--mode|--type)$/) { i++; continue }
      if (a[i] ~ /^-/) continue
      return a[i]
    }
    return ""
  }

  { args = $0; sub(/^[ \t]*[0-9]+[ \t]+[0-9]+[ \t]+/, "", args)
    cmd[$1] = args; kids[$2] = kids[$2] " " $1 }

  # Depth-first search from a pane shell for the first incus instance.
  function find(pid,    name, k, n, i) {
    name = (cmd[pid] ~ /(^|\/|[ \t])incus[ \t]/) ? instance(cmd[pid]) : ""
    if (name != "") return name
    n = split(kids[pid], k, " ")
    for (i = 1; i <= n; i++) if ((name = find(k[i])) != "") return name
    return ""
  }

  END {
    n = split(panes, lines, "\n")
    for (i = 1; i <= n; i++) {
      split(lines[i], p, " ")  # pane_id pane_pid current-@incus
      name = find(p[2])
      if (name == p[3]) continue
      changed = 1
      if (name != "") print "set-option -p -t " p[1] " @incus " name
      else            print "set-option -pu -t " p[1] " @incus"
    }
    # Setting automatic-rename (to its current value) makes tmux recompute
    # window names now rather than on the pane'"'"'s next output.
    if (changed) print "set-option -gF automatic-rename #{automatic-rename}"
  }
' | {
  # One tmux invocation for all panes: join the commands with " ; ".
  args=()
  while read -r -a line; do
    ((${#args[@]})) && args+=(";")
    args+=("${line[@]}")
  done
  ((${#args[@]})) && tmux "${args[@]}" >/dev/null 2>&1
}
exit 0
