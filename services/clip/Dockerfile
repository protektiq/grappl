FROM cgr.dev/chainguard/go:latest AS builder

WORKDIR /src

COPY services/clip ./services/clip

WORKDIR /src/services/clip
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/clip ./...

FROM cgr.dev/chainguard/wolfi-base:latest

RUN apk add --no-cache ffmpeg

COPY --from=builder /out/clip /clip

USER nonroot:nonroot
ENTRYPOINT ["/clip"]
