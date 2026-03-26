# =============================================================================
# Custom Jupyter Notebook Container for Data Engineering
# =============================================================================
# This Dockerfile demonstrates Docker layer caching best practices:
#   1. Layer ordering: least-changing → most-changing
#   2. Multi-stage builds for smaller final images
#   3. BuildKit cache mounts for faster builds
#   4. Security best practices (non-root user)
# =============================================================================

# -----------------------------------------------------------------------------
# STAGE 1: Builder Stage
# -----------------------------------------------------------------------------
# Purpose: Install and compile dependencies in a separate stage
# This keeps build tools out of the final image, reducing size
# -----------------------------------------------------------------------------
FROM python:3.11-slim AS builder

# Build arguments for flexibility
ARG PYTHON_VERSION=3.11

# Set environment variables for Python
# PYTHONDONTWRITEBYTECODE: Prevents .pyc files (reduces image size)
# PYTHONUNBUFFERED: Ensures logs are output immediately
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# -----------------------------------------------------------------------------
# Layer 1: System Dependencies (RARELY CHANGES)
# -----------------------------------------------------------------------------
# These change infrequently, so they're cached for a long time
# Combining commands with && reduces layers
# Cleaning up in the SAME RUN command keeps the layer small
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build essentials for compiling Python packages
    build-essential \
    gcc \
    g++ \
    # Required for psycopg2
    libpq-dev \
    # Required for some data packages
    libffi-dev \
    # Cleanup in same layer to reduce size
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Create virtual environment in builder stage
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# -----------------------------------------------------------------------------
# Layer 2: Python Dependencies (CHANGES OCCASIONALLY)
# -----------------------------------------------------------------------------
# COPY requirements.txt FIRST, before other source code
# This way, if only your code changes (not dependencies),
# Docker reuses the cached layer with installed packages
# -----------------------------------------------------------------------------
COPY requirements.txt /tmp/requirements.txt

# Install Python packages
# Using BuildKit cache mount (--mount=type=cache) speeds up rebuilds
# by caching pip downloads between builds
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --upgrade pip setuptools wheel && \
    pip install -r /tmp/requirements.txt


# -----------------------------------------------------------------------------
# STAGE 2: Runtime Stage (Final Image)
# -----------------------------------------------------------------------------
# Start fresh from slim image - only copy what we need
# This results in a much smaller final image
# -----------------------------------------------------------------------------
FROM python:3.11-slim AS runtime

# Labels for image metadata (OCI standard)
LABEL maintainer="Data Engineering Team" \
      version="1.0" \
      description="Custom Jupyter Notebook for Data Engineering" \
      org.opencontainers.image.source="https://github.com/your-org/jupyter-de"

# Build arguments
ARG JUPYTER_PORT=8888
ARG NB_USER=jupyter
ARG NB_UID=1000
ARG NB_GID=100

# Environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    # Set virtual environment path
    PATH="/opt/venv/bin:$PATH" \
    # Jupyter configuration
    JUPYTER_PORT=${JUPYTER_PORT} \
    # Home directory for jupyter user
    HOME=/home/${NB_USER}

# -----------------------------------------------------------------------------
# Layer 3: Runtime System Dependencies (RARELY CHANGES)
# -----------------------------------------------------------------------------
# Only install runtime dependencies, not build tools
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Runtime library for PostgreSQL
    libpq5 \
    # Process management
    tini \
    # Useful utilities
    curl \
    procps \
    # Network utilities (ping, etc.)
    iputils-ping \
    # Java runtime - REQUIRED for PySpark
    openjdk-21-jre-headless \
    # Cleanup
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Set JAVA_HOME for PySpark (auto-detect architecture)
ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# -----------------------------------------------------------------------------
# Layer 4: User Setup (RARELY CHANGES)
# -----------------------------------------------------------------------------
# Security: Run as non-root user
# This is a critical security best practice
# -----------------------------------------------------------------------------
RUN useradd -m -s /bin/bash -N -u ${NB_UID} ${NB_USER} && \
    mkdir -p /home/${NB_USER}/notebooks /home/${NB_USER}/.jupyter && \
    chown -R ${NB_UID}:${NB_GID} /home/${NB_USER}

# -----------------------------------------------------------------------------
# Layer 5: Copy Virtual Environment from Builder
# -----------------------------------------------------------------------------
# Copy only the compiled packages, not the build tools
# -----------------------------------------------------------------------------
COPY --from=builder /opt/venv /opt/venv

# -----------------------------------------------------------------------------
# Layer 6: Application Files (CHANGES FREQUENTLY)
# -----------------------------------------------------------------------------
# Copy application files LAST since they change most often
# This maximizes cache utilization for previous layers
# -----------------------------------------------------------------------------
COPY --chown=${NB_UID}:${NB_GID} entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Copy notebooks directory (if any pre-made notebooks)
COPY --chown=${NB_UID}:${NB_GID} notebooks/ /home/${NB_USER}/notebooks/

# -----------------------------------------------------------------------------
# Final Configuration
# -----------------------------------------------------------------------------
# Switch to non-root user
USER ${NB_USER}

# Set working directory
WORKDIR /home/${NB_USER}/notebooks

# Expose Jupyter port
EXPOSE ${JUPYTER_PORT}

# Health check - verifies Jupyter is responding
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:${JUPYTER_PORT}/api/status || exit 1

# Use tini as init system for proper signal handling
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]

# Default command - can be overridden
CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--NotebookApp.token=''"]
