# Dockerfile for h2load Load Generator
FROM alpine:3.18

# Install dependencies
RUN apk add --no-cache \
    nghttp2 \
    bash \
    curl \
    coreutils \
    bc \
    findutils

# Set working directory
WORKDIR /app

# Copy test samples
COPY samples/ ./samples/
COPY scripts/ ./scripts/

# Make scripts executable
RUN chmod +x scripts/*.sh

# Default command
CMD ["/bin/bash"]