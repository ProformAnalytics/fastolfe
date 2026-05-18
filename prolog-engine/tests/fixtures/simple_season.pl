% Fixture: season 9901 — three teams with clearly distinct points.
% No tied groups, so tiebreaking logic is never invoked.
% Expected table: team_a (9 pts) > team_b (4 pts) > team_c (0 pts).

% team_season(Team, Season, P, W, D, L, GF, GA, GD, Pts)
team_season(team_a, 9901, 3, 3, 0, 0,  6, 0,  6, 9).
team_season(team_b, 9901, 3, 1, 1, 1,  3, 3,  0, 4).
team_season(team_c, 9901, 3, 0, 0, 3,  0, 6, -6, 0).
