#!/bin/sh

# reF1nd sing-box installer
# Usage: curl -fsSL <your-url>/install.sh | sudo sh -s -- [--version <version>]

set -e

REPO="lurixo/reF1nd-releases"
INSTALL_DIR="/usr/bin"
BINARY_NAME="sing-box"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1" >&2
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1" >&2
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
}

# Parse arguments
download_version=""

while [ $# -gt 0 ]; do
    case "$1" in
        --version)
            shift
            if [ $# -eq 0 ]; then
                log_error "Missing argument for --version"
                echo "Usage: $0 [--version <version>]"
                exit 1
            fi
            download_version="$1"
            shift
            ;;
        -h|--help)
            echo "reF1nd sing-box installer"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --version <version>  Install specific version (e.g., 1.13.0-alpha.27.reF1nd)"
            echo "  -h, --help           Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown argument: $1"
            echo "Usage: $0 [--version <version>]"
            exit 1
            ;;
    esac
done

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Linux*)  echo "linux" ;;
        Darwin*) echo "darwin" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)       echo "unknown" ;;
    esac
}

# Detect architecture
detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)   echo "amd64v3" ;;
        aarch64|arm64)  echo "arm64" ;;
        armv7l)         echo "armv7" ;;
        i386|i686)      echo "386" ;;
        *)              echo "unknown" ;;
    esac
}

# Check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Get latest version from GitHub API
get_latest_version() {
    log_info "Fetching latest version..."
    
    # Try /releases/latest first, then fall back to /releases (for prerelease)
    if [ -n "$GITHUB_TOKEN" ]; then
        latest_release=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
            "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null)
    else
        latest_release=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null)
    fi
    
    # Check if we got a valid response (has tag_name)
    version=$(echo "$latest_release" | grep '"tag_name"' | head -n 1 | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | sed 's/^v//')
    
    # If no version found (prerelease only), try /releases endpoint
    if [ -z "$version" ]; then
        log_info "No stable release found, checking all releases..."
        if [ -n "$GITHUB_TOKEN" ]; then
            latest_release=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
                "https://api.github.com/repos/${REPO}/releases" 2>/dev/null)
        else
            latest_release=$(curl -s "https://api.github.com/repos/${REPO}/releases" 2>/dev/null)
        fi
        version=$(echo "$latest_release" | grep '"tag_name"' | head -n 1 | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | sed 's/^v//')
    fi
    
    if [ -z "$version" ]; then
        log_error "Failed to fetch latest version. API response:"
        echo "$latest_release" | head -20 >&2
        exit 1
    fi
    
    echo "$version"
}

# Download and install binary
install_binary() {
    local version="$1"
    local os="$2"
    local arch="$3"
    
    # Build filename
    local suffix=""
    if [ "$os" = "windows" ]; then
        suffix=".exe"
    fi
    
    local filename="sing-box-${version}-${os}-${arch}${suffix}"
    local download_url="https://github.com/${REPO}/releases/download/v${version}/${filename}"
    
    log_info "Downloading: $download_url"
    
    # Create temp directory
    tmp_dir=$(mktemp -d)
    trap "rm -rf $tmp_dir" EXIT
    
    # Download
    if [ -n "$GITHUB_TOKEN" ]; then
        curl --fail -L -o "${tmp_dir}/${BINARY_NAME}" \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            "$download_url"
    else
        curl --fail -L -o "${tmp_dir}/${BINARY_NAME}" "$download_url"
    fi
    
    if [ $? -ne 0 ]; then
        log_error "Download failed!"
        log_warn "Available architectures may be limited. Check: https://github.com/${REPO}/releases"
        exit 1
    fi
    
    # Install
    log_info "Installing to ${INSTALL_DIR}/${BINARY_NAME}..."
    
    # Backup existing binary if exists
    if [ -f "${INSTALL_DIR}/${BINARY_NAME}" ]; then
        log_warn "Existing installation found, backing up..."
        mv "${INSTALL_DIR}/${BINARY_NAME}" "${INSTALL_DIR}/${BINARY_NAME}.bak"
    fi
    
    # Move and set permissions
    mv "${tmp_dir}/${BINARY_NAME}" "${INSTALL_DIR}/${BINARY_NAME}"
    chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
    
    log_info "Installation complete!"
}

# Create systemd service (optional)
create_systemd_service() {
    if [ ! -d "/etc/systemd/system" ]; then
        return
    fi
    
    if [ -f "/etc/systemd/system/sing-box.service" ]; then
        log_warn "systemd service already exists, skipping..."
        return
    fi
    
    log_info "Creating systemd service..."
    
    cat > /etc/systemd/system/sing-box.service << 'EOF'
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network-online.target nss-lookup.target
Wants=network-online.target
StartLimitIntervalSec=600
StartLimitBurst=5

[Service]
StateDirectory=sing-box
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
ExecStart=/usr/bin/sing-box -D /var/lib/sing-box -C /etc/sing-box run
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=10s
RestartPreventExitStatus=23
LimitNOFILE=infinity
LimitNPROC=infinity
TasksMax=infinity
LimitCORE=0
Nice=-10

[Install]
WantedBy=multi-user.target
EOF

    # Create config directory
    mkdir -p /etc/sing-box
    mkdir -p /var/lib/sing-box
    
    systemctl daemon-reload 2>/dev/null || true
    log_info "systemd service created. Enable with: systemctl enable sing-box"
}

# Verify installation
verify_installation() {
    if command -v sing-box >/dev/null 2>&1; then
        log_info "Verification:"
        sing-box version
    else
        log_warn "sing-box not found in PATH. You may need to add ${INSTALL_DIR} to your PATH."
    fi
}

# Main
main() {
    echo "========================================"
    echo "  reF1nd sing-box Installer"
    echo "========================================"
    echo ""
    
    check_root
    
    os=$(detect_os)
    arch=$(detect_arch)
    
    log_info "Detected OS: $os"
    log_info "Detected Arch: $arch"
    
    if [ "$os" = "unknown" ] || [ "$arch" = "unknown" ]; then
        log_error "Unsupported platform: ${os}-${arch}"
        exit 1
    fi
    
    # Get version
    if [ -z "$download_version" ]; then
        download_version=$(get_latest_version)
    fi
    
    log_info "Version to install: $download_version"
    echo ""
    
    install_binary "$download_version" "$os" "$arch"
    create_systemd_service
    verify_installation
    
    echo ""
    log_info "Done! Run 'sing-box version' to verify."
}

main
