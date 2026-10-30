#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
SOURCE_ROOT="$ROOT/package/luci-app-myfirewall/root"
DIST="$ROOT/dist"
PKG_NAME="luci-app-myfirewall"
PKG_VERSION="1.0.0-r12"
OUTPUT="$DIST/$PKG_NAME-$PKG_VERSION.apk"

if ! command -v apk >/dev/null 2>&1; then
	printf '缺少 apk 命令；请在 Alpine/WSL 或 OpenWrt 25.12 SDK 环境运行。\n' >&2
	exit 1
fi

APK_VERSION="$(apk --version 2>/dev/null || true)"
case "$APK_VERSION" in
apk-tools\ 3.*)
	;;
*)
	printf '当前 apk-tools 不支持 mkpkg，请使用 apk-tools 3.x。\n' >&2
	exit 1
	;;
esac

if [ ! -d "$SOURCE_ROOT" ]; then
	printf '缺少包目录：%s\n' "$SOURCE_ROOT" >&2
	exit 1
fi

mkdir -p "$DIST"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/myfirewall-apk.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

STAGE="$WORK/root"
SCRIPTS="$WORK/scripts"
mkdir -p "$STAGE" "$SCRIPTS"
cp -a "$SOURCE_ROOT/." "$STAGE/"

find "$STAGE" -type d -exec chmod 0755 {} +
find "$STAGE" -type f -exec chmod 0644 {} +
chmod 0755 "$STAGE/etc/init.d/myfirewall" "$STAGE/usr/libexec/myfirewall"
chown -R 0:0 "$STAGE"

mkdir -p "$STAGE/lib/apk/packages"
(
	cd "$STAGE"
	find . -type f -o -type l | sed 's|^\./|/|' | sort
) > "$WORK/$PKG_NAME.list"
mv "$WORK/$PKG_NAME.list" "$STAGE/lib/apk/packages/$PKG_NAME.list"

printf '/etc/config/myfirewall\n' > "$STAGE/lib/apk/packages/$PKG_NAME.conffiles"
CONFIG_SUM="$(sha256sum "$STAGE/etc/config/myfirewall" | awk '{ print $1 }')"
printf '/etc/config/myfirewall %s\n' "$CONFIG_SUM" \
	> "$STAGE/lib/apk/packages/$PKG_NAME.conffiles_static"

cat > "$SCRIPTS/post-install" <<'EOF'
#!/bin/sh
[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s "${IPKG_INSTROOT}/lib/functions.sh" ] || exit 0
. "${IPKG_INSTROOT}/lib/functions.sh"
export root="${IPKG_INSTROOT}"
export pkgname="luci-app-myfirewall"
add_group_and_user
default_postinst

[ -n "${IPKG_INSTROOT}" ] || {
	/etc/init.d/myfirewall enable >/dev/null 2>&1
	rm -f /tmp/luci-indexcache /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	(
		sleep 1
		/etc/init.d/myfirewall restart
		/etc/init.d/ucitrack restart >/dev/null 2>&1
	) </dev/null >/tmp/myfirewall-install.log 2>&1 &
}
exit 0
EOF

{
	printf '#!/bin/sh\n'
	printf 'export PKG_UPGRADE=1\n'
	sed '/^#!/d' "$SCRIPTS/post-install"
} > "$SCRIPTS/post-upgrade"

cat > "$SCRIPTS/pre-deinstall" <<'EOF'
#!/bin/sh
[ -s "${IPKG_INSTROOT}/lib/functions.sh" ] || exit 0
. "${IPKG_INSTROOT}/lib/functions.sh"
export root="${IPKG_INSTROOT}"
export pkgname="luci-app-myfirewall"
default_prerm

[ -n "${IPKG_INSTROOT}" ] || {
	rm -f /etc/nftables.d/90-myfirewall.nft
	[ -x /sbin/fw4 ] && /sbin/fw4 reload >/dev/null 2>&1
}
exit 0
EOF

chmod 0755 "$SCRIPTS/post-install" "$SCRIPTS/post-upgrade" "$SCRIPTS/pre-deinstall"
chown -R 0:0 "$SCRIPTS"

apk mkpkg \
	--info "name:$PKG_NAME" \
	--info "version:$PKG_VERSION" \
	--info "description:External MAC/IP traffic blocking rules for LuCI" \
	--info "arch:noarch" \
	--info "license:Apache-2.0" \
	--info "origin:local/$PKG_NAME" \
	--info "url:https://openwrt.org/" \
	--info "maintainer:MyFirewall" \
	--info "depends:luci-base firewall4 nftables" \
	--script "post-install:$SCRIPTS/post-install" \
	--script "post-upgrade:$SCRIPTS/post-upgrade" \
	--script "pre-deinstall:$SCRIPTS/pre-deinstall" \
	--files "$STAGE" \
	--output "$OUTPUT"

printf '%s\n' "$OUTPUT"
