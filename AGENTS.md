# prolog-sports — Agent Context

## What this project is

A query engine for historical Premier League data, encoded as Prolog facts. The goal is to answer complex temporal and relational questions that are awkward in SQL — consecutive streaks, "the match following condition X", cross-season patterns — and eventually to accept those questions in natural language via an LLM translation layer.

The primary use case is **live broadcast analysis**: a presenter asks a question during a halftime interval and gets a sourced, precise answer in a few seconds.

---

## Project structure

```
prolog-sports/
├── golang/                          # Go code generator
│   ├── cmd/generate/main.go         # CLI: -csv and -out flags
│   ├── internal/loader/
│   │   ├── source.go                # MatchSource interface + Match struct
│   │   └── csv.go                   # CSVSource — swap for PostgresSource in production
│   ├── internal/generator/
│   │   └── generator.go             # Writes 5 .pl files from []Match
│   └── data/
│       └── premier-league-data.csv  # Source data (2015/16–2025/26, 4160 matches)
├── prolog/
│   ├── data/generated/              # NEVER edit by hand — output of `make generate`
│   │   ├── matches.pl               # match/7
│   │   ├── teams.pl                 # team/1
│   │   ├── results.pl               # home_win/2, home_loss/2, home_draw/2, away_*/2
│   │   ├── goals.pl                 # match_goals/3
│   │   ├── sequences.pl             # next_home_match/3, prev_home_match/3, next_away_match/3, prev_away_match/3
│   │   └── season_stats.pl          # team_season/10
│   ├── queries/                     # Hand-authored query logic
│   │   ├── home_goals.pl
│   │   ├── consecutive_wins.pl
│   │   └── league_table.pl
│   ├── tests/                       # Unit tests (see Testing section below)
│   │   ├── fixtures/                # Minimal hand-crafted fact databases
│   │   │   ├── simple_season.pl
│   │   │   ├── gd_tiebreak.pl
│   │   │   ├── h2h_pts_tiebreak.pl
│   │   │   ├── h2h_away_goals.pl
│   │   │   ├── true_tie.pl
│   │   │   └── streaks.pl
│   │   ├── test_league_table.pl
│   │   └── test_consecutive_wins.pl
│   └── main.pl                      # Loads generated/ then queries/
└── Makefile                         # generate, check, repl, query, test targets
```

---

## Development loop

```bash
make generate          # run Go generator → writes prolog/data/generated/*.pl
make check             # syntax-check: load everything and exit (zero = clean)
make repl              # interactive swipl with all facts loaded
make test              # run all unit tests (see Testing section below)
make home-goals        # example named query target
make consecutive-wins  # example named query target
make table             # print league table (default SEASON=2025; override with SEASON=2024)
```

One-off queries run directly as:
```bash
cd prolog && swipl -g "<goal>, halt" main.pl 2>/dev/null
```

---

## Key predicate reference

```prolog
match(Id, Season, Date, HomeTeam, AwayTeam, HomeGoals, AwayGoals).
%   Id       — transfermarkt_id integer (stable external key)
%   Season   — start year, e.g. 2025 = 2025/26 season
%   Date     — YYYYMMDD integer, e.g. 20260513

team(Atom).
home_win(Team, MatchId).   home_loss(Team, MatchId).   home_draw(Team, MatchId).
away_win(Team, MatchId).   away_loss(Team, MatchId).   away_draw(Team, MatchId).
match_goals(MatchId, Team, Goals).          % symmetric — works for home or away team
next_home_match(Team, MatchId1, MatchId2). % MatchId2 is next home match after MatchId1
prev_home_match(Team, MatchId1, MatchId2). % inverse
next_away_match(Team, MatchId1, MatchId2).
prev_away_match(Team, MatchId1, MatchId2).
team_season(Team, Season, Played, Won, Drawn, Lost, GF, GA, GD, Points).
%   Pre-aggregated per (team, season) — used directly by league_table/2.
```

Team names are normalised to lowercase Prolog atoms:
`"Brighton & Hove Albion"` → `brighton_and_hove_albion`
`"Arsenal FC"` → `arsenal_fc`

---

## Testing

Tests use SWI-Prolog's built-in `library(plunit)`. Run them with:

```bash
make test
```

Each test suite runs as its own `swipl` invocation so fixtures from different suites cannot contaminate each other's fact database. Exit code is non-zero on any failure — safe to use as a CI gate.

Passing output looks like:
```
% PL-Unit: league_table ..... done
% All 5 tests passed in 0.008 seconds
```

**Test structure**

Each `test_*.pl` file is self-contained: it loads the relevant query module directly (not `main.pl`) and then consults only its own fixture files. No generated data is loaded during tests.

```
prolog/tests/
  fixtures/            ← minimal, hand-crafted fact databases
  test_league_table.pl ← loads queries/league_table + fixtures
  test_consecutive_wins.pl ← loads queries/consecutive_wins + fixtures
```

**Fixture design rules**

- Each fixture uses a fake season number (9901–9906) that cannot appear in real data, so fixture seasons never collide with each other or with generated data.
- Fixtures for `league_table` tests define `team_season/10` facts directly (pre-aggregated, not derived from match facts). Only tests that exercise H2H tiebreaking also include `match/7` facts — `h2h_result/5` reads `match/7` directly.
- Fixtures for `consecutive_wins` tests use `streak_*` atom prefixes for team names to avoid cross-contamination if both test files are ever loaded in the same session.
- Predicates that appear across multiple fixture files must be declared `:- multifile` in the test file **before** any fixture is consulted. Without this, SWI-Prolog's `consult` replaces all clauses for a predicate when a second file defines it, silently discarding the first file's facts.

**Adding a new test**

1. Create a fixture in `prolog/tests/fixtures/` with a new fake season number.
2. Add `:- multifile pred/arity.` to the test file for any predicates shared across fixtures.
3. Add a `test(name) :- ...` block that queries a specific season and pattern-matches the result list.
4. Run `make test` to confirm it passes, then `make check` to confirm `main.pl` still loads cleanly.

---

## Core architectural decisions and why

**Dates as YYYYMMDD integers, not `date(Y,M,D)` compound terms.**
Integers sort correctly under standard Prolog term order (so `msort` works for chronological ordering without any extra code), and they are valid in Datalog — compound terms are not. This was a deliberate choice to keep a future Datalog migration cheap.

**Pre-computed successor/predecessor chains (`next_home_match` etc.).**
Temporal queries in Prolog otherwise require a collect→sort→fold pipeline on every invocation. Pre-computing the chains at generation time turns each temporal hop into an O(1) fact lookup and enables clean Datalog-style recursive rules in queries:
```prolog
streak(Team, MatchId, N) :-
    home_win(Team, MatchId),
    prev_home_match(Team, PrevId, MatchId),
    streak(Team, PrevId, N0), N is N0 + 1.
```

**Pre-computed result classification (`home_win`, `home_loss`, etc.).**
Avoids arithmetic comparison (`HG > AG`) scattered across every query. Makes query rules read as pure logic. Also the kind of thing LLMs generate more reliably.

**Go for code generation.**
Fast, compiled, handles CSV/DB errors cleanly, easy to swap data sources via the `MatchSource` interface.

**`MatchSource` interface.**
The one place to change when moving from CSV to Postgres is `cmd/generate/main.go`. The `loader.NewCSVSource(...)` call becomes `loader.NewPostgresSource(...)`. Nothing downstream changes.

---

## Temporal logic — how it works in Prolog

Prolog facts are an **unordered set**. There is no native notion of time. Every temporal query requires an explicit pipeline:

1. **Collect** — `findall/3` pulls relevant facts into a list, capturing date as a value
2. **Sort** — `msort/2` imposes chronological order (YYYYMMDD integers sort correctly)
3. **Fold** — a recursive accumulator predicate walks the ordered list tracking state

```prolog
findall(Date-Outcome, (...), Pairs),  % collect
msort(Pairs, Sorted),                 % sort
pairs_values(Sorted, Results),        % strip keys
max_win_streak(Results, 0, 0, Max).  % fold
```

The pre-computed `next_home_match`/`prev_home_match` chains skip steps 1–3 for per-team sequences, since the order is already encoded in the facts.

---

## Gotchas

**Discontiguous predicate warnings.**
When multiple predicate families are interleaved in one generated file (e.g. `home_win`, `home_draw`, `home_loss` all in `results.pl`), SWI-Prolog warns unless `:- discontiguous pred/arity.` declarations appear at the top. The generator emits these automatically. If you add a new predicate family to an existing generated file, add it to the `discontiguous` list in `generator.go`.

**`max_member/2` only returns one result on a tie.**
The standard pattern for returning all joint-maximum results:
```prolog
findall(N-Info, (...), Pairs),
max_member(Max-_, Pairs),                    % find the ceiling
forall(member(Max-Info, Pairs), print(Info)). % iterate all at ceiling
```

**Cold start cost.**
Each `swipl` invocation loads ~37,000 facts from disk. This takes ~1–2 seconds. For production (live broadcast use), run SWI-Prolog as a **persistent server process** — load once at startup, then handle queries over HTTP or stdin. SWI-Prolog's `library(http/...)` stack or pengines support this. The Go layer manages the process lifecycle.

**One-off queries need inline predicate definitions.**
For ad-hoc CLI queries that need helper predicates not already in `queries/`, use `assert/1` inside the `-g` goal. The asserted clauses live only for that invocation.

**Season encoding.**
The `Season` field is the year the season starts: `2025` = 2025/26. Format for display: `S1 is (Season+1) mod 100`, then `format('~w/~w', [Season, S1])`.

**`consult` replaces all clauses for static predicates across files.**
When file B is consulted and defines a predicate already defined in file A, SWI-Prolog retracts all of file A's clauses and loads file B's — silently, with only a "Redefined static procedure" warning. This is the default for static predicates. To allow a predicate to accumulate clauses from multiple files (as in test fixtures), declare it `:- multifile pred/arity.` **before** the first `consult`. `:- dynamic` is not sufficient — SWI-Prolog still replaces clauses on consult for dynamic predicates if they were first defined by a different file.

**Anonymous variables in `findall` templates produce unbound sort keys.**
`findall(f(_,X), ..., List)` produces items where each `_` is a fresh unbound variable. If those items are then passed to `msort`, the comparison of unbound variables is by memory address — non-deterministic and not reproducible across runs. Always use named variables in `findall` templates for any term that will be compared or sorted. This was a real bug caught by the test suite: `sort_h2h` in `league_table.pl` originally used `_,_,_` for the primary sort key fields in its H2H `findall` template, causing non-deterministic tie ordering.

---

## Why Prolog over SQL

SQL with recursive CTEs and window functions can express many of these queries, but:
- Consecutive streak queries require `LAG()`/`LEAD()` + recursive CTEs — verbose and hard to compose
- Prolog rules compose naturally: `home_defeat_then_high_scoring` is two predicates joined
- LLMs generate correct Prolog queries more reliably than correct complex SQL — this matters for the NL translation layer

The one genuine weakness: Prolog has no query planner or indexes. Performance is acceptable at this dataset size (~4000 matches) but would degrade at much larger scale.

**Datalog (Souffle) as a future upgrade path.**
Souffle compiles Datalog to parallel C++ with real indexes. The rule shapes port directly from Prolog. The blockers are: no compound terms (use integers/atoms), no lists (rewrite as recursive derived facts), no `findall`/`msort` (use recursive rules + aggregation). The YYYYMMDD integer date encoding was chosen specifically to make this port cheap.

---

## Future work (not yet started)

- **Persistent swipl server** — HTTP endpoint in Go → swipl subprocess, load once, query many times
- **LLM translation layer** — natural language → Prolog query string, likely via MCP
- **Postgres data source** — implement `loader.PostgresSource` matching the `MatchSource` interface
- **Player-level data** — goals, assists, appearances per match (CSV already has enough metadata to extend)
- **Referee and venue predicates** — fields exist in the CSV, not yet generated
- **Extended query library** — head-to-head records, form tables, season summaries
