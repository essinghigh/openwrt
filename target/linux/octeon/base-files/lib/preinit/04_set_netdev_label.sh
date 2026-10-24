set_erpoe_netdev_labels() {
	local dir label netdev

	[ "$(cat /tmp/sysinfo/board_name)" = "ubnt,edgerouter-poe" ] || return 0
	for dir in /sys/class/net/*; do
		[ -r "$dir/of_node/openwrt,netdev-name" ] || continue
		read -r label < "$dir/of_node/openwrt,netdev-name"
		netdev="${dir##*/}"
		[ "$netdev" = "$label" ] && continue
		ip link set "$netdev" name "$label"
	done
}

boot_hook_add preinit_main set_erpoe_netdev_labels
