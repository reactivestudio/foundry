#!/usr/bin/env bash
# preview-icons.sh — варианты иконок для Filter и Revive.
# Run: bash scripts/preview-icons.sh

set -u

paint() { printf '\033[38;5;%sm%s\033[0m' "$1" "$2"; }

CHROME=117    # sky blue — action chrome
BACKLOG=105   # soft indigo — revive target

echo
echo "═══════════════════════════════════════════════════════════════════"
echo "         FILTER — варианты по разным семантикам                    "
echo "═══════════════════════════════════════════════════════════════════"

show() {
  local key="$1" glyph="$2" name="$3"
  printf '  %s)  %s  %s\n' \
    "$key" \
    "$(paint "$CHROME" "$glyph  Filter")" \
    "$(paint 244 "— $name")"
}

echo
echo "  ── семантика 'оптика / смотреть' (вместо лупы) ──"
echo
show A1 '🔭' 'telescope (emoji, 2 cells, цветной)'
show A2 '👓' 'glasses (emoji, 2 cells, цветной)'
show A3 '👁' 'eye (emoji, 2 cells, цветной)'
show A4 '◉' 'fisheye U+25C9 (1 cell — точка в кружке, как зрачок)'
show A5 '◎' 'bullseye U+25CE (1 cell — два концентрических круга)'
show A6 '⌖' 'position indicator U+2316 (1 cell — прицел/перекрестье)'
show A7 '𓁹' 'Eye of Horus U+13079 (Egyptian hieroglyph — если шрифт его знает)'

echo
echo "  ── семантика 'воронка/фильтр' (классическая UI-иконка filter) ──"
echo
show B1 '▽' 'white down-triangle U+25BD (1 cell — пустая воронка)'
show B2 '▼' 'black down-triangle U+25BC (1 cell — закрашенная воронка)'
show B3 '⛛' 'heavy down-triangle U+26DB (1 cell — толстая)'
show B4 '⏷' 'downwards triangle-headed arrow U+23F7 (1 cell)'
show B5 '⩒' 'logical or with dot inside U+2A52 (нестандарт)'
show B6 '⨊' 'summation with integral U+2A0A (нестандарт)'

echo
echo "  ── семантика 'список с фильтром / меню' ──"
echo
show C1 '≡' 'identical to U+2261 (1 cell — три линии, hamburger/filter)'
show C2 '☰' 'trigram heaven U+2630 (1 cell — толстые три линии)'
show C3 '≣' 'strictly equivalent U+2263 (1 cell — четыре линии)'
show C4 '⫶' 'tricolon U+2AF6 (1 cell — три точки вертикально)'

echo
echo "═══════════════════════════════════════════════════════════════════"
echo "         REVIVE — совсем другие семантики                          "
echo "═══════════════════════════════════════════════════════════════════"

show_rev() {
  local key="$1" glyph="$2" name="$3"
  printf '  %s)  %s  %s\n' \
    "$key" \
    "$(paint "$BACKLOG" "$glyph  Revive (back to backlog)")" \
    "$(paint 244 "— $name")"
}

echo
echo "  ── семантика 'двойные угловые скобки = rewind' ──"
echo
show_rev D1 '«' 'left double angle quotation U+00AB (1 cell — лаконично)'
show_rev D2 '⟪' 'mathematical left double angle U+27EA (1 cell — острее)'
show_rev D3 '‹' 'single left angle quotation U+2039 (1 cell — мягче)'
show_rev D4 '⫷' 'triple nested less-than U+2AF7 (1 cell — тройной)'

echo
echo "  ── семантика 'медицина / реанимация' ──"
echo
show_rev E1 '✚' 'heavy greek cross U+271A (1 cell — медицинский крест)'
show_rev E2 '⚕' 'staff of aesculapius U+2695 (1 cell — медицинский символ)'
show_rev E3 '⊕' 'circled plus U+2295 (1 cell — добавить/оживить)'
show_rev E4 '✛' 'open centre cross U+271B (1 cell — крест с пустым центром)'

echo
echo "  ── семантика 'recycling / возродить' ──"
echo
show_rev F1 '♻' 'recycling symbol U+267B (1 cell — переработка)'
show_rev F2 '⟳' 'clockwise gapped circle U+27F3 (но ⟳ = Reload — конфликт)'
show_rev F3 '⥀' 'counterclockwise top arrow U+2940 (1 cell)'
show_rev F4 '⥁' 'clockwise top arrow U+2941 (1 cell)'

echo
echo "  ── семантика 'вернуть из мёртвых = вверх/из ящика' ──"
echo
show_rev G1 '⤊' 'upwards quadruple arrow U+290A (1 cell)'
show_rev G2 '⇑' 'upwards double arrow U+21D1 (1 cell)'
show_rev G3 '↟' 'upwards arrow with double stroke U+219F (1 cell)'
show_rev G4 '⬆' 'upwards black arrow U+2B06 (1-2 cell в зависимости от шрифта)'

echo
echo "  ── семантика 'звезда / искра жизни' ──"
echo
show_rev H1 '✦' 'black four-pointed star U+2726 (1 cell)'
show_rev H2 '✺' 'twelve-pointed black star U+273A (1 cell — солнце/искра)'
show_rev H3 '❋' 'heavy eight-pointed pinwheel star U+274B (1 cell)'
show_rev H4 '⚝' 'outlined white star U+269D (1 cell)'

echo
echo "═══════════════════════════════════════════════════════════════════"
echo "         ПОЛНОЕ DRILL-MENU (выбери комбинацию)                     "
echo "═══════════════════════════════════════════════════════════════════"

preview_menu() {
  local title="$1" revive_glyph="$2"
  echo
  echo "  ── $title ──"
  printf '    %s\n' "$(paint 215 '▶  Start (move to in-progress)')"
  printf '    %s\n' "$(paint 121 '✓  Finish (move to done)')"
  printf '    %s\n' "$(paint 105 '⏸  Pause back to backlog')"
  printf '    %s\n' "$(paint 105 "$revive_glyph  Revive (back to backlog)")"
  printf '    %s\n' "$(paint 218 '×  Decline')"
  printf '    %s\n' "$(paint "$CHROME" '←  Back')"
}

preview_menu "D1 (« двойная скобка)"   '«'
preview_menu "E1 (✚ медицинский крест)" '✚'
preview_menu "E3 (⊕ circled plus)"     '⊕'
preview_menu "F1 (♻ recycling)"        '♻'
preview_menu "H1 (✦ четырёхлучевая)"   '✦'

echo
echo "═══════════════════════════════════════════════════════════════════"
echo "         ACTION BAR (выбери комбинацию)                            "
echo "═══════════════════════════════════════════════════════════════════"

preview_bar() {
  local title="$1" filter_glyph="$2"
  echo
  echo "  ── $title ──"
  printf '    %s    %s    %s    %s\n' \
    "$(paint "$CHROME" "$filter_glyph Filter")" \
    "$(paint "$CHROME" "+ Add new")" \
    "$(paint "$CHROME" "⟳ Reload")" \
    "$(paint "$CHROME" "⏻ Exit")"
}

preview_bar "A4 (◉ fisheye)"       '◉'
preview_bar "A5 (◎ bullseye)"      '◎'
preview_bar "A6 (⌖ прицел)"        '⌖'
preview_bar "B1 (▽ воронка пустая)" '▽'
preview_bar "B2 (▼ воронка чёрная)" '▼'
preview_bar "C1 (≡ три линии)"      '≡'

echo
echo "Скажи: Filter=X, Revive=Y"
echo
