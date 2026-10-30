#!/usr/bin/env python3

import io
import pathlib
import tarfile


ROOT = pathlib.Path(__file__).resolve().parent.parent
IPK = ROOT / "dist" / "luci-app-myfirewall_1.0.0-r10_all.ipk"


def read_ipk_outer(data):
    if not data.startswith(b"\x1f\x8b"):
        raise AssertionError("IPK 缺少 OpenWrt 24.10 使用的 gzip 文件头")

    members = {}

    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        for member in archive:
            if member.isfile():
                members[member.name] = archive.extractfile(member).read()

    return members


def read_tar(data):
    entries = {}

    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        for member in archive:
            if member.isfile():
                entries[member.name] = (archive.extractfile(member).read(), member.mode)

    return entries


def assert_valid_data_tar(data):
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        for member in archive:
            assert member.isdir() or member.isfile(), f"条目类型错误: {member.name}"


def main():
    members = read_ipk_outer(IPK.read_bytes())
    assert list(members) == ["./debian-binary", "./data.tar.gz", "./control.tar.gz"]
    assert members["./debian-binary"] == b"2.0\n"

    control = read_tar(members["./control.tar.gz"])
    data = read_tar(members["./data.tar.gz"])
    assert_valid_data_tar(members["./data.tar.gz"])

    control_text = control["./control"][0].decode("utf-8")
    assert "Package: luci-app-myfirewall\n" in control_text
    assert "Version: 1.0.0-r10\n" in control_text
    assert "Architecture: all\n" in control_text
    assert control["./postinst"][1] & 0o111
    assert control["./prerm"][1] & 0o111
    postinst_text = control["./postinst"][0].decode("utf-8")
    assert "/etc/init.d/ucitrack restart" in postinst_text
    assert "/etc/init.d/myfirewall restart" in postinst_text
    assert "uhttpd restart" not in postinst_text
    assert "&\n" in postinst_text

    expected = {
        "./etc/config/myfirewall": False,
        "./etc/init.d/myfirewall": True,
        "./usr/libexec/myfirewall": True,
        "./usr/share/luci/menu.d/luci-app-myfirewall.json": False,
        "./usr/share/rpcd/acl.d/luci-app-myfirewall.json": False,
        "./usr/share/ucitrack/luci-app-myfirewall.json": False,
        "./www/luci-static/resources/view/myfirewall/rules-v10.js": False,
    }

    for name, executable in expected.items():
        assert name in data, f"缺少 {name}"
        assert bool(data[name][1] & 0o111) == executable, f"{name} 权限不正确"

    view = data["./www/luci-static/resources/view/myfirewall/rules-v10.js"][0].decode("utf-8")
    assert "].concat(sourceText(section_id))" in view
    assert "o = s.option(form.MultiValue, 'weekdays'" in view
    assert "o = s.option(form.DynamicList, 'src_mac'" in view
    assert "o = s.option(form.DynamicList, 'src_ip'" in view
    assert "o.datatype = 'ipaddr'" not in view
    assert "if (value == null || value == '')" in view

    print(f"IPK verification passed: {IPK}")


if __name__ == "__main__":
    main()
