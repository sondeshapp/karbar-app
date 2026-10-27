FROM golang:1.24-alpine AS build

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/karbar-api ./cmd/api

FROM alpine:3.21
RUN apk add --no-cache ca-certificates wget \
    && addgroup -S karbar \
    && adduser -S -D -H -G karbar karbar
COPY --from=build /out/karbar-api /usr/local/bin/karbar-api
USER karbar
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/v1/healthz || exit 1
ENTRYPOINT ["/usr/local/bin/karbar-api"]
