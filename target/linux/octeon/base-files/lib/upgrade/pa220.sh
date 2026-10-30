# SPDX-License-Identifier: GPL-2.0-only
# PA-220 layout: 256 MiB ext3 boot partition, remaining eMMC as ext4 root.

PA220_DISK=/dev/mmcblk0
PA220_BOOTDEV=/dev/mmcblk0p1
PA220_ROOTDEV=/dev/mmcblk0p2
PA220_BOOT_START=2048
PA220_BOOT_SIZE=524288
PA220_ROOT_START=526336

if [ "$(board_name)" = "pan,pa-220" ]; then
	RAMFS_COPY_BIN="$RAMFS_COPY_BIN cmp head resize2fs sha256sum"
fi

pa220_check_layout() {
	[ -b "$PA220_BOOTDEV" ] && [ -b "$PA220_ROOTDEV" ] &&
		[ ! -b "${PA220_DISK}p3" ] &&
		[ "$(cat /sys/class/block/mmcblk0p1/start)" = "$PA220_BOOT_START" ] &&
		[ "$(cat /sys/class/block/mmcblk0p1/size)" = "$PA220_BOOT_SIZE" ] &&
		[ "$(cat /sys/class/block/mmcblk0p2/start)" = "$PA220_ROOT_START" ]
}

pa220_check_image() {
	local image="$1"
	local dir=sysupgrade-pan_pa-220
	local magic

	tar tf "$image" >/dev/null 2>&1 || return 1
	magic=$(tar xf "$image" "$dir/kernel" -O 2>/dev/null |
		head -c 4 | hexdump -v -e '1/1 "%02x"')
	[ "$magic" = 7f454c46 ] || {
		echo "The PA-220 image must contain an ELF kernel."
		return 1
	}
	magic=$(tar xf "$image" "$dir/root" -O 2>/dev/null |
		dd bs=1 skip=1080 count=2 2>/dev/null | hexdump -v -e '1/1 "%02x"')
	[ "$magic" = 53ef ] || {
		echo "Use the PA-220 ext4-sysupgrade.tar image."
		return 1
	}
}

pa220_unpack_image() {
	local image="$1"
	local work="$2"
	local dir=sysupgrade-pan_pa-220

	pa220_check_image "$image" || return 1
	mkdir -p "$work" || return 1
	tar xf "$image" "$dir/kernel" -O > "$work/kernel" || return 1
	tar xf "$image" "$dir/root" -O > "$work/root.img" || return 1
	[ -s "$work/kernel" ] && [ -s "$work/root.img" ] || return 1
	[ "$(wc -c < "$work/kernel")" -lt $((PA220_BOOT_SIZE * 512 - 1048576)) ] || return 1
	[ "$(wc -c < "$work/root.img")" -le $(($(cat /sys/class/block/mmcblk0p2/size) * 512)) ] || return 1
}

pa220_write_image() {
	local work="$1"
	local boot="$work/boot"
	local bytes expected actual

	pa220_check_layout || return 1
	grep -q "^$PA220_DISK" /proc/mounts && {
		echo "An eMMC partition is still mounted; refusing to write."
		return 1
	}
	bytes=$(wc -c < "$work/root.img")
	expected=$(sha256sum "$work/root.img")
	expected=${expected%% *}
	echo "Writing and verifying the ext4 root filesystem."
	dd if="$work/root.img" of="$PA220_ROOTDEV" bs=1M || return 1
	sync
	actual=$(head -c "$bytes" "$PA220_ROOTDEV" | sha256sum)
	[ "${actual%% *}" = "$expected" ] || {
		echo "Root filesystem readback did not match. Boot the RAM image for recovery."
		return 1
	}
	resize2fs -f "$PA220_ROOTDEV" || return 1

	mkdir -p "$boot" || return 1
	mount -t ext3 "$PA220_BOOTDEV" "$boot" || return 1
	cp "$work/kernel" "$boot/vmlinux.oct3-mp.new" && sync &&
		cmp -s "$work/kernel" "$boot/vmlinux.oct3-mp.new" || {
		rm -f "$boot/vmlinux.oct3-mp.new"
		umount "$boot"
		return 1
	}
	if [ -f "$boot/vmlinux.oct3-mp" ]; then
		mv "$boot/vmlinux.oct3-mp" "$boot/vmlinux.oct3-mp.bak" || {
			umount "$boot"
			return 1
		}
	fi
	mv "$boot/vmlinux.oct3-mp.new" "$boot/vmlinux.oct3-mp" || {
		umount "$boot"
		return 1
	}
	sync
	umount "$boot"
}

pa220_do_upgrade() {
	local work=/tmp/pa220-upgrade

	pa220_check_layout || return 1
	pa220_unpack_image "$1" "$work" || return 1
	pa220_write_image "$work"
}

pa220_copy_config() {
	mkdir -p /boot || return 1
	mount -t ext3 "$PA220_BOOTDEV" /boot || return 1
	cp -af "$UPGRADE_BACKUP" "/boot/$BACKUP_FILE" || {
		umount /boot
		return 1
	}
	sync
	umount /boot
}
