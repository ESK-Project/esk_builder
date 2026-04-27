# shellcheck shell=bash
# shellcheck disable=SC2164

flatten() {
    local file

    step "Flatten modules"

    shopt -s globstar nullglob
    for file in "$KERNEL_OUT"/modules/**/*.ko; do
        cp -p "$file" "$MOD_FLAT"
        llvm-strip --strip-debug "$MOD_FLAT/$(basename "$file")"
    done
    shopt -u globstar nullglob

    success "Modules flattened"
}

vendor_boot() {
    local krel src payload mods_dir depmod_root depmod_meta_dir depmod_dir load_vb load_rc mod
    local -a modules

    step "Package vendor_boot modules"

    reset_dir "$MOD_STAGE/vendor_boot"

    load_vb="$MOD_LOAD/modules.load.vendor_boot"
    load_rc="$MOD_LOAD/modules.load.recovery"

    krel="$(make -s -C "$KERNEL" O="$KERNEL_OUT" kernelrelease)"
    src="$KERNEL_OUT/modules/lib/modules/$krel"

    payload="$MOD_STAGE/vendor_boot"
    mods_dir="$payload/lib/modules"

    depmod_root="$MOD_STAGE/depmod_boot"
    depmod_meta_dir="$depmod_root/lib/modules/0.0"
    depmod_dir="$depmod_meta_dir/lib/modules"

    mkdir -p "$mods_dir" "$depmod_dir"

    mapfile -t modules < <(
        cat "$load_vb" "$load_rc" | sort -u
    )
    for mod in "${modules[@]}"; do
        cp -p "$MOD_FLAT/$mod" "$mods_dir/"
        cp -p "$MOD_FLAT/$mod" "$depmod_dir/"
    done

    cp -p "$load_vb" "$mods_dir/modules.load"
    cp -p "$load_rc" "$mods_dir/modules.load.recovery"

    cp -p "$src"/modules.{order,builtin,builtin.modinfo} "$depmod_meta_dir/"
    depmod -b "$depmod_root" 0.0

    cp -p "$depmod_meta_dir"/modules.{alias,dep,softdep} "$mods_dir/"

    sed -i -e 's|\([^: ]*lib/modules/[^: ]*\)|/\1|g' "$mods_dir/modules.dep"

    rm -rf "$depmod_root"

    rm -f "$AK3/config/modules.load.recovery"

    success "vendor_boot modules staged"
}

vendor_dlkm() {
    local krel src dlkm mods_dir depmod_root depmod_dir load_dlkm file name

    step "Package vendor_dlkm modules"

    reset_dir "$MOD_STAGE/vendor_dlkm"

    load_dlkm="$MOD_LOAD/modules.load"

    krel="$(make -s -C "$KERNEL" O="$KERNEL_OUT" kernelrelease)"
    src="$KERNEL_OUT/modules/lib/modules/$krel"

    dlkm="$MOD_STAGE/vendor_dlkm"
    mods_dir="$dlkm/lib/modules"

    depmod_root="$MOD_STAGE/depmod_dlkm"
    depmod_dir="$depmod_root/lib/modules/0.0"

    mkdir -p "$mods_dir" "$depmod_dir"

    shopt -s nullglob
    for file in "$MOD_FLAT"/*.ko; do
        cp -p "$file" "$mods_dir/"
        cp -p "$file" "$depmod_dir/"
    done
    shopt -u nullglob

    cp -p "$load_dlkm" "$mods_dir/modules.load"

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

    for file in "$mods_dir"/*; do
        name="$(basename "$file")"
        printf 'vendor_dlkm/lib/modules/%s 0 0 0644\n' "$name" >> "$DLKM_FS_CONFIG"
    done

    rm -rf "$depmod_root"

    success "vendor_dlkm modules staged"
}

build_module() {
    reset_dir "$MOD_FLAT"
    reset_dir "$MOD_STAGE"
    reset_dir "$AK3/modules"

    flatten
    vendor_boot
    vendor_dlkm

    step "Package modules"
    tar -C "$MOD_STAGE" -cvpf - vendor_dlkm/ vendor_boot/ | xz -9e -T0 > "$MODULE_PACKAGE"
    cp -p "$MODULE_PACKAGE" "$AK3/modules/"

    success "Module package created"
}
