#!/usr/bin/env python3

import hashlib
import io
import os
import pathlib
import tarfile


ROOT = pathlib.Path(__file__).resolve().parent
PACKAGE_ROOT = ROOT / "package" / "luci-app-myfirewall"
CONTENT_ROOT = PACKAGE_ROOT / "root"
DIST = ROOT / "dist"

NAME = "luci-app-myfirewall"
VERSION = "1.0.0"
RELEASE = "r8"
ARCH = "all"
FILENAME = f"{NAME}_{VERSION}-{RELEASE}_{ARCH}.ipk"

EPOCH = int(os.environ.get("SOURCE_DATE_EPOCH", "0"))


def tar_bytes(files, directories=()):
    buffer = io.BytesIO()

    with tarfile.open(fileobj=buffer, mode="w:gz", format=tarfile.GNU_FORMAT) as archive:
        for path in directories:
            info = tarfile.TarInfo(f"./{path.as_posix().rstrip('/')}/")
            info.type = tarfile.DIRTYPE
            info.mode = 0o755
            info.uid = 0
            info.gid = 0
            info.mtime = EPOCH
            archive.addfile(info)

        for name, data, mode in files:
            info = tarfile.TarInfo(f"./{name}")
            info.type = tarfile.REGTYPE
            info.mode = mode
            info.uid = 0
            info.gid = 0
            info.mtime = EPOCH
            info.size = len(data)
            archive.addfile(info, io.BytesIO(data))

    return buffer.getvalue()


def main():
    if not CONTENT_ROOT.is_dir():
        raise SystemExit(f"缺少包目录：{CONTENT_ROOT}")

    files = []
    dirs = set()

    for source in sorted(CONTENT_ROOT.rglob("*")):
        if not source.is_file():
            continue

        relative = source.relative_to(CONTENT_ROOT)
        data = source.read_bytes()
        executable = (
            relative.as_posix().startswith("etc/init.d/")
            or relative.as_posix().startswith("usr/libexec/")
        )
        mode = 0o755 if executable else 0o644
        files.append((relative.as_posix(), data, mode))

        parent = relative.parent
        while parent != pathlib.Path("."):
            dirs.add(parent)
            parent = parent.parent

    md5_lines = [
        f"{hashlib.md5(data).hexdigest()}  {name}"
        for name, data, _ in files
    ]

    control = (
        f"Package: {NAME}\n"
        f"Version: {VERSION}-{RELEASE}\n"
        "Depends: luci-base, firewall4, nftables\n"
        "Section: luci\n"
        f"Architecture: {ARCH}\n"
        f"Installed-Size: {sum(len(data) for _, data, _ in files) // 1024}\n"
        "Maintainer: MyFirewall\n"
        "Description: MyFirewall external traffic blocking rules for LuCI.\n"
        " Provides a Traffic Rules-style LuCI page under Services for\n"
        " managing MAC/IP based external TCP/UDP blocking rules with\n"
        " weekday and time restrictions.\n"
    ).encode("utf-8")

    postinst = (
        "#!/bin/sh\n"
        "[ -n \"$IPKG_INSTROOT\" ] && exit 0\n"
        "rm -f /tmp/luci-indexcache /tmp/luci-indexcache.*\n"
        "/etc/init.d/myfirewall enable >/dev/null 2>&1\n"
        "/etc/init.d/myfirewall restart\n"
        "/etc/init.d/ucitrack restart >/dev/null 2>&1\n"
        "/etc/init.d/uhttpd restart >/dev/null 2>&1\n"
        "exit 0\n"
    ).encode("utf-8")

    prerm = (
        "#!/bin/sh\n"
        "[ -n \"$IPKG_INSTROOT\" ] && exit 0\n"
        "rm -f /etc/nftables.d/90-myfirewall.nft\n"
        "[ -x /sbin/fw4 ] && /sbin/fw4 reload >/dev/null 2>&1\n"
        "exit 0\n"
    ).encode("utf-8")

    conffiles = b"/etc/config/myfirewall\n"
    md5sums = ("\n".join(md5_lines) + "\n").encode("utf-8")

    control_files = [
        ("control", control, 0o644),
        ("postinst", postinst, 0o755),
        ("prerm", prerm, 0o755),
        ("conffiles", conffiles, 0o644),
        ("md5sums", md5sums, 0o644),
    ]

    data_tar = tar_bytes(files, sorted(dirs, key=lambda p: (len(p.parts), p.as_posix())))
    control_tar = tar_bytes(control_files)

    # OpenWrt 24.10's opkg package format is a gzip-compressed outer tar
    # containing debian-binary plus the data and control tarballs.
    ipk = tar_bytes([
        ("debian-binary", b"2.0\n", 0o644),
        ("data.tar.gz", data_tar, 0o644),
        ("control.tar.gz", control_tar, 0o644),
    ])

    DIST.mkdir(exist_ok=True)
    output = DIST / FILENAME
    output.write_bytes(ipk)
    print(output)


if __name__ == "__main__":
    main()
