# Сборка SICP в Docker

Инфра для сборки `sarabander/sicp` (HTML5 + EPUB3) в контейнере, без засирания
хоста протухшими зависимостями 2014 года.

## Раскладка

```
sicp/
├── compose.yaml          # точка входа
├── docker/
│   ├── Dockerfile        # сборочный образ
│   └── entrypoint.sh     # фиксы bit-rot + запуск make
├── Makefile              # родной Makefile книги (не трогаем)
├── sicp-pocket.texi      # исходник
└── dist/sicp.epub        # ← артефакт сюда
```

Положи `compose.yaml` и `docker/` в корень склонированного репо.

## Использование

```bash
docker compose run --rm epub     # epub из готового html/  (быстро, дефолт)
docker compose run --rm full     # полная регенерация из .texi
docker compose run --rm shell    # bash внутри сборочного окружения
docker compose up serve          # читать собранный html на http://localhost:8080
```

Два пути не просто так:

- **`epub`** собирает EPUB из уже закоммиченного `html/` — это ruby+nokogiri
  (метафайлы) + rsvg (обложка) + zip. Без texinfo и phantomjs, минимум точек
  отказа. Если тебе нужен просто `sicp.epub` — бери это.
- **`full`** регенерит `html/` из `sicp-pocket.texi` целиком: texi2any →
  get/put-math (MathJax через phantomjs) → batch-prettify → метафайлы → zip.
  Нужно, только если правишь сам `.texi`.

## Что протухло и как запинено

README книги врёт деталями. По факту в пайплайне четыре мины:

**Texinfo 5.1, не новее.** Бандленый в репе `lib/Texinfo/Convert/HTML.pm` —
пропатченная версия 5.0. `texi2any` перекрывает им только `HTML.pm`, а
`Parser.pm`/`Structuring.pm` тянет из системного `/usr/local/share/texinfo`.
Современный texinfo 6.x/7.x переписал этот внутренний API и ломает бандл.
Поэтому тянем исходник 5.1, делаем только `./configure` (без `make` — чтобы не
воевать с gnulib на свежей glibc; бинарь `makeinfo` на C не нужен, `texi2any` —
чистый perl) и кладём perl-дерево туда, где `texi2any` его сам ищет.

**PhantomJS 2.1.1.** Все три `*.js` — это phantomjs (`#!/usr/bin/env phantomjs`),
а не node. Заброшен с 2018, в апт-репах его нет — берём официальный пребилт-бинарь.

**MathJax 2.7.x, вендоренный.** `mathcell.xhtml` грузил MathJax с
`http://cdn.mathjax.org` — этот CDN умер в 2017. Плюс код на `MathJax.Hub` +
`toMathML` (API v2), которого нет в 3.x. Вендорим 2.7.9 в образ, а entrypoint
подменяет `src` на `file:///opt/mathjax/MathJax.js`.

**Обложка: inkscape → rsvg-convert.** Makefile рендерит `cover.png` через
`inkscape -e/-f/-C` (CLI 0.92), которого нет в inkscape 1.x. entrypoint
подменяет правило на `rsvg-convert` (librsvg, лёгкий, флаги совместимы).

Плюс **локаль `C.UTF-8`** в образе: без неё `create_metafiles.rb` падает с
`invalid byte sequence in US-ASCII` — в голом контейнере Ruby читает UTF-8
xhtml как ASCII.

Фиксы `mathcell.xhtml` и `Makefile` идемпотентны и применяются к
**смонтированному** репо в рантайме — видно через `git diff`, в образ репа не
вкомпиливается.

## Под Fedora

- `:z` на bind-маунтах в `compose.yaml` обязателен из-за SELinux, иначе
  контейнер не достучится до файлов.
- Под **rootless podman** (`podman compose ... ` / `podman-compose`) uid-маппинг
  разрулится сам: root в контейнере = твой юзер, `dist/sicp.epub` будет твой.
  Под обычным docker файл будет от root — поправь `chown` или гоняй
  `docker compose run --rm --user "$(id -u):$(id -g)" epub`.

## Что протестировано

Лайт-путь `epub` прогнан end-to-end (make + ruby/nokogiri + rsvg + zip):
получается валидный EPUB-контейнер — `mimetype` лежит первым и STORED (главный
инвариант OCF), `content.opf`/`toc.xhtml`/`cover.png` на месте, 167 файлов.
Оба патча (sed по `mathcell`, perl по `Makefile`) проверены на реальных файлах
репо, идемпотентность тоже.

Из `full`-пути проверена самая рискованная нога — **texi2any**: на реальных
исходниках texinfo 5.1 (взял из github-зеркала savannah) репный `./texi2any`
+ бандленый `HTML.pm` 5.0 поверх системного дерева 5.1 регенерит `html/`
без ошибок, на выходе well-formed xhtml с контентом книги. Это снимает главный
страх (что версия texinfo разъедется с бандленым HTML.pm). Заодно подтвердилось,
что perl-дерево грузится **без `./configure`** — поэтому в fetch-стейдже нет
C-тулчейна вообще.

Не гонял только шаг конвертации формул (get/put-math через phantomjs +
batch-prettify) — phantomjs в сэндбоксе не поднять. Но патч MathJax проверен, а
phantomjs — стандартный бинарь. Билд образа само-проверяется (`require
Texinfo::Parser` в fetch-стейдже). Если `full` всё же споткнётся — почти
наверняка это phantomjs ловит segfault на шрифтах в шаге get-math; пиши лог,
докрутим.
