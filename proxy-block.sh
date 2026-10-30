#!/bin/sh

NFT_FILE="/etc/nftables.d/99-reject-mac.nft"
CHAIN_NAME="reject_mac_early"
DISABLED_PREFIX="# DISABLED "

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}   HomeProxy 外部流量拦截管理脚本${NC}"
    echo -e "${GREEN}========================================${NC}"
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}请使用 root 用户运行此脚本${NC}"
        exit 1
    fi
}

reload_fw() {
    echo -e "${YELLOW}正在重新加载防火墙...${NC}"
    fw4 reload >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}防火墙已重新加载${NC}"
    else
        echo -e "${RED}防火墙加载失败，请检查规则语法${NC}"
    fi
}

show_current() {
    echo -e "\n${YELLOW}当前规则：${NC}"
    if [ -f "$NFT_FILE" ]; then
        echo -e "${BLUE}---------- nft 实际生效规则 ----------${NC}"
        nft list chain inet fw4 $CHAIN_NAME 2>/dev/null || echo "链未加载"
        echo -e "\n${BLUE}---------- 规则文件内容 ----------${NC}"
        cat "$NFT_FILE"
    else
        echo "当前没有拦截规则"
    fi
}

gen_header() {
    cat << HEADER
chain $CHAIN_NAME {
        type filter hook prerouting priority mangle - 20; policy accept;

HEADER
}

validate_mac() {
    local mac="$1"
    echo "$mac" | grep -Eq '^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$'
    return $?
}

validate_time() {
    local time="$1"
    echo "$time" | grep -Eq '^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$'
    return $?
}

parse_weekdays() {
    local input="$1"
    local result=""

    expanded=""
    for part in $(echo "$input" | tr ',' ' '); do
        if echo "$part" | grep -q '-'; then
            start=$(echo "$part" | cut -d'-' -f1)
            end=$(echo "$part" | cut -d'-' -f2)
            if ! echo "$start" | grep -Eq '^[1-7]$' || ! echo "$end" | grep -Eq '^[1-7]$'; then
                return 1
            fi
            i=$start
            while [ "$i" -le "$end" ]; do
                expanded="$expanded $i"
                i=$((i + 1))
            done
        else
            if ! echo "$part" | grep -Eq '^[1-7]$'; then
                return 1
            fi
            expanded="$expanded $part"
        fi
    done

    for d in $expanded; do
        case $d in
            1) name="Monday" ;;
            2) name="Tuesday" ;;
            3) name="Wednesday" ;;
            4) name="Thursday" ;;
            5) name="Friday" ;;
            6) name="Saturday" ;;
            7) name="Sunday" ;;
            *) continue ;;
        esac
        if [ -z "$result" ]; then
            result="$name"
        else
            result="$result, $name"
        fi
    done
    echo "$result"
}

add_rule() {
    local mac="$1"
    local ip="$2"
    local start_hour="$3"
    local end_hour="$4"
    local weekdays="$5"
    local comment="$6"

    match=""
    [ -n "$mac" ] && match="$match ether saddr $mac"
    [ -n "$ip" ]  && match="$match ip saddr $ip"
    match="$match fib daddr type != local meta l4proto { tcp, udp }"

    comment_str=""
    if [ -n "$comment" ]; then
        comment_str=" comment \"$comment\""
    fi

    if [ -n "$start_hour" ] && [ -n "$end_hour" ]; then
        if [ -n "$weekdays" ]; then
            echo "        ${match} meta day { $weekdays } meta hour \"${start_hour}\"-\"${end_hour}\" counter drop${comment_str}"
        else
            echo "        ${match} meta hour \"${start_hour}\"-\"${end_hour}\" counter drop${comment_str}"
        fi
    else
        echo "        ${match} counter drop${comment_str}"
    fi
}

write_rules() {
    local content="$1"
    if [ -z "$(echo -e "$content" | sed '/^$/d')" ]; then
        rm -f "$NFT_FILE"
        echo -e "${YELLOW}规则已全部清空${NC}"
    else
        gen_header > "$NFT_FILE"
        echo -e "$content" >> "$NFT_FILE"
        echo "}" >> "$NFT_FILE"
    fi
    reload_fw
    show_current
}

get_rule_lines() {
    if [ ! -f "$NFT_FILE" ]; then
        return
    fi
    sed -n '/type filter/,/^}/p' "$NFT_FILE" | sed '1d;$d' | grep -E '^[[:space:]]*(# DISABLED )?(ether|ip)[[:space:]]' | sed 's/^[[:space:]]*//'
}

print_numbered() {
    local i=1
    echo "$1" | while IFS= read -r line; do
        status="启用"
        display_line="$line"
        case "$line" in
            "$DISABLED_PREFIX"*)
                status="禁用"
                display_line=$(echo "$line" | sed "s/^# DISABLED //")
                ;;
        esac
        printf "%2d. [%s] %s\n" "$i" "$status" "$display_line"
        i=$((i + 1))
    done
}

confirm_action() {
    echo -e "\n${YELLOW}请确认以上操作 (Y/n):${NC}"
    read -p "> " confirm
    if [ -z "$confirm" ] || [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        return 0
    else
        echo -e "${RED}已取消操作${NC}"
        return 1
    fi
}

menu_add() {
    echo -e "\n${YELLOW}【添加拦截规则】${NC}"
    echo "1. 仅 MAC"
    echo "2. 仅 IP"
    echo "3. MAC + IP"
    read -p "请选择类型 [1-3]: " type

    mac=""
    ip=""
    case $type in
        1)
            while true; do
                read -p "请输入 MAC 地址 (例如 08:26:AE:39:54:13): " mac
                if validate_mac "$mac"; then
                    break
                else
                    echo -e "${RED}MAC 地址格式错误，请重新输入（示例：08:26:AE:39:54:13）${NC}"
                fi
            done
            ;;
        2)
            read -p "请输入 IP 地址 (例如 192.168.8.100): " ip
            ;;
        3)
            while true; do
                read -p "请输入 MAC 地址: " mac
                if validate_mac "$mac"; then
                    break
                else
                    echo -e "${RED}MAC 地址格式错误，请重新输入（示例：08:26:AE:39:54:13）${NC}"
                fi
            done
            read -p "请输入 IP 地址: " ip
            ;;
        *) echo -e "${RED}无效选择${NC}"; return ;;
    esac

    # 新增：输入 comment（可为空）
    read -p "请输入备注 comment（可直接回车为空）: " comment

    echo -e "\n时间控制（填写【禁止】的时间段）："
    echo "1. 全天禁止"
    echo "2. 指定禁止时段 + 星期"
    read -p "请选择 [1-2]: " time_type

    rules=""
    case $time_type in
        1)
            rules=$(add_rule "$mac" "$ip" "" "" "" "$comment")
            ;;
        2)
            while true; do
                read -p "禁止开始时间 (HH:MM 或 HH:MM:SS，例如 00:00:30): " start
                if validate_time "$start"; then
                    break
                else
                    echo -e "${RED}时间格式错误，请输入 HH:MM 或 HH:MM:SS（00:00:00 - 23:59:59）${NC}"
                fi
            done

            while true; do
                read -p "禁止结束时间 (HH:MM 或 HH:MM:SS，例如 06:30:15): " end
                if validate_time "$end"; then
                    break
                else
                    echo -e "${RED}时间格式错误，请输入 HH:MM 或 HH:MM:SS（00:00:00 - 23:59:59）${NC}"
                fi
            done

            echo ""
            echo "星期设置说明："
            echo "  1=周一 2=周二 3=周三 4=周四 5=周五 6=周六 7=周日"
            echo "  示例: 1,3,5   或  1-5   或  1-3,5,7"
            echo "  留空表示每天"
            read -p "请输入要禁止的星期 (直接回车=每天): " day_input

            weekdays=""
            if [ -n "$day_input" ]; then
                weekdays=$(parse_weekdays "$day_input")
                if [ -z "$weekdays" ]; then
                    echo -e "${RED}星期格式错误，请重新添加规则${NC}"
                    return
                fi
            fi
            rules=$(add_rule "$mac" "$ip" "$start" "$end" "$weekdays" "$comment")
            ;;
        *) echo -e "${RED}无效选择${NC}"; return ;;
    esac

    echo -e "\n${BLUE}即将添加的规则（启用）：${NC}"
    echo "$rules"
    if ! confirm_action; then
        return
    fi

    old_content=$(get_rule_lines)
    if [ -n "$old_content" ]; then
        new_content="${old_content}
${rules}"
    else
        new_content="$rules"
    fi

    write_rules "$new_content"
    echo -e "${GREEN}规则已添加并生效${NC}"
}

menu_toggle() {
    echo -e "\n${YELLOW}【启用 / 禁用拦截规则】${NC}"

    if [ ! -f "$NFT_FILE" ]; then
        echo "当前没有任何规则"
        return
    fi

    lines=$(get_rule_lines)
    if [ -z "$lines" ]; then
        echo "当前没有任何规则"
        return
    fi

    echo -e "${BLUE}当前规则列表：${NC}"
    print_numbered "$lines"

    total=$(echo "$lines" | wc -l)
    echo ""
    read -p "请输入要切换启用状态的序号 (1-$total，多个用空格分隔): " input
    if [ -z "$input" ]; then
        echo -e "${RED}你没有输入任何序号，操作已取消${NC}"
        return
    fi

    for num in $input; do
        if ! [ "$num" -ge 1 ] 2>/dev/null || ! [ "$num" -le "$total" ] 2>/dev/null; then
            echo -e "${RED}输入的序号无效，操作已取消${NC}"
            return
        fi
    done

    echo -e "\n${BLUE}即将切换以下规则的启用状态：${NC}"
    i=1
    echo "$lines" | while IFS= read -r line; do
        for num in $input; do
            if [ "$i" -eq "$num" ]; then
                echo "  $i. $line"
            fi
        done
        i=$((i + 1))
    done

    if ! confirm_action; then
        return
    fi

    new_content=$(
        i=1
        echo "$lines" | while IFS= read -r line; do
            selected=0
            for num in $input; do
                if [ "$i" -eq "$num" ]; then
                    selected=1
                    break
                fi
            done

            if [ "$selected" -eq 1 ]; then
                case "$line" in
                    "$DISABLED_PREFIX"*)
                        echo "$line" | sed "s/^# DISABLED //"
                        ;;
                    *)
                        echo "${DISABLED_PREFIX}${line}"
                        ;;
                esac
            else
                echo "$line"
            fi
            i=$((i + 1))
        done
    )

    write_rules "$new_content"
    echo -e "${GREEN}规则启用状态已更新${NC}"
}

menu_delete_one() {
    echo -e "\n${YELLOW}【清除指定拦截规则】${NC}"

    if [ ! -f "$NFT_FILE" ]; then
        echo "当前没有任何规则"
        return
    fi

    lines=$(get_rule_lines)
    if [ -z "$lines" ]; then
        echo "当前没有任何规则"
        return
    fi

    echo -e "${BLUE}当前规则列表：${NC}"
    print_numbered "$lines"

    total=$(echo "$lines" | wc -l)
    echo ""
    read -p "请输入要删除的规则序号 (1-$total，多个用空格分隔，输入 all 删除全部): " input

    if [ -z "$input" ]; then
        echo -e "${RED}你没有输入任何序号，操作已取消${NC}"
        return
    fi

    if [ "$input" = "all" ] || [ "$input" = "ALL" ]; then
        echo -e "\n${YELLOW}即将删除【全部】规则${NC}"
        if ! confirm_action; then
            return
        fi
        rm -f "$NFT_FILE"
        reload_fw
        echo -e "${GREEN}已删除全部规则${NC}"
        return
    fi

    valid=0
    for num in $input; do
        if [ "$num" -ge 1 ] 2>/dev/null && [ "$num" -le "$total" ] 2>/dev/null; then
            valid=1
            break
        fi
    done
    if [ $valid -eq 0 ]; then
        echo -e "${RED}输入的序号无效，操作已取消${NC}"
        return
    fi

    echo -e "\n${BLUE}即将删除以下规则：${NC}"
    i=1
    echo "$lines" | while read -r line; do
        for num in $input; do
            if [ "$i" -eq "$num" ]; then
                echo "  $i. $line"
            fi
        done
        i=$((i + 1))
    done

    if ! confirm_action; then
        return
    fi

    i=1
    echo "$lines" | while read -r line; do
        delete=0
        for num in $input; do
            if [ "$i" -eq "$num" ]; then
                delete=1
                break
            fi
        done
        if [ $delete -eq 0 ]; then
            echo "$line"
        fi
        i=$((i + 1))
    done > /tmp/proxy_block_new.rules

    new_content=$(cat /tmp/proxy_block_new.rules 2>/dev/null)
    rm -f /tmp/proxy_block_new.rules

    write_rules "$new_content"
    echo -e "${GREEN}指定规则已删除${NC}"
}

menu_clear() {
    echo -e "\n${YELLOW}即将删除【所有】拦截规则${NC}"
    if ! confirm_action; then
        return
    fi
    rm -f "$NFT_FILE"
    reload_fw
    echo -e "${GREEN}所有拦截规则已清除${NC}"
}

main_menu() {
    while true; do
        print_header
        echo "1. 查看当前规则"
        echo "2. 添加拦截规则（MAC / IP / 时间）"
        echo "3. 启用 / 禁用拦截规则"
        echo "4. 清除指定拦截规则"
        echo "5. 清除所有拦截规则"
        echo "6. 手动重新加载防火墙"
        echo "0. 退出"
        echo "----------------------------------------"
        read -p "请选择操作 [0-6]: " choice

        case $choice in
            1) show_current ;;
            2) menu_add ;;
            3) menu_toggle ;;
            4) menu_delete_one ;;
            5) menu_clear ;;
            6) reload_fw ;;
            0) echo "退出"; exit 0 ;;
            *) echo -e "${RED}无效选择${NC}" ;;
        esac

        echo ""
        read -p "按回车键继续..."
    done
}

if [ "${PROXY_BLOCK_NO_MAIN:-0}" != "1" ]; then
    check_root
    main_menu
fi
