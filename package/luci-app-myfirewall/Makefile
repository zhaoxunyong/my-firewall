#
# Copyright (C) 2026
#
# This is free software, licensed under the Apache License, Version 2.0.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-myfirewall
PKG_VERSION:=1.0.0
PKG_RELEASE:=12
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=MyFirewall

LUCI_TITLE:=MyFirewall external traffic blocking rules
LUCI_DEPENDS:=+luci-base +firewall4 +nftables
LUCI_PKGARCH:=all

define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.*
/etc/init.d/myfirewall enable >/dev/null 2>&1
rm -rf /tmp/luci-modulecache/
(
  sleep 1
  /etc/init.d/myfirewall restart
  /etc/init.d/ucitrack restart >/dev/null 2>&1
) </dev/null >/tmp/myfirewall-install.log 2>&1 &
exit 0
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
rm -f /etc/nftables.d/90-myfirewall.nft
[ -x /sbin/fw4 ] && /sbin/fw4 reload >/dev/null 2>&1
exit 0
endef

include ../../luci.mk
