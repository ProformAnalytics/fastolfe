# Stage 1: generate Prolog facts from CSV using Go
FROM golang:1.23-alpine AS generator
WORKDIR /build
COPY golang/ ./golang/
RUN cd golang && go run ./cmd/generate \
    -csv data/premier-league-data.csv \
    -out /generated

# Stage 2: Prolog HTTP server — only swipl in final image
FROM swipl:stable
WORKDIR /prolog
COPY --from=generator /generated      ./data/generated/
COPY prolog/queries/                  ./queries/
COPY prolog/server.pl                 ./server.pl
EXPOSE 8080
CMD ["swipl", "server.pl"]
