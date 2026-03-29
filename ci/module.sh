# shellcheck shell=bash
# shellcheck disable=SC2164

stage() {
    local file

    step "Stage modules"

    # flatten modules in kernel out
    shopt -s globstar nullglob
    for file in "$KERNEL_OUT"/modules/**/*.ko; do
        cp -p "$file" "$MODULES_STAGE"
        llvm-strip --strip-debug "$MODULES_STAGE/$(basename "$file")"
    done
    shopt -u globstar nullglob

    success "Modules staged"
}

vendor_boot() {
    local tmp krel src payload mods_dir depmod_root depmod_meta_dir depmod_dir
    local mod
    local -a modules

    step "Package vendor_boot modules"

    tmp="$(mktemp -d)"

    krel="$(make -s -C "$KERNEL" O="$KERNEL_OUT" kernelrelease)"
    src="$KERNEL_OUT/modules/lib/modules/$krel"

    # real package
    payload="$tmp/vendor_boot"
    mods_dir="$payload/lib/modules"

    # fake depmod tree
    depmod_root="$tmp/depmod"
    depmod_meta_dir="$depmod_root/lib/modules/0.0"
    depmod_dir="$depmod_meta_dir/lib/modules" # so depmod sees lib/modules/foo.ko

    mkdir -p "$mods_dir" "$depmod_dir"

    # vendor_boot first, then recovery extras
    mapfile -t modules < <(
        cat "$MODULES_LOAD_VENDOR_BOOT" "$MODULES_LOAD_RECOVERY" | sort -u
    )
    for mod in "${modules[@]}"; do
        cp -p "$MODULES_STAGE/$mod" "$mods_dir/"
        cp -p "$MODULES_STAGE/$mod" "$depmod_dir/"
    done

    cp -p "$MODULES_LOAD_VENDOR_BOOT" "$mods_dir/modules.load"
    cp -p "$MODULES_LOAD_RECOVERY" "$mods_dir/modules.load.recovery"

    # rebuild module metadata
    cp -p "$src"/modules.{order,builtin,builtin.modinfo} "$depmod_meta_dir/"
    depmod -b "$depmod_root" 0.0

    cp -p "$depmod_meta_dir"/modules.{alias,dep,softdep} "$mods_dir/"

    # stock vendor_boot/modules.dep uses /lib/modules paths
    sed -i -e 's|\([^: ]*lib/modules/[^: ]*\)|/\1|g' "$mods_dir/modules.dep"

    # pack the archive for ak3
    tar -C "$payload" -cvpf - lib/ | xz -9e -T0 > "$VENDOR_BOOT_PACKAGE"

    cp -p "$VENDOR_BOOT_PACKAGE" "$AK3/modules/"
    rm -f "$AK3/config/modules.load.recovery"
    rm -rf "$tmp"

    success "vendor_boot modules packaged"
}

vendor_dlkm() {
    local tmp krel src dlkm mods_dir depmod_root depmod_dir
    local file name

    step "Package vendor_dlkm modules"

    tmp="$(mktemp -d)"

    krel="$(make -s -C "$KERNEL" O="$KERNEL_OUT" kernelrelease)"
    src="$KERNEL_OUT/modules/lib/modules/$krel"

    # real package
    dlkm="$tmp/vendor_dlkm"
    mods_dir="$dlkm/lib/modules"

    # fake depmod tree
    depmod_root="$tmp/depmod"
    # stock vendor_dlkm image depmod paths are flat
    depmod_dir="$depmod_root/lib/modules/0.0"

    mkdir -p "$mods_dir" "$depmod_dir"

    # vendor_dlkm gets everything
    shopt -s nullglob
    for file in "$MODULES_STAGE"/*.ko; do
        cp -p "$file" "$mods_dir/"
        cp -p "$file" "$depmod_dir/"
    done
    shopt -u nullglob

    cp -p "$MODULES_LOAD_DLKM" "$mods_dir/modules.load"

    # rebuild module metadata
    cp -p "$src"/modules.{order,builtin,builtin.modinfo} "$depmod_dir/"
    depmod -b "$depmod_root" 0.0

    cp -p "$depmod_dir"/modules.{alias,dep,softdep} "$mods_dir/"

    cat > "$DLKM_FS_CONFIG" << 'EOF'
/ 0 0 0755
/lost+found 0 0 0755
vendor_dlkm 0 0 0755
vendor_dlkm/etc 0 0 0755
vendor_dlkm/etc/NOTICE.xml.gz 0 0 0644
vendor_dlkm/etc/build.prop 0 0 0644
vendor_dlkm/etc/fs_config_dirs 0 0 0644
vendor_dlkm/etc/fs_config_files 0 0 0644
vendor_dlkm/lib 0 0 0755
vendor_dlkm/lib/modules 0 0 0755
EOF

    cat > "$DLKM_FILE_CONTEXTS" << 'EOF'
/ u:object_r:vendor_file:s0
/vendor_dlkm/etc(/.*)? u:object_r:vendor_configs_file:s0
/vendor_dlkm(/.*)? u:object_r:vendor_file:s0
EOF

    # one fs_config line per module
    for file in "$mods_dir"/*; do
        name="$(basename "$file")"
        printf 'vendor_dlkm/lib/modules/%s 0 0 0644\n' "$name" >> "$DLKM_FS_CONFIG"
    done

    # pack the archive for ak3
    tar -C "$dlkm" -cvpf - lib/ | xz -9e -T0 > "$VENDOR_DLKM_PACKAGE"

    cp -p "$VENDOR_DLKM_PACKAGE" "$AK3/modules/"
    rm -rf "$tmp"

    success "vendor_dlkm modules packaged"
}
