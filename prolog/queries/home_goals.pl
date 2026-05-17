:- use_module(library(lists)).

% team_home_goals(+Team, -TotalGoals)
% Sums goals scored at home across all matches for Team.
team_home_goals(Team, Total) :-
    team(Team),
    findall(G, match(_, _, _, Team, _, G, _), Goals),
    sum_list(Goals, Total).

% most_home_goals(-Team, -Goals)
% Finds the team with the highest aggregate home goals tally.
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
