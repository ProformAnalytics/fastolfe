% Fixture: season 9902 — two teams equal on points, separated by goal difference.
% H2H tiebreaking is never invoked because GD already differentiates them.
% Expected table: team_a (GD +3) > team_b (GD -1).

% team_season(Team, Season, P, W, D, L, GF, GA, GD, Pts)
team_season(team_a, 9902, 2, 1, 0, 1,  4, 1,  3, 3).
team_season(team_b, 9902, 2, 1, 0, 1,  2, 3, -1, 3).
