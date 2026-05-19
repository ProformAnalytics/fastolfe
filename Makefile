SWIPL  ?= swipl
GO     ?= go
SEASON ?= 2025

.PHONY: generate \
        prolog-check prolog-repl prolog-test \
        prolog-home-goals prolog-all-home-goals \
        prolog-consecutive-wins prolog-all-consecutive-wins \
        prolog-table \
        prolog-build prolog-run prolog-query prolog-rebuild \
        gateway-build gateway-run ask \
        docker-build docker-run rebuild-all up down

# ── Code generation ──────────────────────────────────────────────────────────
# Reads codegen/data/premier-league-data.csv and writes .pl facts to
# prolog-engine/data/generated/. Run before prolog-build or prolog-check.

generate:
	cd codegen && $(GO) run ./cmd/generate \
		-csv data/premier-league-data.csv \
		-player-csv data/player-in-match-data.csv \
		-out ../prolog-engine/data/generated

# ── Prolog engine (local) ────────────────────────────────────────────────────

# Syntax-check: load all facts + queries and exit. Zero exit = clean.
prolog-check:
	cd prolog-engine && $(SWIPL) -g halt main.pl

# Drop into an interactive REPL with all facts loaded.
prolog-repl:
	cd prolog-engine && $(SWIPL) main.pl

# Run all unit tests. Each suite runs in its own swipl session for isolation.
prolog-test:
	cd prolog-engine && $(SWIPL) -g "run_tests, halt" tests/test_league_table.pl
	cd prolog-engine && $(SWIPL) -g "run_tests, halt" tests/test_consecutive_wins.pl

# Print all teams with their home goal tallies.
prolog-all-home-goals:
	cd prolog-engine && $(SWIPL) -g "print_home_goals, halt" main.pl

# Print the team with the most home goals.
prolog-home-goals:
	cd prolog-engine && $(SWIPL) -g "print_most_home_goals, halt" main.pl

# Print each team's consecutive home win streak.
prolog-all-consecutive-wins:
	cd prolog-engine && $(SWIPL) -g "print_home_win_streaks, halt" main.pl

# Print the team with the longest consecutive home win streak.
prolog-consecutive-wins:
	cd prolog-engine && $(SWIPL) -g "print_most_consecutive_home_wins, halt" main.pl

# Print the league table for a given season (default: 2025 = 2025/26).
# Override with: make prolog-table SEASON=2024
prolog-table:
	cd prolog-engine && $(SWIPL) -g "print_league_table($(SEASON)), halt" main.pl 2>/dev/null

# ── Prolog engine (Docker) ───────────────────────────────────────────────────
# Requires `make generate` first — the Dockerfile copies pre-generated facts.

prolog-build:
	docker compose build prolog-engine

prolog-run:
	docker compose run --rm prolog-engine

# Fire a raw Prolog query at the running prolog-engine container.
# Usage: make prolog-query GOAL="league_table(2025, Table)"
prolog-query:
	@curl -s -X POST http://localhost:8080/query \
		-H 'Content-Type: application/json' \
		-d '{"goal":"$(GOAL)"}' | python3 -m json.tool

# Generate facts then rebuild the prolog-engine image.
prolog-rebuild: generate prolog-build

# ── LLM gateway (Docker) ─────────────────────────────────────────────────────
# Build context is the repo root so Dockerfile can COPY prolog-engine/queries/.

gateway-build:
	docker compose build llm-gateway

# Run only the gateway service via compose (handles Docker secret injection).
gateway-run:
	docker compose run --rm llm-gateway

# Ask a natural language question via the llm-gateway.
# Usage: make ask Q="Who won the most matches in 2023/24?"
ask:
	@curl -s -X POST http://localhost:8081/ask \
		-H 'Content-Type: application/json' \
		-d '{"question":"$(Q)"}' | python3 -m json.tool

# ── Full stack ───────────────────────────────────────────────────────────────

# Build both service images via Docker Compose.
docker-build:
	docker compose build

# Start both services.
docker-run: up

# Generate facts and rebuild both service images.
rebuild-all: generate docker-build

# Start / stop both services via Docker Compose.
up:
	docker compose up

down:
	docker compose down
