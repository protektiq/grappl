FROM cgr.dev/chainguard/go:latest AS builder

WORKDIR /src

COPY services/gateway ./services/gateway

WORKDIR /src/services/gateway
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/gateway ./...

FROM cgr.dev/chainguard/static:latest

COPY --from=builder /out/gateway /gateway

USER nonroot:nonroot
ENTRYPOINT ["/gateway"]
