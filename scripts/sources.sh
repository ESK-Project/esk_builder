# shellcheck shell=bash
# shellcheck disable=SC2164,SC2153,SC2034

fetch_sources() {
    step "Fetch sources"
    KERNEL_COMMIT="$(py_cli source sync "$KERNEL_URL" "$KERNEL_REF" "$KERNEL")" || return $?
    export KERNEL_COMMIT
    py_cli source sync "$AK3_URL" "$AK3_REF" "$AK3" > /dev/null
}
