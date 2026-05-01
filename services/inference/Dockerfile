FROM cgr.dev/chainguard/go:latest AS builder

WORKDIR /src

COPY services/inference ./services/inference

WORKDIR /src/services/inference
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/inference ./...

FROM cgr.dev/chainguard/static:latest

COPY --from=builder /out/inference /inference

USER nonroot:nonroot
ENTRYPOINT ["/inference"]
