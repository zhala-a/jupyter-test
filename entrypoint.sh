#!/bin/bash
# =============================================================================
# Entrypoint Script for Jupyter Data Engineering Container
# =============================================================================
# This script runs when the container starts
# It handles environment setup and graceful shutdown
# =============================================================================

set -e  # Exit on any error

# -----------------------------------------------------------------------------
# Signal Handling for Graceful Shutdown
# -----------------------------------------------------------------------------
# Trap SIGTERM and SIGINT for graceful shutdown
shutdown() {
    echo "[entrypoint] Received shutdown signal, stopping Jupyter..."
    # Give Jupyter time to save and cleanup
    kill -TERM "$JUPYTER_PID" 2>/dev/null
    wait "$JUPYTER_PID"
    echo "[entrypoint] Jupyter stopped gracefully"
    exit 0
}

trap shutdown SIGTERM SIGINT

# -----------------------------------------------------------------------------
# Environment Setup
# -----------------------------------------------------------------------------
echo "[entrypoint] Starting Jupyter Data Engineering Container"
echo "[entrypoint] User: $(whoami)"
echo "[entrypoint] Working directory: $(pwd)"
echo "[entrypoint] Python version: $(python --version)"

# Print installed package versions for debugging
echo "[entrypoint] Key packages:"
echo "  - JupyterLab: $(pip show jupyterlab 2>/dev/null | grep Version | cut -d' ' -f2)"
echo "  - Pandas: $(pip show pandas 2>/dev/null | grep Version | cut -d' ' -f2)"
echo "  - PySpark: $(pip show pyspark 2>/dev/null | grep Version | cut -d' ' -f2)"

# -----------------------------------------------------------------------------
# Jupyter Configuration
# -----------------------------------------------------------------------------
# Generate Jupyter config if it doesn't exist
if [ ! -f "$HOME/.jupyter/jupyter_lab_config.py" ]; then
    echo "[entrypoint] Generating Jupyter configuration..."
    jupyter lab --generate-config 2>/dev/null || true
fi

# -----------------------------------------------------------------------------
# Directory Permissions
# -----------------------------------------------------------------------------
# Ensure notebooks directory is writable
if [ ! -w "$HOME/notebooks" ]; then
    echo "[entrypoint] Warning: notebooks directory is not writable"
fi

# -----------------------------------------------------------------------------
# Start Jupyter
# -----------------------------------------------------------------------------
echo "[entrypoint] Starting Jupyter Lab on port ${JUPYTER_PORT:-8888}..."
echo "[entrypoint] Command: $@"
echo "============================================================================="

# Execute the command (passed from Dockerfile CMD or docker run)
exec "$@" &
JUPYTER_PID=$!

# Wait for the Jupyter process
wait "$JUPYTER_PID"
