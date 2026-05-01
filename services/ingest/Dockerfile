FROM cgr.dev/chainguard/go:latest AS builder

WORKDIR /src

COPY services/ingest ./services/ingest
COPY services/shared ./services/shared

WORKDIR /src/services/ingest
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/ingest ./...

FROM cgr.dev/chainguard/static:latest

COPY --from=builder /out/ingest /ingest

USER nonroot:nonroot
ENTRYPOINT ["/ingest"]
