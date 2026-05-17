% Fixture: season 9905 — two teams identical on every tiebreaker (true tie).
% After exhausting Pts, GD, GF, H2H pts, and H2H away goals, both teams remain
% equal. msort resolves the final ordering by atom name (team_a < team_b).
%
% Results:
%   team_a home vs team_b: 1-1  (draw)  — each team scores 1 away goal
%   team_b home vs team_a: 1-1  (draw)
%
% H2H totals:  team_a: 2 pts, 1 away goal
%              team_b: 2 pts, 1 away goal
%
% Expected table: team_a=1, team_b=2 (alphabetical fallback).

% team_season(Team, Season, P, W, D, L, GF, GA, GD, Pts)
team_season(team_a, 9905, 2, 0, 2, 0, 2, 2, 0, 2).
team_season(team_b, 9905, 2, 0, 2, 0, 2, 2, 0, 2).

% match(Id, Season, Date, HomeTeam, AwayTeam, HomeGoals, AwayGoals)
match(9501, 9905, 99050101, team_a, team_b, 1, 1).
match(9502, 9905, 99050201, team_b, team_a, 1, 1).
