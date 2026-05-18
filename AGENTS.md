# prolog-sports — Agent Context

## What this project is

A query engine for historical Premier League data, encoded as Prolog facts, fronted by an LLM translation layer. The goal is to answer complex temporal and relational questions in natural language — consecutive streaks, cross-season patterns, head-to-head records — at the speed required for live broadcast analysis.

The system is built as three independent components that compose into a pipeline:

```
User NL question
      ↓
  llm-gateway  (Go, port 8081)
      │  Claude API — translates NL → Prolog goal
      │  Claude API — translates Prolog result → natural language answer
      ↓
prolog-engine  (SWI-Prolog HTTP server, port 8080)
      │  POST /query  { "goal": "league_table(2024, Table)" }
      ↓
   Prolog facts generated from CSV by codegen (build time)
```

---

## Project structure

```
prolog-sports/
│
├── codegen/                        # Build tool — CSV → Prolog facts (not a service)
│   ├── cmd/generate/main.go        # CLI: -csv and -out flags
│   ├── internal/loader/
│   │   ├── source.go               # MatchSource interface + Match struct
│   │   └── csv.go                  # CSVSource (swap for PostgresSource in production)
│   ├── internal/generator/
│   │   └── generator.go            # Writes 9 .pl fact files from []Match
│   ├── data/
│   │   └── premier-league-data.csv # Source data (2015/16–2025/26, ~4160 matches)
│   └── go.mod                      # module prolog-sports/codegen — stdlib only, no external deps
│
├── prolog-engine/                  # Service — always-on SWI-Prolog HTTP server
│   ├── data/generated/             # NEVER edit — output of `make generate` (.gitignored)
│   │   ├── matches.pl              # match/7
│   │   ├── teams.pl                # team/1
│   │   ├── results.pl              # home_win/2, home_draw/2, home_loss/2, away_*/2
│   │   ├── goals.pl                # match_goals/3
│   │   ├── sequences.pl            # next_home_match/3, prev_home_match/3, next_away_match/3, prev_away_match/3
│   │   ├── season_stats.pl         # team_season/10
│   │   ├── referees.pl             # referee/1, match_referee/2
│   │   ├── venues.pl               # venue/1, match_venue/2
│   │   └── attendance.pl           # match_attendance/2
│   ├── queries/                    # Hand-authored query predicates (literate-style comments)
│   │   ├── home_goals.pl           # team_home_goals/2, most_home_goals/2
│   │   ├── consecutive_wins.pl     # max_consecutive_home_wins/2, most_consecutive_home_wins/2
│   │   └── league_table.pl         # league_table/2 with full PL tiebreaker rules
│   ├── tests/
│   │   ├── fixtures/               # Minimal hand-crafted fact databases (fake season numbers 9901–9906)
│   │   ├── test_league_table.pl
│   │   └── test_consecutive_wins.pl
│   ├── main.pl                     # Loads generated/ then queries/ — used for local REPL/tests
│   ├── server.pl                   # Same load chain, then starts HTTP server on :8080
│   └── Dockerfile                  # FROM swipl:stable — copies pre-generated facts, no build stage
│
├── llm-gateway/                    # Service — NL → Prolog → NL answer
│   ├── cmd/gateway/main.go         # Entry point: reads Docker secret, fetches atoms, starts :8081
│   ├── internal/gateway/
│   │   ├── llm.go                  # Anthropic client, BuildSystemPrompt, TranslateToProlog, FormatAnswer
│   │   ├── handler.go              # POST /ask — translate → execute → retry loop (up to 3 attempts)
│   │   ├── prolog.go               # PrologClient: Query, FetchAtoms
│   │   └── prompt.md               # LLM system prompt template (embedded via //go:embed)
│   ├── go.mod                      # module prolog-sports/llm-gateway — requires anthropic-sdk-go
│   └── Dockerfile                  # Build context = repo root; COPYs prolog-engine/queries/ into image
│
├── docker-compose.yml              # Orchestrates both services; wires Docker secret for API key
├── Makefile                        # generate, test, check, docker-build, gateway-build, ask targets
└── secrets/
    └── .gitkeep                    # Directory tracked; secrets/*.txt is .gitignored
```

---

## Development workflow

### First time / after CSV changes

```bash
make generate          # codegen reads CSV → writes prolog-engine/data/generated/*.pl
make check             # syntax-check: load all facts + queries, exit (zero = clean)
make test              # run all unit tests (must pass before any Docker build)
```

### Running locally (no Docker)

```bash
make repl              # interactive swipl with all facts loaded
make table             # print league table (default SEASON=2025; override SEASON=2024)
make home-goals        # team with most home goals
make consecutive-wins  # team with longest home win streak
```

One-off query:
```bash
cd prolog-engine && swipl -g "league_table(2024, T), print(T), halt" main.pl 2>/dev/null
```

### Docker

```bash
# Requires make generate first — Dockerfile copies pre-generated facts
make docker-build      # builds prolog-engine image (context: ./prolog-engine)
make gateway-build     # builds llm-gateway image (context: repo root)
make rebuild-all       # generate + docker-build + gateway-build in one step

docker compose up      # starts both services

make docker-query GOAL="league_table(2025, Table)"   # query prolog-engine directly
make ask Q="Who had the longest home win streak?"     # full NL pipeline via llm-gateway
```

### API key setup (Docker)

The Anthropic API key is stored as a Docker file-based secret — never in an environment variable or image layer.

```bash
echo "sk-ant-..." > secrets/anthropic_api_key.txt
```

The key is mounted at `/run/secrets/anthropic_api_key` inside the `llm-gateway` container. `secrets/*.txt` is in `.gitignore`.

---

## LLM gateway architecture

`POST /ask  { "question": "..." }` → `{ "question", "prolog_query", "prolog_result", "answer" }`

**Startup sequence** (before serving requests):
1. Read API key from `/run/secrets/anthropic_api_key`
2. Fetch all team, referee, and venue atoms from the prolog-engine via `findall`
3. Read the three hand-authored query files from `prolog-engine/queries/`
4. Build the system prompt: `prompt.md` template + injected query file contents + atom lists
5. Cache that prompt — it's static for the lifetime of the process

**Per-request pipeline:**
1. Call 1 (Claude, `claude-opus-4-7`): NL question → Prolog goal string. System prompt is marked `cache_control: ephemeral` so the large schema prompt is cached across requests.
2. Execute goal against prolog-engine via `POST /query`
3. If Prolog returns an error, feed it back to Claude as a correction request and retry (up to 3 times)
4. Call 2 (Claude): raw Prolog result term → natural language answer

**Prompt architecture** (`llm-gateway/internal/gateway/`):
- `prompt.md` — preamble, generated predicate reference (with examples for large files like `sequences.pl`), atom format rules, output constraints, few-shot NL→Prolog examples. Edit this file to tune LLM behaviour without touching Go.
- `prolog-engine/queries/*.pl` — passed verbatim to the LLM under `## Hand-authored query modules`. The literate comments in these files are the documentation. Adding a new predicate here automatically teaches the LLM about it at next restart.
- Dynamic atom lists — fetched fresh from the Prolog engine at startup; injected via `%TEAMS%`, `%REFEREES%`, `%VENUES%` placeholders. Ensures the LLM uses exact normalised atoms.

**Adding a new query predicate:**
1. Add the `.pl` file to `prolog-engine/queries/`
2. Add it to `server.pl` and `main.pl` consult chains
3. Add the filename to `queryFiles` in `llm-gateway/internal/gateway/llm.go`
4. Restart the gateway — it will read and inject the new file automatically

---

## Full predicate reference

```prolog
% ── Generated facts (prolog-engine/data/generated/) ───────────────────────

match(Id, Season, Date, HomeTeam, AwayTeam, HomeGoals, AwayGoals).
%  Id       — transfermarkt_id integer (stable external key)
%  Season   — start year, e.g. 2025 = 2025/26 season
%  Date     — YYYYMMDD integer (sorts correctly under standard term order)

team(Atom).

home_win(Team, MatchId).   home_draw(Team, MatchId).   home_loss(Team, MatchId).
away_win(Team, MatchId).   away_draw(Team, MatchId).   away_loss(Team, MatchId).
% One fact per match per team. Pre-classified to avoid arithmetic in queries.

match_goals(MatchId, Team, Goals).
% Symmetric — works for both home and away team in the same match.

next_home_match(Team, MatchId1, MatchId2). % MatchId2 is next home match after MatchId1
prev_home_match(Team, MatchId1, MatchId2). % inverse
next_away_match(Team, MatchId1, MatchId2).
prev_away_match(Team, MatchId1, MatchId2).
% Pre-computed successor chains. O(1) temporal hops without sort overhead.

team_season(Team, Season, Played, Won, Drawn, Lost, GF, GA, GD, Points).
% One fact per (team, season). Pre-aggregated. Used directly by league_table/2.

referee(Atom).
match_referee(MatchId, Referee).

venue(Atom).
match_venue(MatchId, Venue).

match_attendance(MatchId, Attendance). % integer; 0 = not recorded

% ── Hand-authored query predicates (prolog-engine/queries/) ────────────────

team_home_goals(+Team, -TotalGoals).      % sum of goals scored at home across all seasons
most_home_goals(-Team, -Goals).           % team with highest aggregate home goal tally

max_consecutive_home_wins(+Team, -N).     % longest home win streak for Team
most_consecutive_home_wins(-Team, -N).    % team with the longest home win streak

league_table(+Season, -Rows).
% Rows = [row(Pos, Team, Played, Won, Drawn, Lost, GF, GA, GD, Points), ...]
% Full PL tiebreaker: Points → GD → GF → H2H Points → H2H Away Goals
```

**Atom normalisation:** lowercase, spaces/punctuation → `_`, `" & "` → `"_and_"`, strip leading/trailing `_`.
`"Brighton & Hove Albion"` → `brighton_and_hove_albion` | `"Arsenal FC"` → `arsenal_fc`

---

## Testing

Tests use SWI-Prolog's `library(plunit)`. Run with:

```bash
make test
```

Each suite runs as its own `swipl` invocation — fixtures from different suites cannot contaminate each other. Exit code is non-zero on any failure (safe as a CI gate). **Always run `make test` before building Docker images.**

**Test structure:** Each `test_*.pl` loads the relevant query module directly (not `main.pl`) and then consults only its own fixture files. No generated data is loaded during tests.

**Fixture design rules:**
- Fake season numbers (9901–9906) that cannot appear in real data — fixtures never collide with each other or with generated data.
- `league_table` fixtures define `team_season/10` facts directly (pre-aggregated). Only H2H tiebreak tests also define `match/7` facts.
- `consecutive_wins` fixtures use `streak_*` atom prefixes for team names.
- Predicates shared across multiple fixture files must be declared `:- multifile pred/arity.` in the test file **before** any fixture is consulted, or SWI-Prolog will silently discard the first file's clauses when the second is loaded.

**Adding a test:**
1. Create a fixture in `prolog-engine/tests/fixtures/` with a new fake season number.
2. Add `:- multifile pred/arity.` to the test file for any predicate shared across fixtures.
3. Add a `test(name) :- ...` block.
4. `make test` → `make check`.

---

## Core architectural decisions

**Dates as YYYYMMDD integers, not `date(Y,M,D)` compound terms.**
Integers sort correctly under standard Prolog term order so `msort` gives chronological order with no extra code. Also valid in Datalog — compound terms are not — keeping a future Souffle migration cheap.

**Pre-computed successor/predecessor chains (`next_home_match` etc.).**
Temporal queries otherwise require collect→sort→fold on every call. These chains turn each temporal hop into an O(1) fact lookup. `sequences.pl` is the largest generated file (16k+ lines) — don't pass it to the LLM; describe it via examples in `prompt.md`.

**Pre-computed result classification (`home_win`, `home_loss`, etc.).**
Avoids `HG > AG` arithmetic scattered across every query. Queries read as pure logic. LLMs generate them more reliably than raw arithmetic comparisons.

**Two separate Go modules.**
`codegen` has zero external dependencies (pure stdlib). `llm-gateway` depends on the Anthropic SDK. Keeping them separate avoids pulling the SDK into the build tool and makes each Docker image's dependency graph minimal.

**`MatchSource` interface in codegen.**
`cmd/generate/main.go` creates `loader.NewCSVSource(...)`. Swapping to `loader.NewPostgresSource(...)` is the only change needed to move to a live data pipeline.

**Query files as the single source of truth for the LLM.**
The hand-authored `prolog-engine/queries/*.pl` files are passed verbatim to the LLM. Their literate comments are the documentation. The prompt never drifts from the implementation because the file *is* the documentation.

---

## Temporal logic — how it works in Prolog

Prolog facts are an **unordered set**. Every temporal query requires an explicit pipeline:

1. **Collect** — `findall/3` pulls facts into a list, capturing date as a value
2. **Sort** — `msort/2` imposes chronological order (YYYYMMDD integers sort correctly)
3. **Fold** — a recursive accumulator walks the ordered list tracking state

```prolog
findall(Date-Outcome, (match(_, _, Date, Team, _, HG, AG), outcome(HG, AG, Outcome)), Pairs),
msort(Pairs, Sorted),
pairs_values(Sorted, Results),
max_win_streak(Results, 0, 0, Max).
```

The pre-computed `next_home_match`/`prev_home_match` chains skip steps 1–3 for per-team sequences.

---

## Gotchas

**`make generate` must run before `make check`, `make test`, or `make docker-build`.**
`prolog-engine/data/generated/` is `.gitignored`. A fresh clone has no generated facts.

**Discontiguous predicate warnings.**
When multiple predicate families interleave in one generated file (e.g. `home_win`, `home_draw`, `home_loss` in `results.pl`), SWI-Prolog warns unless `:- discontiguous pred/arity.` appears at the top. The generator emits these automatically. If you add a new predicate family to an existing generated file, add it to the `discontiguous` list in `codegen/internal/generator/generator.go`.

**`max_member/2` returns only one result on a tie.**
To iterate all joint-maximum results:
```prolog
findall(N-Info, (...), Pairs),
max_member(Max-_, Pairs),
forall(member(Max-Info, Pairs), print(Info)).
```

**`consult` replaces clauses for static predicates across files.**
When file B is consulted and defines a predicate already in file A, SWI-Prolog silently discards file A's clauses. To allow accumulation across files (as in test fixtures), declare `:- multifile pred/arity.` **before** the first `consult`. `:- dynamic` alone is not sufficient.

**Anonymous variables in `findall` templates produce unbound sort keys.**
`findall(f(_,X), ..., List)` → each `_` is a fresh unbound variable. Sorting these by `msort` compares by memory address — non-deterministic. Always use named variables for any term that will be compared or sorted.

**Season encoding.**
`Season` is the start year: `2025` = 2025/26. Display as: `S1 is (Season+1) mod 100`, then `format('~w/~w', [Season, S1])`.

**llm-gateway startup requires prolog-engine to be healthy.**
The gateway calls `FetchAtoms` on startup to build the LLM system prompt. If `docker compose up` is run cold, the gateway may restart once while the prolog-engine loads its ~37,000 facts (~1–2s). `depends_on: prolog-engine` in docker-compose handles ordering but not readiness — the `restart: unless-stopped` policy covers the gap.

---

## Future work

- **Postgres data source** — implement `loader.PostgresSource` in `codegen/internal/loader/` matching the `MatchSource` interface; no other changes needed
- **Player-level data** — goals, assists, appearances per match (CSV metadata supports this)
- **Extended query library** — form tables, head-to-head records, season summaries as new files in `prolog-engine/queries/`
- **Datalog (Souffle) upgrade path** — rule shapes port directly from Prolog; YYYYMMDD integer dates were chosen specifically for this; blockers are no compound terms, no `findall`, no `msort`
