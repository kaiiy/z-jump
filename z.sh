[ -d "${_Z_DATA:-$HOME/.z}" ] && {
    echo "ERROR: z.sh's datafile (${_Z_DATA:-$HOME/.z}) is a directory."
}

_z() {
    local datafile="${_Z_DATA:-$HOME/.z}"
    [ -h "$datafile" ] && datafile=$(readlink "$datafile")
    [ -z "$_Z_OWNER" -a -f "$datafile" -a ! -O "$datafile" ] && return

    _z_dirs() {
        [ -f "$datafile" ] || return
        while IFS= read -r line; do
            [ -d "${line%%|*}" ] && printf '%s\n' "$line"
        done < "$datafile"
    }

    if [ "$1" = "--add" ]; then
        shift
        [ "$*" = "$HOME" -o "$*" = "/" ] && return
        if [ ${#_Z_EXCLUDE_DIRS[@]} -gt 0 ]; then
            for exclude in "${_Z_EXCLUDE_DIRS[@]}"; do
                case "$*" in "$exclude"*) return;; esac
            done
        fi
        local tempfile="${datafile}.$RANDOM"
        local score=${_Z_MAX_SCORE:-9000}
        _z_dirs | awk -v path="$*" -v now="$(date +%s)" -v score="$score" -F"|" '
            BEGIN { rank[path]=1; time[path]=now }
            $2 >= 1 {
              if ($1==path) { rank[$1]=$2+1; time[$1]=now }
              else           { rank[$1]=$2;   time[$1]=$3 }
              total += $2
            }
            END {
              for(x in rank) {
                r = (total>score ? 0.99*rank[x] : rank[x])
                printf "%s|%d|%d\n", x, r, time[x]
              }
            }
        ' >| "$tempfile"
        if [ $? -eq 0 ]; then
            [ "$_Z_OWNER" ] && chown $_Z_OWNER:"$(id -ng $_Z_OWNER)" "$tempfile"
            mv -f "$tempfile" "$datafile"
        else
            rm -f "$tempfile"
        fi

    elif [ "$1" = "--complete" -a -s "$datafile" ]; then
        _z_dirs | awk -v q="$2" -F"|" '
            BEGIN {
              q = substr(q,3)
              imatch = (q==tolower(q))
              gsub(/ /, ".*", q)
            }
            {
              if(imatch ? tolower($1)~q : $1~q) print $1
            }
        '
    else
        # list/go
        local echo_flag fnd last list typ cd
        while [ "$1" ]; do
            case "$1" in
                --) shift; fnd="${fnd:+$fnd }$*"; break ;;
                -*) for opt in $(echo "${1#-}" | sed -e 's/./& /g'); do
                        case "$opt" in
                          c) fnd="^$PWD $fnd";;
                          e) echo_flag=1;;
                          h) echo "${_Z_CMD:-z} [-cehlrtx] args" >&2; return;;
                          l) list=1;;
                          r) typ=rank;;
                          t) typ=recent;;
                          x) sed -i -e "\:^${PWD}|.*:d" "$datafile";;
                        esac
                    done
                    ;;
                *) fnd="${fnd:+$fnd }$1";;
            esac
            last="$1"
            shift
        done

        [ -n "$fnd" -a "$fnd" != "^$PWD " ] || list=1

        case "$last" in
          /*) [ -z "$list" -a -d "$last" ] && builtin cd "$last" && return;;
        esac

        [ -f "$datafile" ] || return

        cd="$(
          _z_dirs | awk -v t="$(date +%s)" -v list="$list" -v typ="$typ" -v q="$fnd" -F"|" '
            function frecent(r,tm){
              dx = t - tm
              return int(10000*r*(3.75/((0.0001*dx+1)+0.25)))
            }
            BEGIN { gsub(" ",".*",q); hi=-1e9; ihi=hi }
            {
              if(typ=="rank") r=$2
              else if(typ=="recent") r=$3-t
              else r=frecent($2,$3)
              if($1~q){ m[$1]=r; if(r>hi){best=$1;hi=r} }
              else if(tolower($1)~tolower(q)){ im[$1]=r; if(r>ihi){ibest=$1;ihi=r} }
            }
            END {
              if(list){
                for(x in m) printf "%10s %s\n", m[x], x | "sort -n"
              } else {
                print best?best:ibest
              }
            }
          '
        )"

        if [ $? -eq 0 ] && [ -n "$cd" ]; then
          [ "$echo_flag" ] && echo "$cd" || builtin cd "$cd"
        fi
    fi
}

z-wrapper() {
  if [ $# -eq 0 ]; then
    if [[ $PWD == $HOME* ]]; then
      while [[ ! -d .git && $PWD != $HOME ]]; do
        builtin cd ..
      done
    else
      builtin cd "$HOME"
    fi
  else
    _z "$@"
  fi
}

alias ${_Z_CMD:-z}='z-wrapper'

[ "$_Z_NO_RESOLVE_SYMLINKS" ] || _Z_RESOLVE_SYMLINKS="-P"

if type compctl >/dev/null 2>&1; then
  [ "$_Z_NO_PROMPT_COMMAND" ] || {
    precmd_functions+=(_z_precmd)
  }
  compctl -U -K _z_zsh_tab_completion _z
elif type complete >/dev/null 2>&1; then
  complete -o filenames -C '_z --complete "$COMP_LINE"' ${_Z_CMD:-z}
  [ "$_Z_NO_PROMPT_COMMAND" ] || {
    grep -q "_z --add" <<<"$PROMPT_COMMAND" \
      || PROMPT_COMMAND="$PROMPT_COMMAND"$'\n''(_z --add "$(pwd '$_Z_RESOLVE_SYMLINKS')" &)'
  }
fi
