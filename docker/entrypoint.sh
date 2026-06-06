#!/usr/bin/env bash
set -euo pipefail

REPO=/work
cd "$REPO"

log() { printf '\033[36m[sicp-build]\033[0m %s\n' "$*"; }

require_repo() {
  if [[ ! -f sicp-pocket.texi || ! -f Makefile ]]; then
    log "ERROR: в /work не вижу репо sicp (нет sicp-pocket.texi / Makefile)."
    log "Смонтируй корень репозитория в /work (см. compose.yaml)."
    exit 1
  fi
}

# Идемпотентные фиксы bit-rot. Меняют смонтированный репо — всё видно через
# git diff, при повторном запуске grep уже не сматчит и фикс не применится.
apply_fixes() {
  # 1) MathJax: мёртвый cdn.mathjax.org -> локально вендоренный 2.7.x.
  if grep -q 'cdn\.mathjax\.org' mathcell.xhtml 2>/dev/null; then
    log "патчу mathcell.xhtml: cdn.mathjax.org -> file:///opt/mathjax/MathJax.js"
    sed -i 's#http://cdn\.mathjax\.org/mathjax/latest/MathJax\.js#file:///opt/mathjax/MathJax.js#' \
        mathcell.xhtml
  fi
  # 2) Обложка: Makefile зовёт inkscape со старым CLI 0.92 (-e/-f/-C),
  #    которого нет в inkscape 1.x. Подменяем на rsvg-convert.
  if grep -q '@inkscape' Makefile 2>/dev/null; then
    log "патчу Makefile: inkscape -> rsvg-convert (рендер обложки cover.png)"
    perl -0pi -e \
      's{\@inkscape[^\n]*}{\@rsvg-convert -b "#fbfbfb" -o \$(THUMB) \$(DIR)fig/coverpage.std.svg}' \
      Makefile
  fi
}

case "${1:-epub}" in
  epub)
    require_repo
    apply_fixes
    mkdir -p dist
    # Лайт-путь: собираем epub из уже готового html/ (ruby+nokogiri+rsvg+zip),
    # без texinfo/phantomjs. Делаем все исходники "старее" html, чтобы make не
    # полез регенерить .texi -> html.
    find . -maxdepth 1 -type f -exec touch -d '@0' {} + 2>/dev/null || true
    touch html/*.xhtml
    log "собираю epub из готового html/ ..."
    make GOAL="$REPO/dist/sicp.epub" epub
    log "готово -> dist/sicp.epub"
    ;;

  full)
    require_repo
    apply_fixes
    mkdir -p dist
    # Fail-fast: phantomjs дёргается в get-math/put-math/batch-prettify, но в
    # Makefile они в ';'-склейке — краш проглатывается и сборка молча даёт
    # книгу без формул и подсветки. Поэтому проверяем его до тяжёлого билда.
    if ! phantomjs --version >/dev/null 2>&1; then
      log "ERROR: phantomjs не запускается:"
      phantomjs --version 2>&1 | sed 's/^/    /' || true
      log "full-сборка без него даст книгу без MathML и подсветки кода — прерываюсь."
      exit 1
    fi
    log "phantomjs $(phantomjs --version) OK"
    # Полная регенерация из sicp-pocket.texi: texi2any -> get/put-math (MathJax)
    # -> batch-prettify -> create_metafiles -> zip. Форсим регенерацию, делая
    # .texi новее html.
    touch sicp-pocket.texi
    log "полная сборка из .texi (texinfo 5.1 + phantomjs + mathjax) ..."
    make GOAL="$REPO/dist/sicp.epub" all
    log "готово -> dist/sicp.epub + регенеренный html/"
    ;;

  shell)
    require_repo
    exec bash
    ;;

  *)
    exec "$@"
    ;;
esac
