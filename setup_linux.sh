#!/bin/bash
# Install Linux dependencies for darwin-vm.
# Run this once before running get_files.sh.
set -euo pipefail

IPSW_VERSION="v0.65.0"  # update as needed: https://github.com/blacktop/ipsw/releases
ARCH="$(uname -m)"

die() { echo "error: $*" >&2; exit 1; }

install_apt_deps() {
    echo "==> Installing apt packages..."
    sudo apt-get update -qq
    sudo apt-get install -y \
        jq \
        hfsprogs \
        python3 \
        kmod \
        git \
        make \
        libplist-dev \
        libssl-dev \
        pkg-config
}

install_ldid() {
    if command -v ldid &>/dev/null; then
        echo "==> ldid already installed"
        return
    fi

    # Try apt first (available on some distros)
    if sudo apt-get install -y ldid 2>/dev/null; then
        echo "==> ldid installed via apt"
        return
    fi

    # Fall back to building from source (ProcursusTeam/ldid)
    echo "==> ldid not in apt — building from source..."
    local TMP_LDID
    TMP_LDID="$(mktemp -d)"
    trap 'rm -rf "${TMP_LDID}"' RETURN

    git clone --depth=1 https://github.com/ProcursusTeam/ldid.git "${TMP_LDID}/ldid"
    make -C "${TMP_LDID}/ldid" -j"$(nproc)"
    sudo install -m755 "${TMP_LDID}/ldid/ldid" /usr/local/bin/ldid
    echo "    installed: $(ldid 2>&1 | head -1 || true)"
}

install_ipsw() {
    if command -v ipsw &>/dev/null; then
        echo "==> ipsw already installed: $(ipsw version 2>/dev/null || true)"
        return
    fi

    echo "==> Installing ipsw ${IPSW_VERSION}..."

    case "${ARCH}" in
        x86_64)  IPSW_ARCH="amd64" ;;
        aarch64) IPSW_ARCH="arm64" ;;
        *) die "unsupported architecture: ${ARCH}" ;;
    esac

    TMP="$(mktemp -d)"
    trap 'rm -rf "${TMP}"' EXIT

    URL="https://github.com/blacktop/ipsw/releases/download/${IPSW_VERSION}/ipsw_${IPSW_VERSION#v}_linux_${IPSW_ARCH}.tar.gz"
    echo "    downloading ${URL}"
    curl -fsSL "${URL}" -o "${TMP}/ipsw.tar.gz"
    tar -xzf "${TMP}/ipsw.tar.gz" -C "${TMP}"
    sudo install -m755 "${TMP}/ipsw" /usr/local/bin/ipsw
    echo "    installed: $(ipsw version)"
}

check_hfsplus_module() {
    echo "==> Checking HFS+ kernel module..."
    if ! grep -q hfsplus /proc/filesystems 2>/dev/null; then
        sudo modprobe hfsplus 2>/dev/null && echo "    hfsplus module loaded" \
            || echo "    warning: could not load hfsplus — mount may fail at runtime"
    else
        echo "    hfsplus already available"
    fi
}

main() {
    echo "darwin-vm Linux dependency installer"
    echo ""
    install_apt_deps
    install_ldid
    install_ipsw
    check_hfsplus_module
    echo ""
    echo "All dependencies installed."
    echo ""
    echo "To use iOS 26.6.1, find the IPSW URL with:"
    echo "  ipsw download ipsw --device iPhone17,3 --version 26.6.1 --url-only"
    echo "Then run:"
    echo "  URL=<url> ./get_files.sh"
}

main "$@"
