# Custom Jupyter Notebook for Data Engineering

A Docker setup for Jupyter Lab with Data Engineering tools, demonstrating Docker layer caching best practices.

## Quick Start

```bash
# Build the image
docker build -t jupyter-de:latest .

# Run with Docker Compose
docker compose up -d

# Access Jupyter at http://localhost:8888
```

## Docker Layer Caching Explained

### Why Layer Order Matters

Docker builds images in layers. Each instruction in a Dockerfile creates a layer. When you rebuild, Docker reuses cached layers if nothing changed.

**Cache invalidation rule**: If a layer changes, all subsequent layers must be rebuilt.

### Optimal Layer Order (used in this Dockerfile)

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 1: Base Image (python:3.11-slim)     [RARELY CHANGES] │
├─────────────────────────────────────────────────────────────┤
│ Layer 2: System Dependencies (apt-get)     [RARELY CHANGES] │
├─────────────────────────────────────────────────────────────┤
│ Layer 3: Python Dependencies (pip install) [OCCASIONALLY]   │
├─────────────────────────────────────────────────────────────┤
│ Layer 4: User Configuration                [RARELY CHANGES] │
├─────────────────────────────────────────────────────────────┤
│ Layer 5: Application Code & Notebooks      [FREQUENTLY]     │
└─────────────────────────────────────────────────────────────┘
                          ▲
                          │
              Most frequently changing
              layers go at the BOTTOM
```

### Key Caching Techniques in This Dockerfile

#### 1. Copy requirements.txt Before Code
```dockerfile
# GOOD: requirements.txt copied separately
COPY requirements.txt /tmp/requirements.txt
RUN pip install -r /tmp/requirements.txt
COPY . /app  # Code changes don't invalidate pip cache

# BAD: Copying everything first
COPY . /app
RUN pip install -r /app/requirements.txt  # Any code change rebuilds pip
```

#### 2. Multi-Stage Builds
```dockerfile
# Stage 1: Builder (includes gcc, build tools)
FROM python:3.11-slim AS builder
RUN apt-get install build-essential gcc
RUN pip install packages

# Stage 2: Runtime (no build tools = smaller image)
FROM python:3.11-slim AS runtime
COPY --from=builder /opt/venv /opt/venv
```

**Result**: Final image is ~500MB smaller without build tools.

#### 3. Combine RUN Commands
```dockerfile
# GOOD: Single layer, cleanup included
RUN apt-get update && apt-get install -y \
    package1 \
    package2 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# BAD: Multiple layers, cleanup doesn't reduce size
RUN apt-get update
RUN apt-get install -y package1
RUN apt-get install -y package2
RUN apt-get clean  # Doesn't help - previous layers still large
```

#### 4. BuildKit Cache Mounts
```dockerfile
# Caches pip downloads between builds
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt
```

## Build Commands

### Standard Build
```bash
docker build -t jupyter-de:latest .
```

### Build with BuildKit (recommended)
```bash
DOCKER_BUILDKIT=1 docker build -t jupyter-de:latest .
```

### Build without Cache
```bash
docker build --no-cache -t jupyter-de:latest .
```

### Build with Custom Arguments
```bash
docker build \
  --build-arg JUPYTER_PORT=9999 \
  --build-arg NB_USER=datascientist \
  -t jupyter-de:custom .
```

## Docker Compose Commands

```bash
# Start Jupyter only
docker compose up -d

# Start with PostgreSQL database
docker compose --profile with-db up -d

# View logs
docker compose logs -f jupyter

# Rebuild after changes
docker compose up -d --build

# Stop and remove
docker compose down

# Stop and remove including volumes
docker compose down -v
```

## Verifying Cache Usage

When you rebuild, look for "CACHED" in the output:

```
 => CACHED [builder 2/5] RUN apt-get update ...
 => CACHED [builder 3/5] RUN python -m venv /opt/venv
 => CACHED [builder 4/5] COPY requirements.txt ...
 => CACHED [builder 5/5] RUN pip install ...
 => [runtime 6/7] COPY entrypoint.sh ...    # Only this rebuilds
```

## File Structure

```
jupyter-test/
├── Dockerfile           # Multi-stage Dockerfile with caching
├── docker-compose.yml   # Container orchestration
├── requirements.txt     # Python dependencies
├── .dockerignore        # Files excluded from build
├── .env.example         # Environment template
├── entrypoint.sh        # Container startup script
├── README.md            # This file
└── notebooks/           # Your Jupyter notebooks
```

## Customization

### Adding Python Packages
1. Edit `requirements.txt`
2. Rebuild: `docker compose up -d --build`

### Changing Jupyter Port
1. Edit `docker-compose.yml` ports section
2. Restart: `docker compose restart`

### Adding System Packages
1. Add to the `apt-get install` section in Dockerfile
2. Rebuild with `--no-cache` to ensure fresh install

## Security Notes

- Container runs as non-root user (`jupyter`)
- No token authentication by default (add `JUPYTER_TOKEN` for production)
- Health checks enabled for monitoring
- Resource limits configured in docker-compose.yml

## Troubleshooting

### Check Container Status
```bash
docker compose ps
docker compose logs jupyter
```

### Access Container Shell
```bash
docker compose exec jupyter bash
```

### Check Installed Packages
```bash
docker compose exec jupyter pip list
```

### Disk Space Issues
```bash
# Remove dangling images
docker image prune

# Full cleanup
docker system prune -a
```
