% Generated data — produced by the Go code generator (golang/cmd/generate).
% Run `make generate` to refresh after new match data arrives.
:- consult('data/generated/matches').
:- consult('data/generated/teams').
:- consult('data/generated/results').
:- consult('data/generated/goals').
:- consult('data/generated/sequences').
:- consult('data/generated/season_stats').
:- consult('data/generated/referees').
:- consult('data/generated/venues').
:- consult('data/generated/attendance').

% Hand-authored query logic.
:- consult('queries/home_goals').
:- consult('queries/consecutive_wins').
:- consult('queries/league_table').
