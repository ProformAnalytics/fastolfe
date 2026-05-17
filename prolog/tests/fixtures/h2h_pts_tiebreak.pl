% Fixture: season 9903 — three teams identical on Pts/GD/GF, separated by H2H points.
%
% H2H match results among the group:
%   team_a home vs team_b: 2-0  (A wins)     team_a: +3 H2H pts
%   team_b home vs team_a: 0-0  (draw)        team_a: +1 H2H pt
%   team_a home vs team_c: 2-0  (A wins)     team_a: +3 H2H pts
%   team_c home vs team_a: 0-0  (draw)        team_a: +1 H2H pt
%   team_b home vs team_c: 1-1  (draw)
%   team_c home vs team_b: 1-1  (draw)
%
% H2H totals:
%   team_a: 8 pts, 0 away goals
%   team_b: 3 pts, 1 away goal  (true tie with team_c — resolved alphabetically)
%   team_c: 3 pts, 1 away goal
%
% Expected table: team_a=1, team_b=2, team_c=3.

% team_season(Team, Season, P, W, D, L, GF, GA, GD, Pts)
team_season(team_a, 9903, 10, 4, 2, 4, 14, 14, 0, 14).
team_season(team_b, 9903, 10, 4, 2, 4, 14, 14, 0, 14).
team_season(team_c, 9903, 10, 4, 2, 4, 14, 14, 0, 14).

% match(Id, Season, Date, HomeTeam, AwayTeam, HomeGoals, AwayGoals)
match(9301, 9903, 99030101, team_a, team_b, 2, 0).
match(9302, 9903, 99030201, team_b, team_a, 0, 0).
match(9303, 9903, 99030301, team_a, team_c, 2, 0).
match(9304, 9903, 99030401, team_c, team_a, 0, 0).
match(9305, 9903, 99030501, team_b, team_c, 1, 1).
match(9306, 9903, 99030601, team_c, team_b, 1, 1).
