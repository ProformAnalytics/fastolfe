% test_consecutive_wins.pl — unit tests for max_consecutive_home_wins/2
% and most_consecutive_home_wins/2.
%
% Tests:
%   simple_streak       — W W W → streak of 3
%   broken_streak       — W D W → streak of 1 (draw resets counter)
%   no_wins             — D only → streak of 0
%   most_wins_overall   — finds the team with the longest streak across all teams
%
% Isolation: this file is invoked as a standalone swipl session (see `make test`).
% Only the streaks fixture is loaded — no league_table fixtures, no generated data.
% home_results_by_date/2 has no season filter, so fixture isolation depends on
% separate swipl sessions rather than season scoping.

:- use_module(library(plunit)).

:- consult('../queries/consecutive_wins').

% Declare multifile so fixture facts accumulate across files.
:- multifile match/7, team/1.

:- consult('fixtures/streaks').

:- begin_tests(consecutive_wins).

% streak_a plays three home matches, all wins.
test(simple_streak) :-
    max_consecutive_home_wins(streak_a, 3).

% streak_b plays W, D, W — the draw resets the running count.
test(broken_streak) :-
    max_consecutive_home_wins(streak_b, 1).

% streak_c plays one draw and no wins.
test(no_wins) :-
    max_consecutive_home_wins(streak_c, 0).

% streak_a holds the overall maximum across all teams in the fixture.
test(most_wins_overall) :-
    most_consecutive_home_wins(streak_a, 3).

:- end_tests(consecutive_wins).
