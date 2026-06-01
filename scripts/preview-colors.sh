#!/usr/bin/env bash
# preview-colors.sh — explore color shades for foundry's UI.
# Run: bash scripts/preview-colors.sh

set -u

paint()    { printf '\033[38;5;%sm%s\033[0m' "$1" "$2"; }
swatch()   { printf '%s %s\n' "$(paint "$1" "████████")" "$(paint "$1" "$2")"; }
status()   { printf '%s\n' "$(paint "$1" "$2")"; }

echo
echo "═══════════════════════════════════════════════════════════════════"
echo "                  SHADE EXPLORER — выбирай по ролям                "
echo "═══════════════════════════════════════════════════════════════════"

echo
echo "── ИКОНКА (один цвет для всех 4 кружков, голубой) ──"
echo
for code in 195 159 153 123 117 81; do
  case "$code" in
    195) name='pale ice    #d7ffff (самый светлый)' ;;
    159) name='ice cyan    #afffff' ;;
    153) name='baby blue   #afd7ff' ;;
    123) name='aqua light  #87ffff' ;;
    117) name='sky blue    #87d7ff' ;;
    81)  name='cool cyan   #5fd7ff (самый насыщенный)' ;;
  esac
  printf '  [%3s]  %s %s %s %s %s   %s\n' \
    "$code" \
    "$(paint "$code" "████")" \
    "$(paint "$code" "○")" \
    "$(paint "$code" "⊙")" \
    "$(paint "$code" "●")" \
    "$(paint "$code" "⊗")" \
    "$name"
done

echo
echo "── BACKLOG (cool/calm — purple/lilac/blue) ──"
echo
for c in 147 183 141 189 110 105; do
  case "$c" in
    147) n='periwinkle    #afafff' ;;
    183) n='light lilac   #d7afff' ;;
    141) n='electric lav  #af87ff' ;;
    189) n='lavender mist #d7d7ff (very light)' ;;
    110) n='frost blue    #87afd7' ;;
    105) n='soft indigo   #8787ff' ;;
  esac
  printf '  [%3s]  %s     %s\n' "$c" "$(paint "$c" "○  backlog")" "$n"
done

echo
echo "── IN-PROGRESS (warm/active — yellow/orange/amber) ──"
echo
for c in 215 222 220 179 221 223 209 214; do
  case "$c" in
    215) n='warm orange   #ffaf5f' ;;
    222) n='peach         #ffd787' ;;
    220) n='golden        #ffd700' ;;
    179) n='muted amber   #d7af5f' ;;
    221) n='soft yellow   #ffd75f' ;;
    223) n='light peach   #ffd7af' ;;
    209) n='salmon-orange #ff875f' ;;
    214) n='vivid orange  #ffaf00' ;;
  esac
  printf '  [%3s]  %s   %s\n' "$c" "$(paint "$c" "⊙  in-progress")" "$n"
done

echo
echo "── DONE (success — green/mint) ──"
echo
for c in 121 84 156 119 108 78 192 158; do
  case "$c" in
    121) n='soft mint     #87ffaf' ;;
    84)  n='bright mint   #5fff87' ;;
    156) n='light mint    #afff87' ;;
    119) n='vivid mint    #87ff5f' ;;
    108) n='sage          #87af87 (muted)' ;;
    78)  n='emerald       #5fd787' ;;
    192) n='pale lime     #d7ff87' ;;
    158) n='pale mint     #afffd7' ;;
  esac
  printf '  [%3s]  %s          %s\n' "$c" "$(paint "$c" "●  done")" "$n"
done

echo
echo "── DECLINED (stop — pink/red/rose) ──"
echo
for c in 211 204 217 174 203 218 175 168; do
  case "$c" in
    211) n='soft pink     #ff87af' ;;
    204) n='hot pink      #ff5f87' ;;
    217) n='coral         #ffafaf' ;;
    174) n='muted rose    #d78787' ;;
    203) n='salmon        #ff5f5f' ;;
    218) n='pale pink     #ffafd7' ;;
    175) n='dusty rose    #d787af' ;;
    168) n='deep rose     #d75f87' ;;
  esac
  printf '  [%3s]  %s      %s\n' "$c" "$(paint "$c" "⊗  declined")" "$n"
done

echo
echo "═══════════════════════════════════════════════════════════════════"
echo "                  CURATED PALETTES                                  "
echo "═══════════════════════════════════════════════════════════════════"

show_palette() {
  local title="$1" b="$2" ip="$3" d="$4" dc="$5" note="$6"
  echo
  echo "── $title ──"
  printf '  %s  %s  %s  %s\n' \
    "$(paint "$b"  '○ backlog       ')" \
    "$(paint "$ip" '⊙ in-progress   ')" \
    "$(paint "$d"  '● done          ')" \
    "$(paint "$dc" '⊗ declined      ')"
  printf '  %s\n' "$(paint 244 "$note")"
}

show_palette "A — Tokyo Night (vibrant)"      147 215 121 211 "periwinkle / warm orange / soft mint / soft pink"
show_palette "A2 — Tokyo Night (softer)"      183 222 156 217 "light lilac / peach / light mint / coral"
show_palette "A3 — Tokyo Night (saturated)"   141 214 84  204 "electric lav / vivid orange / bright mint / hot pink"

show_palette "B — Synthwave (high contrast)"  141 220 84  204 "electric lavender / golden / bright mint / hot pink"
show_palette "B2 — Synthwave (warmer)"        105 209 78  168 "soft indigo / salmon-orange / emerald / deep rose"

show_palette "C — Pastel candy (very soft)"   183 222 156 217 "light lilac / peach / mint / coral"
show_palette "C2 — Pastel candy (mintier)"    189 223 158 218 "lavender mist / light peach / pale mint / pale pink"

show_palette "D — Nordic (muted)"             110 179 108 174 "frost blue / muted amber / sage / muted rose"
show_palette "D2 — Nordic (lighter)"          117 222 156 217 "sky blue / peach / mint / coral"

show_palette "E — Cyber soft (cyan-based)"    117 222 84  211 "sky blue / peach / bright mint / soft pink"
show_palette "F — Spring (fresh)"             153 221 121 218 "baby blue / soft yellow / soft mint / pale pink"

echo
echo "═══════════════════════════════════════════════════════════════════"
echo "                  ПРЕВЬЮ ПОЛНОЙ СТРОКИ                              "
echo "═══════════════════════════════════════════════════════════════════"

preview_row() {
  local icon_c="$1" b="$2" ip="$3" d="$4" dc="$5"
  echo
  printf '  iconColor=%s · palette: backlog=%s, in-progress=%s, done=%s, declined=%s\n' \
    "$icon_c" "$b" "$ip" "$d" "$dc"
  echo
  printf '  %s  %s  %s  %s  %s\n' \
    "$(paint "$icon_c" '○')" "$(paint "$b"  'backlog       ')" "Rate limiting for /api/orders         " "$(paint 244 'Jun 1   ')" "$(paint 244 '3m ago')"
  printf '  %s  %s  %s  %s  %s\n' \
    "$(paint "$icon_c" '⊙')" "$(paint "$ip" 'in-progress   ')" "Fix flaky kafka consumer test         " "$(paint 244 'Jun 1   ')" "$(paint 244 '2m ago')"
  printf '  %s  %s  %s  %s  %s\n' \
    "$(paint "$icon_c" '●')" "$(paint "$d"  'done          ')" "Deprecate old API endpoint            " "$(paint 244 'Jun 1   ')" "$(paint 244 'yesterday')"
  printf '  %s  %s  %s  %s  %s\n' \
    "$(paint "$icon_c" '⊗')" "$(paint "$dc" 'declined      ')" "Remove dead config                    " "$(paint 244 'Jun 1   ')" "$(paint 244 '1h ago')"
}

preview_row 153 147 215 121 211   # icon=baby blue + palette A
preview_row 117 183 222 156 217   # icon=sky + palette C
preview_row 195 147 222 84  217   # icon=ice + custom mix

echo
echo "Скажи или:"
echo "  • номер палитры + iconColor (например: 'E, icon=153')"
echo "  • кастомный сет (например: 'icon=117, backlog=183, in-prog=222, done=121, declined=204')"
echo
