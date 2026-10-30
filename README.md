# MyFirewall for OpenWrt 24.10 and 25.12

将 `proxy-block.sh` 的外部流量拦截能力做成 LuCI 页面，入口位于：

`服务 -> MyFirewall`

## 功能

- 参考“防火墙 -> 通信规则”，使用可排序、可筛选的规则表格。
- 支持“仅 MAC”“仅 IP”“MAC + IP”三种来源匹配，并可一次添加多个 MAC/IP。
- 支持 TCP、UDP 或两者同时匹配。
- 拦截目标是所有“非本机地址”，不会拦截访问路由器自身的流量。
- 支持启用/禁用单条规则。
- 支持按星期、开始时间和结束时间限制；结束时间早于开始时间时按跨午夜处理。
- “保存并应用”后自动重新生成 nftables 规则并重载 fw4。

## OpenWrt 24.10 安装（opkg）

在 OpenWrt 24.10（opkg）上执行：

```sh
opkg update
opkg install ./luci-app-myfirewall_1.0.0-r10_all.ipk
```

也可以在 LuCI 的“系统 -> 软件包”中上传安装。

## OpenWrt 25.12 安装（apk）

OpenWrt 25.12 使用 APK v3 包格式，请安装对应的 `.apk`：

```sh
apk add --allow-untrusted ./luci-app-myfirewall-1.0.0-r10.apk
```

也可以在 LuCI 的“系统 -> 软件包”中上传安装。由于这是本地构建包，
没有使用 OpenWrt 官方私钥签名，因此命令行安装时需要
`--allow-untrusted`。

安装后如果菜单尚未出现，退出 LuCI 后重新登录，或执行：

```sh
rm -f /tmp/luci-indexcache
/etc/init.d/uhttpd restart
```

## 与旧脚本共存

新页面使用 `/etc/nftables.d/90-myfirewall.nft`，不会自动覆盖旧脚本生成的
`/etc/nftables.d/99-reject-mac.nft`，以避免升级时丢失现有规则。

如果旧规则已经导入到页面，可运行旧脚本选择“清除所有拦截规则”，或确认后删除旧文件：

```sh
rm -f /etc/nftables.d/99-reject-mac.nft
fw4 reload
```

## 从源码构建

直接生成 OpenWrt 24.10 可安装的 `.ipk`：

```sh
python build-ipk.py
```

在 Linux、WSL 或 OpenWrt 25.12 SDK 环境中生成 APK：

```sh
sh build-apk.sh
```

也可以把 `package/luci-app-myfirewall` 放入 LuCI feeds 的
`applications/` 目录，通过 OpenWrt SDK 按正常流程编译。
# my-firewall
