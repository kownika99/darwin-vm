#!/bin/bash
set -euo pipefail

is_linux() {
    [[ "$(uname)" == "Linux" ]]
}

fixup_perms_darwin() {
    local ramdisk="${1}"
    local livemount

    livemount="$(mktemp -d)"

    if [[ -z "${livemount}" || ! -d "${livemount}" ]]; then
        echo "something's wrong with the livemount, stopping here"
        exit 1
    fi

    if ! hdiutil attach -owners on -mountpoint "${livemount}" "${ramdisk}"; then
        echo "mount failed"
        rmdir "${livemount}"
        exit 1
    fi

    echo "mounted ${ramdisk} on ${livemount}"
    trap 'hdiutil detach ${livemount}; rmdir ${livemount}' EXIT

    echo "This will run: sudo chown -R root:wheel ${livemount}/bin ${livemount}/System ${livemount}/libexec"
    read -r -p "Are you sure? (y/n) " response
    echo "${response}"

    case "${response}" in
        [Yy])
            sudo chown -R root:wheel "${livemount}/bin" "${livemount}/System"
            if [[ -d "${livemount}/libexec" ]]; then
                sudo chown -R root:wheel "${livemount}/libexec"
            fi
            echo "done!"
            ;;
        *)
            echo "skipping permission fixes"
            ;;
    esac
}

fixup_perms_linux() {
    local ramdisk="${1}"
    local livemount loopdev

    livemount="$(mktemp -d)"

    if [[ -z "${livemount}" || ! -d "${livemount}" ]]; then
        echo "something's wrong with the livemount, stopping here"
        exit 1
    fi

    loopdev="$(sudo losetup -f --show "${ramdisk}")"

    if ! sudo mount -t hfsplus -o rw,force "${loopdev}" "${livemount}"; then
        echo "mount failed — install hfsprogs: apt install hfsprogs"
        sudo losetup -d "${loopdev}" 2>/dev/null || true
        rmdir "${livemount}"
        exit 1
    fi

    echo "mounted ${ramdisk} on ${livemount}"
    trap 'sudo umount "${livemount}" 2>/dev/null || true; sudo losetup -d "${loopdev}" 2>/dev/null || true; rmdir "${livemount}" 2>/dev/null || true' EXIT

    # Linux HFS+ uses root:root — 'wheel' group may not exist
    echo "This will run: sudo chown -R root:root ${livemount}/bin ${livemount}/System ${livemount}/libexec"
    read -r -p "Are you sure? (y/n) " response
    echo "${response}"

    case "${response}" in
        [Yy])
            sudo chown -R root:root "${livemount}/bin" "${livemount}/System"
            if [[ -d "${livemount}/libexec" ]]; then
                sudo chown -R root:root "${livemount}/libexec"
            fi
            echo "done!"
            ;;
        *)
            echo "skipping permission fixes"
            ;;
    esac
}

main() {
    if [[ -z "${1:-}" ]]; then
        echo "usage: fix_perms.sh [ramdisk.dmg]"
        exit 1
    fi

    if is_linux; then
        fixup_perms_linux "${1}"
    elif [[ "$(uname)" == "Darwin" ]]; then
        fixup_perms_darwin "${1}"
    else
        echo "unsupported platform: $(uname)"
        exit 1
    fi
}

main "$@"
