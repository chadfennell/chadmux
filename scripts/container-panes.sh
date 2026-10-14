#!/usr/bin/env bash
# Tag every tmux pane with the container it's attached to.
#
# For each pane, walk the process tree under #{pane_pid} looking for
#   incus shell|exec|console <instance>   -> pane option @incus
#   sbx run|exec ...                      -> pane option @sbx (Docker Sandboxes)
# and store the name in that option (unset when there is none). tmux.conf
# reads #{@incus} and #{@sbx}.
#
# Prints nothing, so it can run as a #() job from the status line.

ps -e -o pid=,ppid=,args= | awk -v panes="$(tmux list-panes -a -F $'#{pane_id}\t#{pane_pid}\t#{@incus}\t#{@sbx}')" '
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

  # Sandbox name from an sbx command line, or "" if it is not attached to one.
  #   sbx exec [flags] <name> <command...>
  #   sbx run [flags] [<agent> [<workspace> [<extra mounts...>]]]
  # run without --name gets sbx'"'"'s default name, <agent>-<workspace dir name>,
  # with the workspace resolved against the process'"'"'s cwd.
  function sandbox(pid, args,    n, a, i, cmd, pos, agent, path, dir, sh) {
    n = split(args, a, /[ \t]+/)
    for (i = 1; i <= n; i++) {
      if (a[i] ~ /(^|\/)sbx$/) break
    }
    for (i++; i <= n; i++) {
      if (cmd == "") {
        if (a[i] ~ /^-/) continue
        if (a[i] != "run" && a[i] != "exec") return ""
        cmd = a[i]
        continue
      }
      if (a[i] == "--") break
      if (a[i] ~ /^--name=/) return substr(a[i], 8)
      if (a[i] == "--name") return a[i + 1]
      # Flags that take a separate value
      if (cmd == "exec" && a[i] ~ /^(-u|--user|-e|--env|--env-file|-w|--workdir)$/) { i++; continue }
      if (cmd == "run" && a[i] ~ /^(-t|--template|--policy|--network|--mount|-e|--env|--cpus|--memory)$/) { i++; continue }
      if (a[i] ~ /^-/) continue
      if (cmd == "exec") return a[i]
      if (++pos == 1) agent = a[i]
      else if (pos == 2) { path = a[i]; break }
    }
    if (cmd != "run" || agent == "") return ""

    sub(/:(ro|rw)$/, "", path)
    if (path == "") path = "."
    if (path ~ /^~(\/|$)/) path = ENVIRON["HOME"] substr(path, 2)
    gsub(/'"'"'/, "'"'"'\\'"'"''"'"'", path)
    sh = "cd /proc/" pid "/cwd 2>/dev/null && cd -- '"'"'" path "'"'"' 2>/dev/null && pwd -P"
    dir = ""
    sh | getline dir
    close(sh)
    sub(/.*\//, "", dir)
    return dir == "" ? "" : agent "-" dir
  }

  { args = $0; sub(/^[ \t]*[0-9]+[ \t]+[0-9]+[ \t]+/, "", args)
    cmd[$1] = args; kids[$2] = kids[$2] " " $1 }

  # Depth-first search from a pane shell for the first container, as
  # "incus <name>" or "sbx <name>".
  function find(pid,    name, k, n, i) {
    name = (cmd[pid] ~ /(^|\/|[ \t])incus[ \t]/) ? instance(cmd[pid]) : ""
    if (name != "") return "incus " name
    name = (cmd[pid] ~ /(^|\/|[ \t])sbx[ \t]/) ? sandbox(pid, cmd[pid]) : ""
    if (name != "") return "sbx " name
    n = split(kids[pid], k, " ")
    for (i = 1; i <= n; i++) if ((name = find(k[i])) != "") return name
    return ""
  }

  # Emit the tmux command that sets pane option @opt to want, if it changed.
  function sync(pane, opt, have, want) {
    if (want == have) return
    changed = 1
    if (want != "") print "set-option -p -t " pane " @" opt " " want
    else            print "set-option -pu -t " pane " @" opt
  }

  END {
    n = split(panes, lines, "\n")
    for (i = 1; i <= n; i++) {
      split(lines[i], p, "\t")  # pane_id pane_pid current-@incus current-@sbx
      split(find(p[2]), found, " ")
      sync(p[1], "incus", p[3], found[1] == "incus" ? found[2] : "")
      sync(p[1], "sbx",   p[4], found[1] == "sbx"   ? found[2] : "")
      delete found
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
