#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
APK_FILE="$ROOT/dist/luci-app-myfirewall-1.0.0-r8.apk"

[ -f "$APK_FILE" ] || {
	printf '缺少 APK：%s\n' "$APK_FILE" >&2
	exit 1
}

DUMP="$(apk adbdump "$APK_FILE")"

for needle in \
	'name: luci-app-myfirewall' \
	'version: 1.0.0-r8' \
	'arch: noarch' \
	'depends: # 3 items' \
	'post-install:' \
	'post-upgrade:' \
	'pre-deinstall:' \
	'name: rules-v8.js' \
	'name: etc/init.d' \
	'name: usr/libexec' \
	'conffiles_static'
do
	if ! printf '%s\n' "$DUMP" | grep -qF -- "$needle"; then
		printf 'APK 元数据缺少：%s\n' "$needle" >&2
		exit 1
	fi
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/myfirewall-apk-verify.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

apk --allow-untrusted extract --destination "$WORK" "$APK_FILE" >/dev/null

sh -n "$WORK/etc/init.d/myfirewall"
sh -n "$WORK/usr/libexec/myfirewall"

[ "$(stat -c '%a' "$WORK/etc/init.d/myfirewall")" = "755" ]
[ "$(stat -c '%a' "$WORK/usr/libexec/myfirewall")" = "755" ]
[ "$(stat -c '%a' "$WORK/etc/config/myfirewall")" = "644" ]
[ "$(stat -c '%a' "$WORK/www/luci-static/resources/view/myfirewall/rules-v8.js")" = "644" ]

grep -qx '/etc/config/myfirewall' "$WORK/lib/apk/packages/luci-app-myfirewall.conffiles"
grep -q '^/etc/config/myfirewall [0-9a-f]\{64\}$' \
	"$WORK/lib/apk/packages/luci-app-myfirewall.conffiles_static"
grep -qx '/www/luci-static/resources/view/myfirewall/rules-v8.js' \
	"$WORK/lib/apk/packages/luci-app-myfirewall.list"

if grep -q '^/lib/apk/packages/' "$WORK/lib/apk/packages/luci-app-myfirewall.list"; then
	printf 'APK 文件清单不应包含自身元数据。\n' >&2
	exit 1
fi

printf 'APK verification passed: %s\n' "$APK_FILE"
