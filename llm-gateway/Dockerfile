# Build context must be the repo root so we can COPY prolog-engine/queries/.
# In docker-compose: context: . / dockerfile: llm-gateway/Dockerfile

# Stage 1: build the gateway binary
FROM golang:1.23-alpine AS builder
WORKDIR /build
COPY llm-gateway/ .
RUN go build -o /gateway ./cmd/gateway

# Stage 2: minimal runtime — no Go toolchain
FROM alpine:3.20
WORKDIR /app
COPY --from=builder /gateway ./gateway
# Query files are read at startup to build the LLM system prompt.
# prolog-engine/queries/ is the single source of truth; we copy it here
# so the gateway always reflects the engine's current predicate set.
COPY prolog-engine/queries/ ./prolog-engine/queries/
EXPOSE 8081
CMD ["./gateway"]
