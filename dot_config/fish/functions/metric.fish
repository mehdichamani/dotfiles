function metric --description "Toggle default gateway metric between eno1 and eno1.400 permanently via NetworkManager"
    set -l conn_eno1 "Wired connection 1"
    set -l conn_vlan "eno1.400"

    set -l m_eno1 (nmcli -g ipv4.route-metric connection show "$conn_eno1" 2>/dev/null)
    set -l m_vlan (nmcli -g ipv4.route-metric connection show "$conn_vlan" 2>/dev/null)

    # Defaults if unset
    test -z "$m_eno1"; and set m_eno1 100
    test -z "$m_vlan"; and set m_vlan 100

    echo (set_color --bold blue)"== Current Route Metrics (NetworkManager) =="(set_color normal)
    if test "$m_eno1" -lt "$m_vlan"
        echo (set_color green)"  ● eno1 (Wired connection 1): metric $m_eno1 [ACTIVE DEFAULT]"(set_color normal)
        echo (set_color yellow)"  ○ eno1.400: metric $m_vlan [STANDBY]"(set_color normal)
        set target "eno1.400"
        set new_m_eno1 150
        set new_m_vlan 50
    else if test "$m_vlan" -lt "$m_eno1"
        echo (set_color yellow)"  ○ eno1 (Wired connection 1): metric $m_eno1 [STANDBY]"(set_color normal)
        echo (set_color green)"  ● eno1.400: metric $m_vlan [ACTIVE DEFAULT]"(set_color normal)
        set target "eno1"
        set new_m_eno1 50
        set new_m_vlan 150
    else
        echo (set_color yellow)"  = eno1: metric $m_eno1 (EQUAL)"(set_color normal)
        echo (set_color yellow)"  = eno1.400: metric $m_vlan (EQUAL)"(set_color normal)
        set target "eno1"
        set new_m_eno1 50
        set new_m_vlan 150
    end

    echo ""
    read -P "Switch priority to $target? [y/N]: " -l confirm
    if test "$confirm" != "y" -a "$confirm" != "Y"
        echo (set_color red)"Aborted."(set_color normal)
        return 0
    end

    echo (set_color cyan)"Applying metrics via NetworkManager..."(set_color normal)
    nmcli connection modify "$conn_eno1" ipv4.route-metric $new_m_eno1
    nmcli connection modify "$conn_vlan" ipv4.route-metric $new_m_vlan
    nmcli connection up "$conn_eno1" >/dev/null
    nmcli connection up "$conn_vlan" >/dev/null

    echo (set_color green)"Successfully switched!"(set_color normal)
    echo (set_color blue)"Current Default Route:"(set_color normal)
    ip route show default
end
