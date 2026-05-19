# prolog-sports — Agent Context

## What this project is

A natural-language query engine for historical Premier League data, encoded as Prolog facts,
fronted by an agentic LLM layer. The goal is to answer complex temporal and relational questions
— consecutive streaks, cross-season patterns, head-to-head records, league tables — at the speed
required for live broadcast analysis.

The system is built as three independent Docker services that compose into a pipeline:

```
User NL question
      ↓
  llm-gateway  (Go, port 8081)
      │  Claude (Sonnet 4.6, agentic tool-use loop)
      │  Claude calls query_prolog tool as many times as needed
      │  Returns natural language answer + tool call audit trail
      ↓
prolog-engine  (SWI-Prolog HTTP server, port 8080)
      │  POST /query  { "goal": "league_table(2024, Table)" }
      ↓
   Prolog facts generated from CSV by codegen (build time)
      ↓
  frontend  (React, port 3000)
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
│   │   ├── sequences.pl            # next_home_match/3, prev_home_match/3,
│   │   │                           # next_away_match/3, prev_away_match/3,
│   │   │                           # next_match/3, prev_match/3  ← combined home+away chains
│   │   ├── season_stats.pl         # team_season/10
│   │   ├── referees.pl             # referee/1, match_referee/2
│   │   ├── venues.pl               # venue/1, match_venue/2
│   │   └── attendance.pl           # match_attendance/2
│   ├── queries/                    # Hand-authored query predicates (literate-style comments)
│   │   ├── home_goals.pl           # team_home_goals/2, most_home_goals/2
│   │   ├── consecutive_wins.pl     # home and all-match consecutive win predicates (see below)
│   │   └── league_table.pl         # league_table/2 with full PL tiebreaker rules
│   ├── tests/
│   │   ├── fixtures/               # Minimal hand-crafted fact databases (fake season numbers 9901–9906)
│   │   ├── test_league_table.pl
│   │   └── test_consecutive_wins.pl
│   ├── main.pl                     # Loads generated/ then queries/ — used for local REPL/tests
│   ├── server.pl                   # Same load chain, then starts HTTP server on :8080
│   └── Dockerfile                  # FROM swipl:stable — copies pre-generated facts, no build stage
│
├── llm-gateway/                    # Service — agentic NL → Prolog → NL answer loop
│   ├── cmd/gateway/main.go         # Entry point: reads Docker secret, fetches atoms, starts :8081
│   ├── internal/gateway/
│   │   ├── llm.go                  # Anthropic client, BuildSystemPrompt, agentic Answer() loop,
│   │   │                           # ToolCall struct, prologTool definition
│   │   ├── handler.go              # POST /ask — calls llm.Answer(), returns tool_calls audit trail
│   │   ├── prolog.go               # PrologClient: Query, FetchAtoms
│   │   └── prompt.md               # Giskard system prompt (embedded via //go:embed)
│   ├── go.mod                      # module prolog-sports/llm-gateway — requires anthropic-sdk-go
│   └── Dockerfile                  # Build context = repo root; COPYs prolog-engine/queries/ into image
│
├── frontend/                       # Service — React chat UI
│   ├── src/
│   │   ├── App.jsx                 # Main chat component
│   │   └── App.css
│   ├── nginx.conf                  # Reverse-proxy: /api/* → llm-gateway:8081
│   └── Dockerfile                  # Node build stage + nginx serve stage
│
├── docker-compose.yml              # Orchestrates all three services; wires Docker secret for API key
├── Makefile                        # All targets prefixed by service (prolog-*, gateway-*) or scope (docker-*)
└── secrets/
    └── .gitkeep                    # Directory tracked; secrets/*.txt is .gitignored
```

---

## Development workflow

### First time / after CSV changes

```bash
make generate       # codegen reads CSV → writes prolog-engine/data/generated/*.pl
make prolog-check   # syntax-check: load all facts + queries, exit (zero = clean)
make prolog-test    # run all unit tests (must pass before any Docker build)
```

### Running locally (no Docker)

```bash
make prolog-repl              # interactive swipl with all facts loaded
make prolog-table             # print league table (default SEASON=2025; override SEASON=2024)
make prolog-home-goals        # team with most home goals
make prolog-consecutive-wins  # team with longest home win streak
```

One-off query:
```bash
cd prolog-engine && swipl -g "league_table(2024, T), print(T), halt" main.pl 2>/dev/null
```

### Docker

All Docker image builds go through `docker compose build`. Never use bare `docker build`
for service images — Docker Compose manages its own image namespace and `docker compose up`
will ignore images built with bare `docker build`, running a stale cached image instead.

```bash
# Requires make generate first — Dockerfile copies pre-generated facts
make prolog-build    # docker compose build prolog-engine
make gateway-build   # docker compose build llm-gateway
make rebuild-all     # generate + docker compose build (all services)

make up              # docker compose up (all services)
make down            # docker compose down

make prolog-query GOAL="league_table(2025, Table)"  # raw query to prolog-engine
make ask Q="Who had the longest home win streak?"   # full NL pipeline via llm-gateway
```

### API key setup (Docker)

The Anthropic API key is stored as a Docker file-based secret — never in an environment variable or image layer.

```bash
echo "sk-ant-..." > secrets/anthropic_api_key.txt
```

The key is mounted at `/run/secrets/anthropic_api_key` inside the `llm-gateway` container. `secrets/*.txt` is in `.gitignore`.

---

## LLM gateway architecture

`POST /ask  { "question": "..." }` → `{ "question", "tool_calls", "answer" }`

The response's `tool_calls` array is a full audit trail of every Prolog query Claude issued:
```json
{
  "question": "When did Man Utd last win 5 consecutive games?",
  "tool_calls": [
    { "goal": "findall(...)", "result": "...", "success": true },
    { "goal": "match(4087933, ...)", "result": "match(4087933,2023,...)", "success": true }
  ],
  "answer": "The last time Manchester United won five consecutive matches was..."
}
```

**Startup sequence** (before serving requests):
1. Read API key from `/run/secrets/anthropic_api_key`
2. Fetch all team, referee, and venue atoms from the prolog-engine via `findall`
3. Read the three hand-authored query files from `prolog-engine/queries/`
4. Build the system prompt: `prompt.md` template + injected query file contents + atom lists
5. Cache that prompt — it's static for the lifetime of the process

**Per-request agentic loop** (`llm.go:Answer()`):
1. Send the question to Claude (Sonnet 4.6, adaptive thinking, `maxToolCalls = 12`)
2. Claude calls `query_prolog` tool with a Prolog goal
3. Gateway executes it against prolog-engine, appends result to conversation history
4. Claude continues issuing tool calls — enriching, verifying, following up — until satisfied
5. When Claude stops requesting tools (`StopReason != tool_use`), extract the text answer
6. Return answer + full `[]ToolCall` audit trail to the caller

Claude does not receive a Prolog goal in the system prompt — it generates goals autonomously
based on the predicate documentation in `prompt.md` and decides when it has enough information.

**Prompt architecture** (`llm-gateway/internal/gateway/`):
- `prompt.md` — Giskard system prompt: identity, scope guardrails, predicate reference, atom format rules, Prolog patterns, tool use strategy. Edit this file to tune LLM behaviour without touching Go.
- `prolog-engine/queries/*.pl` — passed verbatim to the LLM under `## Hand-authored query modules`. The literate comments in these files are the documentation. Adding a new predicate here automatically teaches the LLM about it at next restart.
- Dynamic atom lists — fetched fresh from the Prolog engine at startup; injected via `%TEAMS%`, `%REFEREES%`, `%VENUES%` placeholders. Ensures the LLM uses exact normalised atoms.

**Key constants in `llm.go`:**
- `maxToolCalls = 12` — hard cap on the agentic loop per request; returns an error if exceeded
- `maxResultLen = 3000` — Prolog results are truncated to this before feeding back to Claude; prevents large `findall` dumps from consuming context

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

% Per-team successor/predecessor chains — O(1) temporal hops without sort overhead.
next_home_match(Team, MatchId1, MatchId2). % MatchId2 is next home match after MatchId1
prev_home_match(Team, MatchId1, MatchId2). % inverse
next_away_match(Team, MatchId1, MatchId2).
prev_away_match(Team, MatchId1, MatchId2).
next_match(Team, MatchId1, MatchId2).      % next match (home OR away) after MatchId1
prev_match(Team, MatchId1, MatchId2).      % inverse

team_season(Team, Season, Played, Won, Drawn, Lost, GF, GA, GD, Points).
% One fact per (team, season). Pre-aggregated. Used directly by league_table/2.

referee(Atom).
match_referee(MatchId, Referee).

venue(Atom).
match_venue(MatchId, Venue).

match_attendance(MatchId, Attendance). % integer; 0 = not recorded

% ── Hand-authored query predicates (prolog-engine/queries/) ────────────────

% home_goals.pl
team_home_goals(+Team, -TotalGoals).      % sum of goals scored at home across all seasons
most_home_goals(-Team, -Goals).           % team with highest aggregate home goal tally

% consecutive_wins.pl
max_consecutive_home_wins(+Team, -N).     % longest home-only win streak for Team
most_consecutive_home_wins(-Team, -N).    % team with the longest home-only win streak

max_consecutive_wins(+Team, -N).          % longest all-match win streak (home + away)
most_consecutive_wins(-Team, -N).         % team with the longest all-match win streak

last_n_consecutive_wins(+Team, +N, -EndDate).
% EndDate (YYYYMMDD) of the final match in the most recent N-or-more consecutive win run.
% Fails if Team never achieved N consecutive wins.

% league_table.pl
league_table(+Season, -Rows).
% Rows = [row(Pos, Team, Played, Won, Drawn, Lost, GF, GA, GD, Points), ...]
% Full PL tiebreaker: Points → GD → GF → H2H Points → H2H Away Goals
```

**Atom normalisation:** lowercase, spaces/punctuation → `_`, `" & "` → `"_and_"`, strip leading/trailing `_`.
`"Brighton & Hove Albion"` → `brighton_and_hove_albion` | `"Arsenal FC"` → `arsenal_fc`

---

## Prolog query patterns

### Inline chain expansion — the primary pattern for consecutive queries

For "N consecutive wins/draws/losses", expand the `next_match` chain as a flat conjunction.
Prolog backtracking finds every qualifying window; `findall + max_member` on the terminal
date returns the most recent occurrence.

```prolog
% Most recent time Man Utd won 5 consecutive games (home or away):
findall(D5, (
    (home_win(manchester_united, M1) ; away_win(manchester_united, M1)),
    next_match(manchester_united, M1, M2),
    (home_win(manchester_united, M2) ; away_win(manchester_united, M2)),
    next_match(manchester_united, M2, M3),
    (home_win(manchester_united, M3) ; away_win(manchester_united, M3)),
    next_match(manchester_united, M3, M4),
    (home_win(manchester_united, M4) ; away_win(manchester_united, M4)),
    next_match(manchester_united, M4, M5),
    (home_win(manchester_united, M5) ; away_win(manchester_united, M5)),
    match(M5, _, D5, _, _, _, _)
), Dates), max_member(LastDate, Dates)
```

Scale by adding more `next_match` + result hops. Use `next_home_match` for home-only runs,
`next_away_match` for away-only runs.

### Streak queries — collect ALL matches, never filter inside findall

Wrong — silently drops zero-goal games so the fold sees no gaps:
```prolog
% BAD: only scoring matches enter the list; fold counts 372 "consecutive"
findall(D-M, (match(M,_,D,manchester_city,_,HG,_), HG>0 ; ...), Pairs), ...
```

Correct — collect ALL matches with a 1/0 flag; fold resets on 0:
```prolog
% GOOD: every match appears; scoreless games get S=0 and reset the counter
findall(D-S, (
    match(_,_,D,manchester_city,_,HG,_), (HG>0 -> S=1 ; S=0)
    ; match(_,_,D,_,manchester_city,_,AG), (AG>0 -> S=1 ; S=0)
), Pairs),
msort(Pairs, Sorted), pairs_values(Sorted, Scores),
foldl([S,C0-M0,C1-M1]>>(S=:=1 -> (C1 is C0+1, M1 is max(C1,M0)) ; C1=0, M1=M0),
      Scores, 0-0, _-MaxStreak)
```

This rule applies to any streak question: goals, clean sheets, unbeaten runs, etc.

### Always embed match details in findall keys

Wrong — returns a bare ID that requires a follow-up query:
```prolog
findall(Total-Id, (match(Id,_,_,H,A,HG,AG), Total is HG+AG), Pairs),
max_member(MaxTotal-MatchId, Pairs)
```

Correct — the result is self-describing:
```prolog
findall(Total-match(Id,Home,Away,HG,AG,Season), (match(Id,Season,_,Home,Away,HG,AG), Total is HG+AG), Pairs),
max_member(MaxTotal-match(MatchId,HomeTeam,AwayTeam,HomeGoals,AwayGoals,MatchSeason), Pairs)
```

---

## Testing

Tests use SWI-Prolog's `library(plunit)`. Run with:

```bash
make prolog-test
```

Each suite runs as its own `swipl` invocation — fixtures from different suites cannot contaminate each other. Exit code is non-zero on any failure (safe as a CI gate). **Always run `make prolog-test` before building Docker images.**

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
4. `make prolog-test` → `make prolog-check`.

---

## Core architectural decisions

**Agentic tool-use loop, not a two-call pipeline.**
The gateway exposes a single `query_prolog` tool to Claude. Claude calls it iteratively —
once to find a key ID or statistic, again to enrich the result with match details, again to
verify a surprising number. This eliminates the need for a hard-coded retry loop and allows
Claude to self-correct logical errors between calls.

**Dates as YYYYMMDD integers, not `date(Y,M,D)` compound terms.**
Integers sort correctly under standard Prolog term order so `msort` gives chronological order
with no extra code. Also valid in Datalog — compound terms are not — keeping a future Souffle
migration cheap.

**Pre-computed successor/predecessor chains (`next_home_match`, `next_match`, etc.).**
Temporal queries otherwise require collect→sort→fold on every call. These chains turn each
temporal hop into an O(1) fact lookup. `sequences.pl` is the largest generated file — describe
it via examples in `prompt.md` rather than passing it verbatim to the LLM.

**`next_match`/`prev_match` are the combined home+away chains.**
Use these for "N consecutive wins across all fixtures". Use `next_home_match`/`next_away_match`
only when the question is specifically about home or away sequences. The LLM prompt teaches
inline chain expansion as the primary pattern for consecutive queries.

**Pre-computed result classification (`home_win`, `home_loss`, etc.).**
Avoids `HG > AG` arithmetic scattered across every query. Queries read as pure logic. LLMs
generate them more reliably than raw arithmetic comparisons.

**Two separate Go modules.**
`codegen` has zero external dependencies (pure stdlib). `llm-gateway` depends on the Anthropic
SDK. Keeping them separate avoids pulling the SDK into the build tool and makes each Docker
image's dependency graph minimal.

**`MatchSource` interface in codegen.**
`cmd/generate/main.go` creates `loader.NewCSVSource(...)`. Swapping to
`loader.NewPostgresSource(...)` is the only change needed to move to a live data pipeline.

**Query files as the single source of truth for the LLM.**
The hand-authored `prolog-engine/queries/*.pl` files are passed verbatim to the LLM. Their
literate comments are the documentation. The prompt never drifts from the implementation
because the file *is* the documentation.

**Giskard scope guardrails are enforced in the system prompt, not in Go.**
The LLM is instructed to refuse non-football questions and to never make claims it has not
verified with a `query_prolog` call. In particular: Claude must never reason mentally over
result strings to derive counts or win/loss records — it must issue a follow-up query or omit
the claim. See `prompt.md` for the exact rules.

---

## Gotchas

**`make generate` must run before `make prolog-check`, `make prolog-test`, or any Docker build.**
`prolog-engine/data/generated/` is `.gitignored`. A fresh clone has no generated facts.

**Always build Docker images via `docker compose build`, never bare `docker build`.**
Docker Compose manages its own image namespace (named by project + service). An image built with
`docker build -t llm-gateway .` is a different image from the one `docker compose up` uses.
Running `docker compose up` after a bare `docker build` will silently start the old cached image.
All Makefile targets (`prolog-build`, `gateway-build`, `docker-build`) delegate to `docker compose build`.

**Claude must never reason mentally over Prolog result strings.**
When `query_prolog` returns a list of matches, Claude cannot reliably count, compare, or
derive conclusions from it by reading the result. Example failure: "Leicester appear 3 times,
winning all three" — claimed without querying, wrong. The rule in `prompt.md`:
"If you want to say 'Team X won Y of these matches', issue a follow-up `query_prolog` call.
When in doubt, omit the claim." This is the #1 source of hallucinations in the current system.

**Streak findall must collect ALL matches, not just matching ones.**
If the `findall` generator filters to only scoring (or winning) matches, the fold sees no
gaps and reports the total count as a single streak. Always collect every match with a 1/0
flag and let the fold reset on 0. See the Prolog query patterns section above.

**Backtick-wrapped goals silently corrupt Prolog queries.**
In SWI-Prolog, `` `...` `` is a character code list, not a string. If the LLM returns
`` `league_table(2025, T)` `` instead of `league_table(2025, T)`, Prolog evaluates the
character code list as a goal — it "succeeds" but returns a list of ASCII integers, not
query results. `handler.go`'s `stripMarkdown()` defensively strips backticks before sending
to Prolog. The examples in `prompt.md` must not use backtick formatting on goal strings.

**Discontiguous predicate warnings.**
When multiple predicate families interleave in one generated file (e.g. `home_win`,
`home_draw`, `home_loss` in `results.pl`), SWI-Prolog warns unless `:- discontiguous pred/arity.`
appears at the top. The generator emits these automatically. If you add a new predicate family
to an existing generated file, add it to the `discontiguous` list in
`codegen/internal/generator/generator.go`.

**`max_member/2` returns only one result on a tie.**
To iterate all joint-maximum results:
```prolog
findall(N-Info, (...), Pairs),
max_member(Max-_, Pairs),
forall(member(Max-Info, Pairs), print(Info)).
```

**`consult` replaces clauses for static predicates across files.**
When file B is consulted and defines a predicate already in file A, SWI-Prolog silently
discards file A's clauses. To allow accumulation across files (as in test fixtures), declare
`:- multifile pred/arity.` **before** the first `consult`. `:- dynamic` alone is not sufficient.

**Anonymous variables in `findall` templates produce unbound sort keys.**
`findall(f(_,X), ..., List)` → each `_` is a fresh unbound variable. Sorting by `msort`
compares by memory address — non-deterministic. Always use named variables for any term
that will be compared or sorted.

**Season encoding.**
`Season` is the start year: `2025` = 2025/26. Display as: `S1 is (Season+1) mod 100`, then
`format('~w/~w', [Season, S1])`.

**`llm-gateway` startup requires `prolog-engine` to be healthy.**
The gateway calls `FetchAtoms` on startup to build the LLM system prompt. If `docker compose up`
is run cold, the gateway may restart once while the prolog-engine loads its ~37,000 facts (~1–2s).
`depends_on: prolog-engine` in docker-compose handles ordering but not readiness — the
`restart: unless-stopped` policy covers the gap.

**`maxToolCalls = 12` is a hard ceiling per request.**
If Claude exhausts all 12 calls without producing a final answer, the gateway returns an
HTTP 500 with the partial tool call audit trail. This should not happen for normal questions
but can occur if Claude gets into a correction loop on a malformed goal. If you raise this
limit, monitor API spend — each call hits the Anthropic API.

---

## Future work

- **Postgres data source** — implement `loader.PostgresSource` in `codegen/internal/loader/` matching the `MatchSource` interface; no other changes needed
- **Player-level data** — goals, assists, appearances per match (CSV metadata supports this)
- **Extended query library** — form tables, head-to-head records, season summaries as new files in `prolog-engine/queries/`
- **Datalog (Souffle) upgrade path** — rule shapes port directly from Prolog; YYYYMMDD integer dates were chosen specifically for this; blockers are no compound terms, no `findall`, no `msort`
- **Streaming answers** — the Anthropic SDK supports streaming; wiring it through the gateway would let the frontend render the answer token-by-token rather than waiting for the full agentic loop (which can involve 5–12 API round-trips) to complete
- **Response caching** — the agentic loop makes multiple API calls per question and repeated questions (common in broadcast) hit the full loop every time; a cache keyed on `(question, system_prompt_hash)` would cut costs significantly without any change to answer quality
- **Frontend tool call inspector** — the gateway returns the full `tool_calls` audit trail (Prolog goals + results) but the frontend does not display it; a collapsible debug panel per answer would make hallucination debugging much faster without requiring `curl`
