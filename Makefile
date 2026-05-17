SWIPL    ?= swipl
GO       ?= go
PROLOG_DIR = prolog
GEN_DIR    = golang
SEASON   ?= 2025

.PHONY: generate check repl home-goals all-home-goals consecutive-wins all-consecutive-wins table test

# Run the Go code generator. Re-run after each data update.
generate:
	cd $(GEN_DIR) && $(GO) run ./cmd/generate \
		-csv data/premier-league-data.csv \
		-out ../$(PROLOG_DIR)/data/generated

# Syntax-check: load everything and exit. Zero exit = clean.
check:
	cd $(PROLOG_DIR) && $(SWIPL) -g halt main.pl

# Drop into an interactive REPL with all facts loaded.
repl:
	cd $(PROLOG_DIR) && $(SWIPL) main.pl

# Print all teams with their home goal tallies.
all-home-goals:
	cd $(PROLOG_DIR) && $(SWIPL) -g "print_home_goals, halt" main.pl

# Print the team with the most home goals.
home-goals:
	cd $(PROLOG_DIR) && $(SWIPL) -g "print_most_home_goals, halt" main.pl

# Print each team's consecutive home win streak.
all-consecutive-wins:
	cd $(PROLOG_DIR) && $(SWIPL) -g "print_home_win_streaks, halt" main.pl

# Print the team with the longest consecutive home win streak.
consecutive-wins:
	cd $(PROLOG_DIR) && $(SWIPL) -g "print_most_consecutive_home_wins, halt" main.pl

# Print the league table for a given season (default: 2025 = 2025/26).
# Override with: make table SEASON=2024
table:
	cd $(PROLOG_DIR) && $(SWIPL) -g "print_league_table($(SEASON)), halt" main.pl 2>/dev/null

# Run all unit tests. Each suite gets its own isolated swipl session so that
# fixtures from different suites cannot contaminate each other's fact database.
test:
	cd $(PROLOG_DIR) && $(SWIPL) -g "run_tests, halt" tests/test_league_table.pl 
	cd $(PROLOG_DIR) && $(SWIPL) -g "run_tests, halt" tests/test_consecutive_wins.pl 
