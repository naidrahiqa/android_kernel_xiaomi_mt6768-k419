#!/bin/bash
#
# Kaeru LK Build Script for Mocchipyon Kernel
# This script builds the Kaeru LK and packages it with the kernel
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="$SCRIPT_DIR/.."
KAERU_DIR="${KAERU_DIR:-/home/naidra/Projects/kaeru-src}"
LK_IMAGE="${LK_IMAGE:-/home/naidra/Projects/kaeru/selene-kaeru.bin}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -k, --kaeru-dir DIR    Kaeru source directory (default: $KAERU_DIR)"
    echo "  -l, --lk-image FILE    Pre-built LK image (default: $LK_IMAGE)"
    echo "  -b, --build-kaeru      Build Kaeru LK from source"
    echo "  -h, --help             Show this help"
    exit 1
}

BUILD_KAERU=0

while [ $# -gt 0 ]; do
    case "$1" in
        -k|--kaeru-dir)
            KAERU_DIR="$2"
            shift 2
            ;;
        -l|--lk-image)
            LK_IMAGE="$2"
            shift 2
            ;;
        -b|--build-kaeru)
            BUILD_KAERU=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

echo -e "${GREEN}=== Kaeru LK Build Script ===${NC}"

# Build Kaeru from source if requested
if [ "$BUILD_KAERU" = "1" ]; then
    echo -e "${YELLOW}Building Kaeru from source...${NC}"
    
    if [ ! -d "$KAERU_DIR" ]; then
        echo -e "${RED}Error: Kaeru directory not found: $KAERU_DIR${NC}"
        exit 1
    fi
    
    # Check if we have the stock LK image
    STOCK_LK="${STOCK_LK:-lk_stock.img}"
    if [ ! -f "$STOCK_LK" ]; then
        echo -e "${RED}Error: Stock LK image not found: $STOCK_LK${NC}"
        echo "Please provide STOCK_LK=/path/to/stock/lk.img"
        exit 1
    fi
    
    (
        cd "$KAERU_DIR"
        ./build.sh selene "$STOCK_LK"
        cp selene-kaeru.bin "$KERNEL_DIR/lk_a.img"
    )
    
    echo -e "${GREEN}Kaeru LK built successfully${NC}"
fi

# Check if we have the LK image
if [ ! -f "$LK_IMAGE" ]; then
    echo -e "${RED}Error: LK image not found: $LK_IMAGE${NC}"
    echo "Please provide LK_IMAGE=/path/to/selene-kaeru.bin"
    exit 1
fi

# Copy LK to AnyKernel3 build directory
echo -e "${YELLOW}Copying LK image to AnyKernel3...${NC}"
mkdir -p "$KERNEL_DIR/ak3"
cp "$LK_IMAGE" "$KERNEL_DIR/ak3/lk_a.img"

echo -e "${GREEN}=== Build Complete ===${NC}"
echo "LK image ready for packaging: ak3/lk_a.img"
