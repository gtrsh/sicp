# syntax=docker/dockerfile:1
#
# Сборочный образ для sarabander/sicp (HTML5 + EPUB3).
# Пайплайн 2014 года, поэтому половина зависимостей — это пины протухших
# версий. Подробности почему именно так — в комментариях ниже и в BUILD-DOCKER.md.

##############################################################################
# Стейдж 1: тянем и готовим протухшие артефакты
##############################################################################
FROM debian:bookworm-slim AS fetch

ARG TEXINFO_VERSION=5.1
ARG PHANTOMJS_VERSION=2.1.1
# 2.4.0 — это «latest» MathJax на момент сборки оригинального html (авг 2014).
# Именно он даёт MathML 1-в-1 с репным: версии >=2.7 добавили в toMathML
# <mi/>-спейсеры, displaystyle, <mstyle scriptlevel>, пустые <mo fence/> и
# другой отступ — отсюда весь шум в diff. Если фидельность не важна и нужен
# просто корректный рендер — можно вернуть 2.7.9.
ARG MATHJAX_VERSION=2.4.0

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl bzip2 xz-utils tar perl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

# --- PhantomJS 2.1.1 -------------------------------------------------------
# Заброшен с 2018, в апт-репах современных дистров его нет. Берём официальный
# пребилт-бинарь (внутри статически слинкованный Qt/WebKit). Все три скрипта
# книги (get-math/put-math/batch-prettify) — это phantomjs, а не node.
RUN curl -fsSL -o phantomjs.tar.bz2 \
      "https://bitbucket.org/ariya/phantomjs/downloads/phantomjs-${PHANTOMJS_VERSION}-linux-x86_64.tar.bz2" \
    && tar xjf phantomjs.tar.bz2 \
    && mkdir -p /opt/phantomjs/bin \
    && cp "phantomjs-${PHANTOMJS_VERSION}-linux-x86_64/bin/phantomjs" /opt/phantomjs/bin/ \
    && chmod +x /opt/phantomjs/bin/phantomjs

# --- MathJax (пин версии — см. ARG выше) -----------------------------------
# mathcell.xhtml дёргает MathJax.Hub + toMathML — это API v2 (в 3.x его
# выпилили, так что любая 2.x, но не 3.x). Оригинальный cdn.mathjax.org умер
# в 2017, поэтому вендорим локально и в entrypoint подменяем src на file://.
RUN curl -fsSL -o mathjax.tar.gz \
      "https://github.com/mathjax/MathJax/archive/refs/tags/${MATHJAX_VERSION}.tar.gz" \
    && mkdir -p /opt/mathjax \
    && tar xzf mathjax.tar.gz --strip-components=1 -C /opt/mathjax

# --- Texinfo 5.1 (только perl-дерево) --------------------------------------
# Бандленый в репе lib/Texinfo/Convert/HTML.pm — это пропатченная версия 5.0.
# Он перекрывает только HTML.pm, а Parser.pm/Structuring.pm texi2any берёт из
# системного $datadir/texinfo. Современный texinfo 6.x/7.x переписал этот
# внутренний API и ломает бандленый HTML.pm — поэтому нужен именно 5.1.
#
# Бинарь makeinfo на C нам не нужен (texi2any в репе — чистый perl), а
# perl-модули в tp/ статические (configure их не трогает) — поэтому НЕ
# конфигурим и не компилим вообще, просто копируем дерево туда, где texi2any
# сам его ищет: /usr/local/share/texinfo/{Texinfo,DebugTexinfo,lib/...}.
# Завершающий require — sanity-check, что дерево разложилось и грузится.
RUN curl -fsSL -o texinfo.tar.gz \
      "https://ftp.gnu.org/gnu/texinfo/texinfo-${TEXINFO_VERSION}.tar.gz" \
    && tar xzf texinfo.tar.gz \
    && cd "texinfo-${TEXINFO_VERSION}" \
    && mkdir -p /staging/texinfo/lib \
    && cp -r tp/Texinfo        /staging/texinfo/Texinfo \
    && cp -r tp/DebugTexinfo   /staging/texinfo/DebugTexinfo \
    && cp -r tp/maintain/lib/. /staging/texinfo/lib/ \
    && perl \
         -I/staging/texinfo \
         -I/staging/texinfo/lib/libintl-perl/lib \
         -I/staging/texinfo/lib/Unicode-EastAsianWidth/lib \
         -I/staging/texinfo/lib/Text-Unidecode/lib \
         -e 'require Texinfo::Parser; require Texinfo::Structuring; print "texinfo 5.1 perl-tree OK\n"'

##############################################################################
# Стейдж 2: рантайм сборки
##############################################################################
FROM debian:bookworm-slim

# ruby-nokogiri из апта = пребилт, не надо компилить нативку (libxml2/libxslt).
# librsvg2-bin даёт rsvg-convert — им рендерим обложку вместо inkscape.
# fontconfig/freetype нужны phantomjs'у, иначе webkit падает на шрифтах.
RUN apt-get update && apt-get install -y --no-install-recommends \
        make perl zip \
        ruby ruby-nokogiri \
        librsvg2-bin \
        fontconfig libfontconfig1 libfreetype6 fonts-dejavu-core \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=fetch /opt/phantomjs       /opt/phantomjs
COPY --from=fetch /opt/mathjax         /opt/mathjax
COPY --from=fetch /staging/texinfo     /usr/local/share/texinfo

ENV PATH="/opt/phantomjs/bin:${PATH}"
# КРИТИЧНО: без UTF-8 локали create_metafiles.rb падает с
# 'invalid byte sequence in US-ASCII' — Ruby читает UTF-8 xhtml как ASCII
# (Encoding.default_external = US-ASCII в голом контейнере). C.UTF-8 есть в
# debian из коробки, пакет locales не нужен. Заодно нужно texi2any для .texi.
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8
# PhantomJS уже headless и использует свой собственный QPA-плагин 'phantom'.
# НЕ задаём QT_QPA_PLATFORM: плагина 'offscreen' в его собранном Qt нет, и
# любой запуск падает с 'could not find the offscreen plugin' + core dump.
# OPENSSL_CONF=/dev/null — воркэраунд краша phantomjs 2.1.1 на парсинге
# системного openssl.cnf на некоторых хостах (для file:// безвреден).
ENV OPENSSL_CONF=/dev/null

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["epub"]
