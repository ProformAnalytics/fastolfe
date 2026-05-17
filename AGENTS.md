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
│   │   └── sequences.pl             # next_home_match/3, prev_home_match/3, next_away_match/3, prev_away_match/3
│   ├── queries/                     # Hand-authored query logic
│   │   ├── home_goals.pl
│   │   └── consecutive_wins.pl
│   └── main.pl                      # Loads generated/ then queries/
└── Makefile                         # generate, check, repl, query targets
```

---

## Development loop

```bash
make generate          # run Go generator → writes prolog/data/generated/*.pl
make check             # syntax-check: load everything and exit (zero = clean)
make repl              # interactive swipl with all facts loaded
make home-goals        # example named query target
make consecutive-wins  # example named query target
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
```

Team names are normalised to lowercase Prolog atoms:
`"Brighton & Hove Albion"` → `brighton_and_hove_albion`
`"Arsenal FC"` → `arsenal_fc`

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
