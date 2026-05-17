% Fixture: season 9906 — controlled home match sequences for streak testing.
% Uses distinct team atom prefixes (streak_*) to avoid interference with
% league_table fixtures when both test suites run in the same session.

% team/1 is required by most_consecutive_home_wins/2.
team(streak_a).
team(streak_b).
team(streak_c).

% streak_a: three consecutive home wins → max streak 3.
% match(Id, Season, Date, HomeTeam, AwayTeam, HomeGoals, AwayGoals)
match(9601, 9906, 99060101, streak_a, opp_x, 2, 0).
match(9602, 9906, 99060201, streak_a, opp_x, 1, 0).
match(9603, 9906, 99060301, streak_a, opp_x, 3, 1).

% streak_b: win, draw, win → streak resets at draw → max streak 1.
match(9611, 9906, 99060101, streak_b, opp_x, 1, 0).
match(9612, 9906, 99060201, streak_b, opp_x, 0, 0).
match(9613, 9906, 99060301, streak_b, opp_x, 2, 0).

% streak_c: one draw, no wins → max streak 0.
match(9621, 9906, 99060101, streak_c, opp_x, 0, 0).
