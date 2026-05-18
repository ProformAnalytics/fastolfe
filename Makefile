SWIPL  ?= swipl
GO     ?= go
SEASON ?= 2025

.PHONY: generate check repl home-goals all-home-goals consecutive-wins \
        all-consecutive-wins table test \
        docker-build docker-run docker-query rebuild \
        gateway-build rebuild-all ask

# ── Code generation ──────────────────────────────────────────────────────────
# Reads codegen/data/premier-league-data.csv and writes .pl facts to
# prolog-engine/data/generated/. Run this before docker-build or make check.

generate:
	cd codegen && $(GO) run ./cmd/generate \
		-csv data/premier-league-data.csv \
		-out ../prolog-engine/data/generated

# ── Prolog engine (local) ────────────────────────────────────────────────────

# Syntax-check: load all facts + queries and exit. Zero exit = clean.
check:
	cd prolog-engine && $(SWIPL) -g halt main.pl

# Drop into an interactive REPL with all facts loaded.
repl:
	cd prolog-engine && $(SWIPL) main.pl

# Print all teams with their home goal tallies.
all-home-goals:
	cd prolog-engine && $(SWIPL) -g "print_home_goals, halt" main.pl

# Print the team with the most home goals.
home-goals:
	cd prolog-engine && $(SWIPL) -g "print_most_home_goals, halt" main.pl

# Print each team's consecutive home win streak.
all-consecutive-wins:
	cd prolog-engine && $(SWIPL) -g "print_home_win_streaks, halt" main.pl

# Print the team with the longest consecutive home win streak.
consecutive-wins:
	cd prolog-engine && $(SWIPL) -g "print_most_consecutive_home_wins, halt" main.pl

# Print the league table for a given season (default: 2025 = 2025/26).
# Override with: make table SEASON=2024
table:
	cd prolog-engine && $(SWIPL) -g "print_league_table($(SEASON)), halt" main.pl 2>/dev/null

# Run all unit tests. Each suite runs in its own swipl session for isolation.
test:
	cd prolog-engine && $(SWIPL) -g "run_tests, halt" tests/test_league_table.pl
	cd prolog-engine && $(SWIPL) -g "run_tests, halt" tests/test_consecutive_wins.pl

# ── Prolog engine (Docker) ───────────────────────────────────────────────────
# Requires `make generate` first — the Dockerfile copies pre-generated facts.

docker-build:
	docker build -t prolog-engine prolog-engine

docker-run:
	docker run --rm -p 8080:8080 prolog-engine

# Fire a query at the running container. Usage: make docker-query GOAL="league_table(2025, Table)"
docker-query:
	@curl -s -X POST http://localhost:8080/query \
		-H 'Content-Type: application/json' \
		-d '{"goal":"$(GOAL)"}' | python3 -m json.tool

# Generate facts then build the prolog-engine image.
rebuild: generate docker-build

# ── LLM gateway (Docker) ─────────────────────────────────────────────────────
# Build context is the repo root so Dockerfile can COPY prolog-engine/queries/.

gateway-build:
	docker build -t llm-gateway -f llm-gateway/Dockerfile .

# Generate facts, rebuild both Docker images.
rebuild-all: generate docker-build gateway-build

# Ask a natural language question. Usage: make ask Q="Who won the most matches in 2023/24?"
ask:
	@curl -s -X POST http://localhost:8081/ask \
		-H 'Content-Type: application/json' \
		-d '{"question":"$(Q)"}' | python3 -m json.tool
