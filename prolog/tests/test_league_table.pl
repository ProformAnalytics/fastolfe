% test_league_table.pl — unit tests for league_table/2.
%
% Each test targets a specific code path:
%   basic_ordering     — primary sort only (Pts distinct, no ties)
%   gd_tiebreak        — two teams equal Pts, separated by GD
%   h2h_pts_tiebreak   — three teams tied on Pts/GD/GF, H2H points decides
%   h2h_away_goals     — two teams tied through H2H pts, away goals decides
%   true_tie           — exhausted all tiebreakers, alphabetical fallback
%
% Isolation: this file is invoked as a standalone swipl session (see `make test`).
% It loads only the query module and the relevant fixtures — no generated data.

:- use_module(library(plunit)).

:- consult('../queries/league_table').

% Declare multifile so facts from multiple fixture files accumulate
% rather than replacing each other on consult.
:- multifile team_season/10, match/7.

:- consult('fixtures/simple_season').
:- consult('fixtures/gd_tiebreak').
:- consult('fixtures/h2h_pts_tiebreak').
:- consult('fixtures/h2h_away_goals').
:- consult('fixtures/true_tie').

:- begin_tests(league_table).

% Season 9901: three teams with distinct points — pure primary sort.
test(basic_ordering) :-
    league_table(9901, [
        row(1, team_a, 3, 3, 0, 0,  6, 0,  6, 9),
        row(2, team_b, 3, 1, 1, 1,  3, 3,  0, 4),
        row(3, team_c, 3, 0, 0, 3,  0, 6, -6, 0)
    ]).

% Season 9902: same points, GD decides — H2H never invoked.
test(gd_tiebreak) :-
    league_table(9902, [
        row(1, team_a, 2, 1, 0, 1, 4, 1,  3, 3),
        row(2, team_b, 2, 1, 0, 1, 2, 3, -1, 3)
    ]).

% Season 9903: all three teams tied on Pts/GD/GF.
% team_a accumulates 8 H2H points vs 3 each for team_b and team_c.
% team_b and team_c are equal on H2H pts and H2H away goals — resolved
% alphabetically by msort on the underlying term.
test(h2h_pts_tiebreak) :-
    league_table(9903, [
        row(1, team_a, 10, 4, 2, 4, 14, 14, 0, 14),
        row(2, team_b, 10, 4, 2, 4, 14, 14, 0, 14),
        row(3, team_c, 10, 4, 2, 4, 14, 14, 0, 14)
    ]).

% Season 9904: two teams tied through Pts/GD/GF and H2H pts (always equal
% for two teams over two legs). team_a scored 2 away goals vs team_b's 1.
test(h2h_away_goals) :-
    league_table(9904, [
        row(1, team_a, 2, 0, 2, 0, 3, 3, 0, 2),
        row(2, team_b, 2, 0, 2, 0, 3, 3, 0, 2)
    ]).

% Season 9905: teams identical on every tiebreaker — true tie.
% Both teams appear with sequential positions; order is the msort atom fallback.
test(true_tie) :-
    league_table(9905, [
        row(1, team_a, 2, 0, 2, 0, 2, 2, 0, 2),
        row(2, team_b, 2, 0, 2, 0, 2, 2, 0, 2)
    ]).

:- end_tests(league_table).
