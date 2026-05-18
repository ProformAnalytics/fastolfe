% Fixture: season 9904 — two teams identical on Pts/GD/GF and equal H2H points.
% Tiebreaker is H2H away goals (team_a scored more away than team_b).
%
% Results:
%   team_a home vs team_b: 1-1  (draw)  — team_b scores 1 away goal
%   team_b home vs team_a: 2-2  (draw)  — team_a scores 2 away goals
%
% H2H totals:  team_a: 2 pts, 2 away goals
%              team_b: 2 pts, 1 away goal
%
% Expected table: team_a=1, team_b=2.

% team_season(Team, Season, P, W, D, L, GF, GA, GD, Pts)
team_season(team_a, 9904, 2, 0, 2, 0, 3, 3, 0, 2).
team_season(team_b, 9904, 2, 0, 2, 0, 3, 3, 0, 2).

% match(Id, Season, Date, HomeTeam, AwayTeam, HomeGoals, AwayGoals)
match(9401, 9904, 99040101, team_a, team_b, 1, 1).
match(9402, 9904, 99040201, team_b, team_a, 2, 2).
