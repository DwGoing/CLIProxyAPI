FROM golang:1.26-bookworm AS builder

WORKDIR /app

ARG GOPROXY=https://goproxy.cn,https://proxy.golang.org,direct
ENV GOPROXY=${GOPROXY}
ARG BUILD_VERBOSE=0

RUN apt-get update && apt-get install -y --no-install-recommends build-essential git && rm -rf /var/lib/apt/lists/*

COPY go.mod go.sum ./

RUN --mount=type=cache,id=cliproxyapi-go-mod,target=/go/pkg/mod,sharing=shared \
    --mount=type=cache,id=cliproxyapi-go-build,target=/root/.cache/go-build,sharing=shared \
    echo "[cliproxy-build] go mod download start $(date -u +%Y-%m-%dT%H:%M:%SZ)" && \
    if [ "${BUILD_VERBOSE}" = "1" ]; then \
      echo "[cliproxy-build] WARNING: BUILD_VERBOSE=1 is not a secret filter; do not share these logs if they may contain credentials or private module paths"; \
      go env GOPROXY GOSUMDB GOPATH GOMODCACHE; \
    fi && \
    go mod download && \
    echo "[cliproxy-build] go mod download done $(date -u +%Y-%m-%dT%H:%M:%SZ)"

COPY . .

ARG VERSION=dev
ARG COMMIT=none
ARG BUILD_DATE=unknown

RUN --mount=type=cache,id=cliproxyapi-go-mod,target=/go/pkg/mod,sharing=shared \
    --mount=type=cache,id=cliproxyapi-go-build,target=/root/.cache/go-build,sharing=shared \
    echo "[cliproxy-build] go build start $(date -u +%Y-%m-%dT%H:%M:%SZ)" && \
    CGO_ENABLED=1 GOOS=linux go build -buildvcs=false -ldflags="-s -w -X 'main.Version=${VERSION}' -X 'main.Commit=${COMMIT}' -X 'main.BuildDate=${BUILD_DATE}'" -o ./CLIProxyAPI ./cmd/server/ && \
    echo "[cliproxy-build] go build done $(date -u +%Y-%m-%dT%H:%M:%SZ)"

FROM debian:bookworm

RUN apt-get update && apt-get install -y --no-install-recommends tzdata ca-certificates && rm -rf /var/lib/apt/lists/*

RUN mkdir /CLIProxyAPI

COPY --from=builder ./app/CLIProxyAPI /CLIProxyAPI/CLIProxyAPI

COPY config.example.yaml /CLIProxyAPI/config.example.yaml

WORKDIR /CLIProxyAPI

EXPOSE 8317

ENV TZ=Asia/Shanghai

RUN cp /usr/share/zoneinfo/${TZ} /etc/localtime && echo "${TZ}" > /etc/timezone

CMD ["./CLIProxyAPI"]
