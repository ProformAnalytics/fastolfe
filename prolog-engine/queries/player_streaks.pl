% player_streaks.pl — Player-level analytics: goal streaks and top scorers.
%
% Algorithm: the foldl streak pattern (same as consecutive_wins.pl).
% Collect ALL played appearances (minutes > 0) with a 1/0 scored flag,
% sort chronologically, then fold to find the longest consecutive run of 1s.
% Bench games are excluded — they are not "appearances" for streak purposes.

:- use_module(library(lists)).
:- use_module(library(pairs)).
:- use_module(library(apply)).

% player_goal_streak(+PlayerId, -MaxStreak)
% MaxStreak is the length of the longest run of consecutive played appearances
% (minutes > 0) in which PlayerId scored at least one goal.
% Fails if PlayerId has no qualifying appearances.
player_goal_streak(PlayerId, MaxStreak) :-
    findall(
        Date-Scored,
        ( player_appearance(Mid, PlayerId, _, Role, _),
          Role \= bench,
          match(Mid, _, Date, _, _, _, _),
          ( player_goals(Mid, PlayerId, _) -> Scored = 1 ; Scored = 0 )
        ),
        Pairs
    ),
    Pairs \= [],
    msort(Pairs, Sorted),
    pairs_values(Sorted, Scores),
    foldl(
        [S, C0-M0, C1-M1]>>(
            S =:= 1
            -> ( C1 is C0 + 1, M1 is max(C1, M0) )
            ;  ( C1 = 0, M1 = M0 )
        ),
        Scores, 0-0, _-MaxStreak
    ).

% best_player_goal_streak(-PlayerId, -MaxStreak)
% The player with the longest individual goal-scoring streak across all seasons.
best_player_goal_streak(PlayerId, MaxStreak) :-
    findall(S-P, (player(P, _, _), player_goal_streak(P, S), S > 0), Pairs),
    max_member(MaxStreak-PlayerId, Pairs).

% top_scorers(+Season, -Pairs)
% Pairs = [Goals-PlayerId-TeamAtom, ...] in descending goal order.
% Season is the start year (e.g. 2024 for 2024/25).
% Players who transferred mid-season appear once per team — sum manually if needed.
top_scorers(Season, Sorted) :-
    findall(
        G-P-T,
        ( player_season(P, T, Season, _, _, _, _, G, _), G > 0 ),
        Raw
    ),
    sort(0, @>=, Raw, Sorted).

% top_n_scorers(+Season, +N, -TopN)
% TopN is the first N elements of top_scorers for Season.
top_n_scorers(Season, N, TopN) :-
    top_scorers(Season, All),
    length(TopN, N),
    append(TopN, _, All).

% player_season_goals(+PlayerId, +Season, -TotalGoals)
% TotalGoals across all teams for PlayerId in Season.
% (Handles mid-season transfers by summing both stints.)
player_season_goals(PlayerId, Season, TotalGoals) :-
    findall(G, player_season(PlayerId, _, Season, _, _, _, _, G, _), Gs),
    sumlist(Gs, TotalGoals).

% player_career_goals(+PlayerId, -TotalGoals)
% Total Premier League goals across all seasons in the database.
player_career_goals(PlayerId, TotalGoals) :-
    findall(G, player_season(PlayerId, _, _, _, _, _, _, G, _), Gs),
    sumlist(Gs, TotalGoals).

% player_career_assists(+PlayerId, -TotalAssists)
% Total Premier League assists across all seasons in the database.
player_career_assists(PlayerId, TotalAssists) :-
    findall(A, player_season(PlayerId, _, _, _, _, _, _, _, A), As),
    sumlist(As, TotalAssists).

% top_assisters(+Season, -Pairs)
% Pairs = [Assists-PlayerId-TeamAtom, ...] descending.
top_assisters(Season, Sorted) :-
    findall(
        A-P-T,
        ( player_season(P, T, Season, _, _, _, _, _, A), A > 0 ),
        Raw
    ),
    sort(0, @>=, Raw, Sorted).
