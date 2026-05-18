% home_goals.pl — Aggregation queries over goals scored in home matches.
%
% These predicates aggregate across ALL seasons. To restrict to a specific
% season, add a Season argument and bind it in the match/7 call.
%
% NOTE: Only goals scored as the home team are counted. For total goals
% across home and away fixtures, use team_season(Team, Season, _, _, _, _, GF, _, _, _).

:- use_module(library(lists)).

% team_home_goals(+Team, -TotalGoals)
% TotalGoals is the sum of goals scored by Team in all home matches across all seasons.
% Binds to match/7 as HomeTeam only — away goals for Team are not included.
team_home_goals(Team, Total) :-
    team(Team),
    findall(G, match(_, _, _, Team, _, G, _), Goals),
    sum_list(Goals, Total).

% most_home_goals(-Team, -Goals)
% Team is the club with the highest aggregate home goals tally across all seasons.
% Goals is that total. Uses max_member/2 over a Pts-Team keylist.
most_home_goals(Team, Goals) :-
    findall(Total-T, team_home_goals(T, Total), Pairs),
    max_member(Goals-Team, Pairs).

% print_home_goals/0 — convenience predicate for the Makefile target.
print_home_goals :-
    forall(
        team_home_goals(T, G),
        format('  ~w: ~w~n', [T, G])
    ).

print_most_home_goals :-
    most_home_goals(Team, Goals),
    format('Top home scorer: ~w (~w goals)~n', [Team, Goals]).
