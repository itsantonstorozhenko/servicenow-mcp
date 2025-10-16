# Use a Python image with uv pre-installed
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS uv

# Install the project into `/app`
WORKDIR /app

# Enable bytecode compilation
ENV UV_COMPILE_BYTECODE=1

# Copy from the cache instead of linking since it's a mounted volume
ENV UV_LINK_MODE=copy

# Generate proper TOML lockfile first (if not exists)
RUN --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=README.md,target=README.md \
    uv lock

# Install the project's dependencies using the lockfile (without project code)
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    uv sync --frozen --no-install-project --no-dev --no-editable

# Then, add the rest of the project source code and install it
ADD . /app
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    uv sync --frozen --no-dev --no-editable

# --- 2) Build Node layer and install the npm package ------------------------
FROM node:20-bookworm-slim AS nodepkgs
# Install supergateway globally in this stage
RUN npm install -g supergateway

FROM python:3.12-slim-bookworm
COPY --from=uv /usr/local/bin/uv /usr/local/bin/uv
WORKDIR /app

# Create app user for proper ownership
RUN useradd -m app

COPY --from=uv /app/.venv /app/.venv
# Copy source files (excluding .venv to avoid overwriting)
COPY --from=uv /app/*.py /app/
COPY --from=uv /app/pyproject.toml /app/
COPY --from=uv /app/uv.lock /app/
COPY --from=uv /app/README.md /app/
COPY --from=uv /app/LICENSE /app/
COPY --from=uv /app/config /app/config
RUN chown -R app:app /app/.venv

# Safety: ensure PyYAML is available at runtime even if lock/deps missed it
# Bootstrap pip inside the uv-managed venv, then install PyYAML
RUN /app/.venv/bin/python -m ensurepip --upgrade \
    && /app/.venv/bin/python -m pip install --no-cache-dir PyYAML

# Place executables in the environment at the front of the path
ENV PATH="/app/.venv/bin:$PATH"

# Bring in Node, npm, global node_modules, and the bin shims (with symlinks)
COPY --from=nodepkgs /usr/local/bin/ /usr/local/bin/
COPY --from=nodepkgs /usr/local/lib/node_modules/ /usr/local/lib/node_modules/

# Ensure the ServiceNow MCP server finds tool package config inside the container
ENV TOOL_PACKAGE_CONFIG_PATH=/app/config/tool_packages.yaml

# when running the container, add --db-path and a bind mount to the host's db file
ENTRYPOINT ["supergateway", "--stdio", "cd /app && servicenow-mcp"] 
