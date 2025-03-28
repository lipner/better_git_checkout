_GIT_COMPLETION_LAST_BRANCHES_COUNT=${_GIT_COMPLETION_LAST_BRANCHES_COUNT:-10}

# Inspired by 'git lb' alias from https://ses4j.github.io/2020/04/01/git-alias-recent-branches/
_last_branches() {
    local cur_branch
    cur_branch=$(git rev-parse --abbrev-ref HEAD)  # get the current branch
     # show reflog for HEAD:
     #  pull: Fast-forward ~ HEAD@{2 days ago}
     #  checkout: moving from staging to master ~ HEAD@{2 days ago}
     #  cherry-pick: some commit message ~ HEAD@{2 days ago}
     #  reset: moving to origin/staging ~ HEAD@{2 days ago}
     #  merge master: Merge made by the 'ort' strategy. ~ HEAD@{2 days ago}
     __git reflog show --pretty=format:'%gs ~ %gd' --date=relative |
     # select only checkout lines, then transform 'checkout: moving from staging to master' to 'master' (last word before ~),
     # while keeping the date part
     # note: this is safe as git branch names cannot contain spaces
     grep 'checkout:' | grep -oE '[^ ]+ ~ .*' |
     # remove duplicate branches. -F~ = field separator is ~, !seen[$1]++ = print only first occurrence of $1 (where seen[$1] is 0)
     awk -F~ '!seen[$1]++' |
     # select only (N+1) last branches (+1 because we usually delete the curernt branch)
     head -n "$((${_GIT_COMPLETION_LAST_BRANCHES_COUNT}+1))"|
     # transform 'master ~ HEAD@{2 days ago}' to '2 days ago:  master'
     awk -F' ~ HEAD@{' -v cur="$cur_branch" '{ if ($1 != cur) print (substr($2, 1, length($2)-1) ":  " $1) }' |
     # After potential removal of current branch, select only top N
     head -n "${_GIT_COMPLETION_LAST_BRANCHES_COUNT}"
}

__git_complete_refs__hook() {
	local cur_="$cur"
  local complete_last_branches=1

  # __git_complete_refs receives variouns arguments with '--' syntax.
  # We want to offer last branches completion only if the user didn't specify any non-default arguments.
  # --mode=refs is the default mode, so it's that same as being omitted.
  # --dwim is the default mode for __git_complete_refs, so it's the same as being omitted.
  # Any other argument will disable the last branches completion.
  local -a args
  args=("$@")
  for arg in "${args[@]}"; do
    case "$arg" in
      --mode=refs|--dwim)
        ;;
      *)
        complete_last_branches=0
        break
        ;;
    esac
  done

  # We only offer last branch completion if the user hasn't entered a prefix before pressing <TAB>
  if [[ -n "$cur_" ]]; then
    complete_last_branches=0
  fi

  #call the original function if complete_last_branches is 0
  if [[ $complete_last_branches -eq 0 ]]; then
    __git_complete_refs__orig "$@"
    return
  fi

  # get the last branches and read the output to an array
  local lb_output
  lb_output=$(_last_branches)
  local -a branch_names display_lines
  for line in ${(f)lb_output}; do
      # line format: '2 days ago:  master' (note double space after colon)
      local branch="${line#*:  }"
      branch_names+=("$branch")
      display_lines+=("$line")
  done

  # Offer the completions in two groups: recent and regular.
  # Need to do this here, as calling the original function overwrites the completion list.
  # Using `builtin compadd` because some completion plugins hijack `compadd` (fsf-tab, I'm looking at you)
  emulate -L zsh
  builtin compadd -V "recent" -X '%B%URecently checked-out branches...%b%u' -Q -l -d display_lines -E 1 -- "${branch_names[@]}"
  builtin compadd -V "regular" -X '%B%URegular completions...%b%u' -Q -S '' -- $(__git_heads)
  _ret=0
}

_hook_completions(){
  # load the git completion
  autoload -Uz _git
  # call the function for it to actually load (otherwise it's a stub)
  _git 2>/dev/null

  # Make sure the git completion is loaded properly
  # __git_complete_refs is an internat function called by _git, so it should be available after loading _git
  if [[ -z "${functions[__git_complete_refs]}" ]]; then
    return 1
  fi

  # save the original __git_complete_refs function but only if not saved before
  if [[ -z "${functions[__git_complete_refs__orig]}" ]]; then
    functions[__git_complete_refs__orig]="${functions[__git_complete_refs]}"
  fi

  # sanity check: make sure the orig function was not assigned the hook function
  if [[ "${functions[__git_complete_refs__orig]}" == "${functions[__git_complete_refs__hook]}" ]]; then
    return 1
  fi

  # assign the hook function to the original function
  functions[__git_complete_refs]="${functions[__git_complete_refs__hook]}"
}

_hook_completions