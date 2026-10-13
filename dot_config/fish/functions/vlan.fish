function vlan --description "Multi-VLAN Cisco Trunk and vNIC Manager (NetworkManager)"
    python3 ~/.config/scripts/vlan.py $argv
end

# Auto-completions
complete -c vlan -s s -l status -d "Show current VLAN interfaces and routing status"
complete -c vlan -s r -l reset -d "Remove VLAN sub-interfaces and restore eno1 to default"
complete -c vlan -s h -l help -d "Show help and usage"
