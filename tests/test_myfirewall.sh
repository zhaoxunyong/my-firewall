#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM

cat > "$TEST_DIR/functions.sh" <<'EOF'
config_load() {
	return 0
}

config_get_bool() {
	_var="$1"
	_section="$2"
	_option="$3"
	_default="$4"

	case "$_section:$_option" in
		settings:enabled) eval "$_var=${TEST_GLOBAL_ENABLED:-1}" ;;
		rule_1:enabled) eval "$_var=1" ;;
		rule_1:timed) eval "$_var=1" ;;
		rule_2:enabled) eval "$_var=0" ;;
		rule_3:enabled) eval "$_var=1" ;;
		rule_3:timed) eval "$_var=0" ;;
		*) eval "$_var=$_default" ;;
	esac
}

config_get() {
	_var="$1"
	_section="$2"
	_option="$3"
	_default="$4"

	case "$_section:$_option" in
		rule_1:name) eval "$_var='客厅电视'" ;;
		rule_1:match) eval "$_var=mac" ;;
		rule_1:src_mac_LENGTH) eval "$_var=2" ;;
		rule_1:src_mac) eval "$_var='aa-bb-cc-dd-ee-01 AA:BB:CC:DD:EE:02'" ;;
		rule_1:src_mac_ITEM1) eval "$_var='aa-bb-cc-dd-ee-01'" ;;
		rule_1:src_mac_ITEM2) eval "$_var='AA:BB:CC:DD:EE:02'" ;;
		rule_1:protocol) eval "$_var=tcp_udp" ;;
		rule_1:start_time) eval "$_var='22:30:00'" ;;
		rule_1:stop_time) eval "$_var='06:00:00'" ;;
		rule_1:weekdays) eval "$_var='Mon Wed'" ;;
		rule_3:name) eval "$_var='IPv6 主机'" ;;
		rule_3:match) eval "$_var=ip" ;;
		rule_3:src_ip_LENGTH) eval "$_var=2" ;;
		rule_3:src_ip) eval "$_var='192.168.1.30 2001:db8::20'" ;;
		rule_3:src_ip_ITEM1) eval "$_var='192.168.1.30'" ;;
		rule_3:src_ip_ITEM2) eval "$_var='2001:db8::20'" ;;
		rule_3:protocol) eval "$_var=tcp" ;;
		rule_4:name) eval "$_var='多设备 MAC 和 IP'" ;;
		rule_4:match) eval "$_var=both" ;;
		rule_4:src_mac_LENGTH) eval "$_var=2" ;;
		rule_4:src_mac) eval "$_var='AA:BB:CC:DD:EE:10 AA:BB:CC:DD:EE:11'" ;;
		rule_4:src_mac_ITEM1) eval "$_var='AA:BB:CC:DD:EE:10'" ;;
		rule_4:src_mac_ITEM2) eval "$_var='AA:BB:CC:DD:EE:11'" ;;
		rule_4:src_ip_LENGTH) eval "$_var=2" ;;
		rule_4:src_ip) eval "$_var='192.168.1.40 192.168.1.41'" ;;
		rule_4:src_ip_ITEM1) eval "$_var='192.168.1.40'" ;;
		rule_4:src_ip_ITEM2) eval "$_var='192.168.1.41'" ;;
		rule_5:name) eval "$_var='旧版单值配置'" ;;
		rule_5:match) eval "$_var=mac" ;;
		rule_5:src_mac) eval "$_var='aa-bb-cc-dd-ee-50'" ;;
		*) eval "$_var=$_default" ;;
	esac
}

config_list_foreach() {
	local section="$1"
	local option="$2"
	local callback="$3"
	local length value count=0

	config_get length "$section" "${option}_LENGTH" ""
	while [ -n "$length" ] && [ "$count" -lt "$length" ]; do
		count=$((count + 1))
		config_get value "$section" "${option}_ITEM${count}" ""
		"$callback" "$value"
	done
}

config_foreach() {
	_callback="$1"
	_type="$2"

	[ "$_type" = "rule" ] || return 0
	[ "${TEST_HAS_RULES:-1}" = "1" ] || return 0
	"$_callback" rule_1
	"$_callback" rule_2
	"$_callback" rule_3
	"$_callback" rule_4
	"$_callback" rule_5
}
EOF

cat > "$TEST_DIR/nft" <<'EOF'
#!/bin/sh
[ "$1" = "-c" ] || exit 2
grep -q 'table inet myfirewall_validate' "$3"
EOF
chmod +x "$TEST_DIR/nft"

MYFIREWALL_FUNCTIONS_LIB="$TEST_DIR/functions.sh" \
MYFIREWALL_NFT_FILE="$TEST_DIR/rules.nft" \
MYFIREWALL_NFT_BIN="$TEST_DIR/nft" \
	"$ROOT/package/luci-app-myfirewall/root/usr/libexec/myfirewall" generate

grep -q 'ether saddr { AA:BB:CC:DD:EE:01, AA:BB:CC:DD:EE:02 }' "$TEST_DIR/rules.nft"
grep -q 'ip saddr { 192.168.1.30 }' "$TEST_DIR/rules.nft"
grep -q 'meta day { Monday, Wednesday }' "$TEST_DIR/rules.nft"
grep -q 'meta hour "00:00:00"-"06:00:00"' "$TEST_DIR/rules.nft"
grep -q 'meta hour "22:30:00"-"23:59:59"' "$TEST_DIR/rules.nft"
grep -q 'ip6 saddr { 2001:db8::20 }' "$TEST_DIR/rules.nft"
grep -q 'ether saddr { AA:BB:CC:DD:EE:10, AA:BB:CC:DD:EE:11 } ip saddr { 192.168.1.40, 192.168.1.41 }' "$TEST_DIR/rules.nft"
grep -q 'ether saddr { AA:BB:CC:DD:EE:50 }' "$TEST_DIR/rules.nft"
grep -q 'meta l4proto tcp ' "$TEST_DIR/rules.nft"
! grep -q 'should-not-render' "$TEST_DIR/rules.nft"
[ "$(grep -c 'counter drop' "$TEST_DIR/rules.nft")" -eq 6 ]

printf 'stale\n' > "$TEST_DIR/rules.nft"
TEST_GLOBAL_ENABLED=0 \
MYFIREWALL_FUNCTIONS_LIB="$TEST_DIR/functions.sh" \
MYFIREWALL_NFT_FILE="$TEST_DIR/rules.nft" \
MYFIREWALL_NFT_BIN="$TEST_DIR/nft" \
	"$ROOT/package/luci-app-myfirewall/root/usr/libexec/myfirewall" generate
[ ! -f "$TEST_DIR/rules.nft" ]

printf 'stale\n' > "$TEST_DIR/rules.nft"
TEST_HAS_RULES=0 \
MYFIREWALL_FUNCTIONS_LIB="$TEST_DIR/functions.sh" \
MYFIREWALL_NFT_FILE="$TEST_DIR/rules.nft" \
MYFIREWALL_NFT_BIN="$TEST_DIR/nft" \
	"$ROOT/package/luci-app-myfirewall/root/usr/libexec/myfirewall" generate
[ ! -f "$TEST_DIR/rules.nft" ]

printf 'MyFirewall rule generation tests passed.\n'
