#!/usr/bin/env bash

set -ex

# See: https://bugzilla.redhat.com/show_bug.cgi?id=1051816
find /usr/share/locale -mindepth  1 -maxdepth 1 -type d -not -name "en_US" -not -name "ja" -not -name "ja_JP" -exec rm -rf {} +
localedef --list-archive | grep -a -v ^"en_US\|ja\|ja_jp" | xargs localedef --delete-from-archive
mv -f /usr/lib/locale/locale-archive /usr/lib/locale/locale-archive.tmpl
build-locale-archive
