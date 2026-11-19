# tf-api multi-stage image for tfh-local. Build context: apps/tf-api.
# Mirrors tf-api's own build (Makefile `build-go`: cd src && CGO_ENABLED=0 GOOS=linux go build -o ../tf-api .)
# and runtime (.cicd/docker/Dockerfile: debian:bookworm-slim + ca-certificates, binary in /root, port 3000).
# Go version from apps/tf-api/src/go.mod (go 1.24.3). Update both together.
# Build stage uses the daemon network (module downloads OK); the runtime container has no direct internet.

FROM golang:1.24.3-bookworm AS build
ARG TARGETOS=linux
ARG TARGETARCH
WORKDIR /src
COPY src/go.mod src/go.sum ./
# src/vendor/ is committed in tf-api; if present, `go build` uses it and this download is a no-op cache warm.
RUN GOWORK=off go mod download || true
COPY src/ ./
RUN GOWORK=off CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -o /out/tf-api .

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /root
COPY --from=build /out/tf-api .
EXPOSE 3000
CMD ["./tf-api"]
