# Multi-stage Dockerfile for building Envoy from source - Kaniko compatible
# This Dockerfile builds Envoy exactly like the CI does: ./ci/do_ci.sh release.server_only
#
# Build with:
#   docker build -f Dockerfile.local -t my-envoy:latest .
#   OR with Kaniko:
#   executor --dockerfile=Dockerfile.local --context=. --destination=my-envoy:latest
#
# No additional scripts needed - this is a complete self-contained build.

# Build arguments for the build image
# Using the tag from .github/config.yml instead of SHA for better compatibility
ARG BUILD_IMAGE_TAG=86873047235e9b8232df989a5999b9bebf9db69c
ARG BUILD_IMAGE_REPO=docker.io/envoyproxy/envoy-build-ubuntu


# STAGE 1: Build Envoy from source
FROM ${BUILD_IMAGE_REPO}:${BUILD_IMAGE_TAG} AS envoy-builder

# Set working directory
WORKDIR /source

# Copy bazelrc files first to ensure they're available
COPY .bazelrc .bazelversion MODULE.bazel WORKSPACE ./
COPY bazel/ bazel/

# Copy the rest of the source code
COPY . .

# Remove user.bazelrc if present (contains macOS-specific flags incompatible with Linux builds)
RUN rm -f user.bazelrc

# Run fix-bazel-truststore if it exists (needed for some environments)
RUN if [ -x /tmp/fix-bazel-truststore.sh ]; then /tmp/fix-bazel-truststore.sh; fi || true

# Build Envoy with release configuration
# This matches what ci/do_ci.sh does for release.server_only:
# - Uses --config=clang (Clang with libc++)
# - Uses -c opt (optimized build)
# - Uses --stripopt=--strip-all (strip symbols)
# - Uses --workspace_status_command to avoid git dependency
# - Limits resources for Docker environment to prevent OOM
RUN cd /source && \
    bazel build \
    --config=clang \
    -c opt \
    --stripopt=--strip-all \
    --workspace_status_command=/usr/bin/true \
    --jobs=1 \
    --local_ram_resources=4096 \
    --local_cpu_resources=1 \
    //source/exe:envoy-static

# Extract the built binary
RUN cp -a bazel-bin/source/exe/envoy-static /tmp/envoy


# STAGE 2: Create minimal runtime image
FROM ubuntu:22.04

# Install runtime dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        libc++1 \
        tzdata \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create envoy user
RUN groupadd -r envoy && useradd -r -g envoy envoy

# Create config directory
RUN mkdir -p /etc/envoy && chown envoy:envoy /etc/envoy

# Copy the built Envoy binary from builder stage
COPY --from=envoy-builder --chown=0:0 --chmod=755 /tmp/envoy /usr/local/bin/envoy

# Make binary executable
RUN chmod 755 /usr/local/bin/envoy

# Optional: Copy a default config
# COPY configs/envoyproxy_io_proxy.yaml /etc/envoy/envoy.yaml

# Expose default Envoy port
EXPOSE 10000

# Run as envoy user
USER envoy

# Default command
ENTRYPOINT ["/usr/local/bin/envoy"]
CMD ["-c", "/etc/envoy/envoy.yaml"]
