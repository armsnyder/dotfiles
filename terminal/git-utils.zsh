# Git, Graphite & tmux utilities

REPO_ROOTS=("$HOME/repos" "$HOME/.dotfiles")

_tmux_safe_name() {
  echo "${1//[.:]/-}"
}

_tmux_switch() {
  if [[ -n "$TMUX" ]]; then
    tmux switch-client -t "=$1"
  else
    tmux attach-session -t "=$1"
  fi
}

# Set up the standard IDE pane layout in the current tmux target.
_ide_layout() {
  local target="$1" dir="$2"
  tmux send-keys -t "$target" "nvim" Enter
  tmux split-window -h -l 40% -t "$target" -c "$dir"
  tmux send-keys -t "$target" "agent --approve-mcps" Enter
  tmux split-window -v -f -l 25% -t "$target" -c "$dir"
  tmux select-pane -t "${target}.0"
}

# Remove all clean worktrees for a given repo root.
_cleanup_worktrees() {
  local repo_dir="$1"
  git -C "$repo_dir" worktree list --porcelain | awk '
    /^worktree / { wt = substr($0, 10) }
    /^branch /   { print wt }
  ' | while read -r wt_path; do
    [[ "$wt_path" == "$repo_dir" ]] && continue
    if git -C "$wt_path" diff --quiet HEAD 2>/dev/null && \
       git -C "$wt_path" diff --quiet --cached HEAD 2>/dev/null && \
       [[ -z "$(git -C "$wt_path" ls-files --others --exclude-standard 2>/dev/null)" ]]; then
      git worktree remove "$wt_path" 2>/dev/null
    else
      echo "Skipping dirty worktree: $wt_path" >&2
    fi
  done
}

# List all repo paths under REPO_ROOTS.
_list_repos() {
  for root in "${REPO_ROOTS[@]}"; do
    find "$root" -maxdepth 3 -name .git -type d 2>/dev/null
  done | while read -r gitdir; do
    dirname "$gitdir"
  done | sort
}

# List recent branches across all repos under REPO_ROOTS.
_list_recent_branches() {
  local max_per_repo="${1:-10}"
  for root in "${REPO_ROOTS[@]}"; do
    find "$root" -maxdepth 3 -name .git -type d 2>/dev/null | while read -r gitdir; do
      local repo_dir=$(dirname "$gitdir")
      local repo_name=${repo_dir#$root/}
      git -C "$repo_dir" for-each-ref --sort=-committerdate \
        --format="%(committerdate:unix)|%(committerdate:relative)|%(refname:short)|$repo_name|$repo_dir" \
        refs/heads/ 2>/dev/null | head -n "$max_per_repo"
    done
  done | sort -t'|' -k1 -nr | cut -d'|' -f2-
}

# ide <path> — open a repo in a new tmux session with the IDE layout.
#              Switches to an existing session if one already exists.
ide() {
  local dir="${1:?Usage: ide <path>}"
  dir=$(cd "$dir" 2>/dev/null && pwd) || {
    echo "Error: $dir is not a valid directory" >&2
    return 1
  }
  local name
  name=$(_tmux_safe_name "$(basename "$dir")")

  if ! tmux has-session -t "=$name" 2>/dev/null; then
    tmux new-session -d -s "$name" -c "$dir"
    _ide_layout "=$name:0" "$dir"
  fi

  _tmux_switch "$name"
}

# wta <name> — create (or reuse) a worktree off main and open it in a new
#              tmux window with the IDE layout, targeted at the repo's session.
#              If a window for this worktree is already open, switch to it.
wta() {
  if [[ -z "$1" ]]; then
    echo "Usage: wta <name>" >&2
    return 1
  fi

  local name="$1"

  if [[ "$name" =~ [[:space:]] ]]; then
    echo "Error: name cannot contain spaces" >&2
    return 1
  fi

  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "Error: not in a git repository" >&2
    return 1
  }

  if ! git rev-parse --verify main &>/dev/null; then
    echo "Error: branch 'main' does not exist in this repo" >&2
    return 1
  fi

  local repo_name=$(basename "$repo_root")
  local safe_name
  safe_name=$(_tmux_safe_name "$name")
  local session
  session=$(_tmux_safe_name "$repo_name")

  if [[ -n "$TMUX" ]] && tmux list-windows -t "=$session" -F '#{window_name}' 2>/dev/null | grep -qx "$safe_name"; then
    tmux select-window -t "=$session:$safe_name"
    return
  fi

  local wt_dir="${repo_root}/../${repo_name}-${name}"

  local existing_wt
  existing_wt=$(git worktree list --porcelain | awk -v branch="refs/heads/$name" '
    /^worktree / { wt = substr($0, 10) }
    /^branch /   { if (substr($0, 8) == branch) print wt }
  ')

  if [[ -n "$existing_wt" ]]; then
    wt_dir="$existing_wt"
  elif [[ -d "$wt_dir" ]]; then
    echo "Error: $wt_dir already exists but is not a worktree for $name" >&2
    return 1
  elif git show-ref --verify --quiet "refs/heads/$name"; then
    git worktree add "$wt_dir" "$name" || return 1
  else
    git worktree add -b "$name" "$wt_dir" main || return 1
  fi

  if [[ -n "$TMUX" ]]; then
    tmux new-window -n "$safe_name" -t "=$session:" -c "$wt_dir"
    _ide_layout "=$session:$safe_name" "$wt_dir"
    _tmux_switch "$session"
    tmux select-window -t "=$session:$safe_name"
  else
    cd "$wt_dir"
  fi
}

# idec — close the current tmux session, cleaning up any worktrees first.
idec() {
  if [[ -z "$TMUX" ]]; then
    echo "Error: not in a tmux session" >&2
    return 1
  fi

  local current
  current=$(tmux display-message -p '#{session_name}')

  if (( $(tmux list-sessions | wc -l) <= 1 )); then
    echo "Error: this is the only tmux session" >&2
    return 1
  fi

  local session_dir
  session_dir=$(tmux display-message -t "=$current:0" -p '#{pane_current_path}')
  local repo_root
  repo_root=$(git -C "$session_dir" rev-parse --show-toplevel 2>/dev/null)

  if [[ -n "$repo_root" ]]; then
    _cleanup_worktrees "$repo_root"
  fi

  tmux switch-client -l 2>/dev/null || tmux switch-client -n
  tmux kill-session -t "=$current"
}

# wtr — remove the current worktree and close the tmux window.
#        If this is the last window in the session, kill the session instead.
wtr() {
  local wt_dir
  wt_dir=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "Error: not in a git repository" >&2
    return 1
  }

  local common_dir
  common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
  local git_dir
  git_dir=$(git rev-parse --git-dir 2>/dev/null)

  if [[ "$common_dir" == "$git_dir" ]]; then
    echo "Error: not in a worktree (this is the main checkout)" >&2
    return 1
  fi

  if [[ -n "$TMUX" ]]; then
    local current_window
    current_window=$(tmux display-message -p '#{window_id}')
    local window_count
    window_count=$(tmux list-windows | wc -l | tr -d ' ')

    if ! git worktree remove "$wt_dir"; then
      echo "Hint: commit or stash changes first, or use 'git worktree remove --force'" >&2
      return 1
    fi

    if (( window_count <= 1 )); then
      local current_session
      current_session=$(tmux display-message -p '#{session_name}')
      tmux kill-session -t "=$current_session"
    else
      tmux select-window -l
      tmux kill-window -t "$current_window"
    fi
  else
    local main_root
    main_root=$(git -C "$common_dir/.." rev-parse --show-toplevel 2>/dev/null)
    git worktree remove "$wt_dir" || return 1
    cd "$main_root"
  fi
}
