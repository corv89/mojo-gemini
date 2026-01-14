#!/bin/bash
# Build script for mojo-gemini (depends on mojo-tls)
#
# Environment variables (auto-detected if not set):
#   MOJO_TLS_PATH    - Path to mojo-tls source directory
#   MBEDTLS_LIB      - Path to mbedTLS library directory
#   MOJO_BIN         - Path to mojo compiler
#   MOJO_RUNTIME_LIB - Path to Mojo runtime libraries
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- Auto-detect paths ---

# MOJO_TLS_PATH: Check env, then sibling directory, then parent directory
if [ -z "$MOJO_TLS_PATH" ]; then
    if [ -d "$SCRIPT_DIR/../mojo-tls" ]; then
        MOJO_TLS_PATH="$SCRIPT_DIR/../mojo-tls"
    elif [ -d "$SCRIPT_DIR/mojo-tls" ]; then
        MOJO_TLS_PATH="$SCRIPT_DIR/mojo-tls"
    fi
fi

# MBEDTLS_LIB: Check env, then common locations
if [ -z "$MBEDTLS_LIB" ]; then
    if [ -d "/opt/homebrew/opt/mbedtls/lib" ]; then
        MBEDTLS_LIB="/opt/homebrew/opt/mbedtls/lib"
    elif [ -d "/usr/local/opt/mbedtls/lib" ]; then
        MBEDTLS_LIB="/usr/local/opt/mbedtls/lib"
    elif [ -d "/usr/lib/x86_64-linux-gnu" ] && [ -f "/usr/lib/x86_64-linux-gnu/libmbedtls.a" ]; then
        MBEDTLS_LIB="/usr/lib/x86_64-linux-gnu"
    elif [ -d "/usr/lib" ] && [ -f "/usr/lib/libmbedtls.a" ]; then
        MBEDTLS_LIB="/usr/lib"
    fi
fi

# MOJO_BIN: Check env, then PATH, then common locations
if [ -z "$MOJO_BIN" ]; then
    if command -v mojo &> /dev/null; then
        MOJO_BIN="$(command -v mojo)"
    elif [ -f "$HOME/.modular/bin/mojo" ]; then
        MOJO_BIN="$HOME/.modular/bin/mojo"
    # Check for .venv in parent directory (common dev setup)
    elif [ -f "$SCRIPT_DIR/../.venv/bin/mojo" ]; then
        MOJO_BIN="$SCRIPT_DIR/../.venv/bin/mojo"
    elif [ -f "$SCRIPT_DIR/.venv/bin/mojo" ]; then
        MOJO_BIN="$SCRIPT_DIR/.venv/bin/mojo"
    fi
fi

# MOJO_RUNTIME_LIB: Check env, then derive from MOJO_BIN location
if [ -z "$MOJO_RUNTIME_LIB" ]; then
    if [ -n "$MOJO_BIN" ]; then
        # Try to find runtime lib relative to mojo binary
        MOJO_DIR="$(dirname "$(dirname "$MOJO_BIN")")"
        if [ -d "$MOJO_DIR/lib/python3.12/site-packages/modular/lib" ]; then
            MOJO_RUNTIME_LIB="$MOJO_DIR/lib/python3.12/site-packages/modular/lib"
        elif [ -d "$MOJO_DIR/lib" ] && [ -f "$MOJO_DIR/lib/libKGENCompilerRTShared.dylib" ]; then
            MOJO_RUNTIME_LIB="$MOJO_DIR/lib"
        fi
    fi
    # Try pixi/magic environment
    if [ -z "$MOJO_RUNTIME_LIB" ] && [ -n "$CONDA_PREFIX" ]; then
        if [ -d "$CONDA_PREFIX/lib" ]; then
            MOJO_RUNTIME_LIB="$CONDA_PREFIX/lib"
        fi
    fi
fi

# --- Validate paths ---

SHIM_LIB="$MOJO_TLS_PATH/shim/libmojo_tls_shim.a"

if [ -z "$MOJO_TLS_PATH" ] || [ ! -d "$MOJO_TLS_PATH" ]; then
    echo "Error: mojo-tls not found"
    echo "Set MOJO_TLS_PATH environment variable or place mojo-tls as sibling directory"
    exit 1
fi

if [ ! -f "$SHIM_LIB" ]; then
    echo "Error: mojo-tls shim not found at $SHIM_LIB"
    echo "Please build mojo-tls first: cd $MOJO_TLS_PATH && ./build.sh"
    exit 1
fi

if [ -z "$MBEDTLS_LIB" ] || [ ! -d "$MBEDTLS_LIB" ]; then
    echo "Error: mbedTLS libraries not found"
    echo "Install with: brew install mbedtls (macOS) or apt install libmbedtls-dev (Linux)"
    echo "Or set MBEDTLS_LIB environment variable"
    exit 1
fi

if [ -z "$MOJO_BIN" ] || [ ! -f "$MOJO_BIN" ]; then
    echo "Error: mojo compiler not found"
    echo "Install Mojo or set MOJO_BIN environment variable"
    exit 1
fi

if [ -z "$MOJO_RUNTIME_LIB" ] || [ ! -d "$MOJO_RUNTIME_LIB" ]; then
    echo "Error: Mojo runtime libraries not found"
    echo "Set MOJO_RUNTIME_LIB environment variable"
    exit 1
fi

# Parse arguments
DEBUG_FLAG=""
VERBOSE=""
POSITIONAL_ARGS=()

for arg in "$@"; do
    case $arg in
        --debug)
            DEBUG_FLAG="-DMOJO_TLS_DEBUG"
            ;;
        -v|--verbose)
            VERBOSE=1
            ;;
        *)
            POSITIONAL_ARGS+=("$arg")
            ;;
    esac
done

set -- "${POSITIONAL_ARGS[@]}"

# Show detected paths (useful for debugging)
if [ -n "$VERBOSE" ]; then
    echo "Detected paths:"
    echo "  MOJO_TLS_PATH:    $MOJO_TLS_PATH"
    echo "  MBEDTLS_LIB:      $MBEDTLS_LIB"
    echo "  MOJO_BIN:         $MOJO_BIN"
    echo "  MOJO_RUNTIME_LIB: $MOJO_RUNTIME_LIB"
    echo
fi

# Default input/output
INPUT_FILE="${1:-examples/simple_client.mojo}"
OUTPUT_FILE="${2:-$(basename "${INPUT_FILE%.mojo}")}"

echo "=== Building mojo-gemini ==="
echo "Input:  $INPUT_FILE"
echo "Output: $OUTPUT_FILE"
echo

# Step 1: Compile Mojo to object file
echo "[1/2] Compiling Mojo to object file..."
OBJ_FILE="${OUTPUT_FILE}.o"
"$MOJO_BIN" build --emit object "$INPUT_FILE" -o "$OBJ_FILE" \
    -I "$SCRIPT_DIR" \
    -I "$MOJO_TLS_PATH"
echo "      Created $OBJ_FILE"

# Step 2: Link everything together
echo "[2/2] Linking..."
clang "$OBJ_FILE" \
    "$SHIM_LIB" \
    ${MBEDTLS_LIB}/libmbedtls.a \
    ${MBEDTLS_LIB}/libmbedx509.a \
    ${MBEDTLS_LIB}/libmbedcrypto.a \
    ${MBEDTLS_LIB}/libtfpsacrypto.a \
    -L${MOJO_RUNTIME_LIB} \
    -lKGENCompilerRTShared -lAsyncRTMojoBindings -lAsyncRTRuntimeGlobals \
    -o "$OUTPUT_FILE"

# Cleanup object file
rm -f "$OBJ_FILE"

echo
echo "=== Build complete ==="
echo "Binary: $OUTPUT_FILE"
echo
echo "Run with:"
echo "  DYLD_LIBRARY_PATH=${MOJO_RUNTIME_LIB} ./$OUTPUT_FILE"
