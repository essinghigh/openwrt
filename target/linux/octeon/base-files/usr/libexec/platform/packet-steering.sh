#!/bin/sh

. /lib/functions.sh

if [ "$(board_name)" = "ubnt,edgerouter-poe" ] && [ -d /sys/bus/platform/drivers/octeon_pip ]; then
	steering="${1:-1}"
	for dev in lan0 lan1 switchcpu lan2 lan3 lan4; do
		mask=0
		case "$dev:$steering" in
			lan0:1|lan0:2|lan1:1|lan1:2|switchcpu:1|switchcpu:2) mask=2 ;;
		esac
		for path in /sys/class/net/"$dev"/queues/rx-*/rps_cpus; do
			[ -e "$path" ] && echo "$mask" > "$path"
		done
	done
	for group in 0 1; do
		irq="$(awk -v group="$group" '$4 == "CIU" && $5 == group && $6 == "octeon_pip" { sub(/:$/, "", $1); print $1 }' /proc/interrupts)"
		[ -n "$irq" ] || continue
		mask=1
		case "$steering" in
			1|2) ;;
			*) mask=$((1 << group)) ;;
		esac
		echo "$mask" > "/proc/irq/$irq/smp_affinity"
	done
	exit 0
fi

case "$1" in
	1|2)
		flows="$(uci -q get 'network.@globals[0].steering_flows')"
		case "$flows" in
			''|*[!0-9]*) flows=0 ;;
		esac
		if [ "$flows" -gt 0 ]; then
			exec /usr/libexec/network/packet-steering.uc -l "$flows" "$1"
		fi
		exec /usr/libexec/network/packet-steering.uc "$1"
		;;
	*) exec /usr/libexec/network/packet-steering.uc 0 ;;
esac
