% player_streaks.pl — Player-level analytics: goal/assist streaks and top scorers.
%
% Streak predicates count consecutive non-bench appearances (minutes > 0) in
% which the player scored a goal or recorded an assist.
%
% Two families:
%   player_*_streak/2        — streak continues across season boundaries
%   player_season_*_streak/2 — streak resets at each season boundary
%
% Three venue filters apply to both families:
%   (no suffix) all appearances
%   home_       only matches where the player's team was the home side
%   away_       only matches where the player's team was the away side

:- use_module(library(lists)).
:- use_module(library(pairs)).
:- use_module(library(apply)).

% ── Stat check helpers ────────────────────────────────────────────────────────

has_goal(Mid, PlayerId)   :- player_goals(Mid, PlayerId, _).
has_assist(Mid, PlayerId) :- player_assists(Mid, PlayerId, _).

% ── Core streak computation ───────────────────────────────────────────────────

% pairs_to_streak(+Pairs, -MaxStreak)
% Pairs = [Date-Scored, ...]. Sorts chronologically; folds to find the longest
% consecutive run of 1s. Fails if Pairs is empty.
pairs_to_streak(Pairs, MaxStreak) :-
    Pairs \= [],
    msort(Pairs, Sorted),
    pairs_values(Sorted, Scores),
    foldl([S, C0-M0, C1-M1]>>(
        S =:= 1 -> (C1 is C0+1, M1 is max(C1,M0)) ; (C1=0, M1=M0)
    ), Scores, 0-0, _-MaxStreak).

% season_triples_to_streak(+Triples, -MaxStreak)
% Triples = [Season-Date-Scored, ...]. Sorts by season then date within season;
% resets the running streak counter whenever Season changes.
season_triples_to_streak(Triples, MaxStreak) :-
    Triples \= [],
    msort(Triples, Sorted),
    season_streak_fold(Sorted, none, 0-0, _-MaxStreak).

season_streak_fold([], _, Acc, Acc).
season_streak_fold([S-_-Scored | Rest], PrevS, C0-M0, Result) :-
    (PrevS == S -> Cur = C0 ; Cur = 0),
    (Scored =:= 1 -> C1 is Cur+1, M1 is max(C1,M0) ; C1=0, M1=M0),
    season_streak_fold(Rest, S, C1-M1, Result).

% ── Data collection helpers ───────────────────────────────────────────────────

% stat_pairs(+PlayerId, +Venue, +Stat, -Pairs)
% Venue ∈ all | home | away.  Stat ∈ has_goal | has_assist.
% Pairs = [Date-Scored, ...] for all non-bench appearances at Venue.
stat_pairs(PlayerId, all, Stat, Pairs) :-
    findall(Date-S, (
        player_appearance(Mid, PlayerId, _, Role, _), Role \= bench,
        match(Mid, _, Date, _, _, _, _),
        (call(Stat, Mid, PlayerId) -> S=1 ; S=0)
    ), Pairs).
stat_pairs(PlayerId, home, Stat, Pairs) :-
    findall(Date-S, (
        player_appearance(Mid, PlayerId, Team, Role, _), Role \= bench,
        match(Mid, _, Date, Team, _, _, _),
        (call(Stat, Mid, PlayerId) -> S=1 ; S=0)
    ), Pairs).
stat_pairs(PlayerId, away, Stat, Pairs) :-
    findall(Date-S, (
        player_appearance(Mid, PlayerId, Team, Role, _), Role \= bench,
        match(Mid, _, Date, _, Team, _, _),
        (call(Stat, Mid, PlayerId) -> S=1 ; S=0)
    ), Pairs).

% season_stat_pairs(+PlayerId, +Venue, +Stat, -Triples)
% Triples = [Season-Date-Scored, ...] for all non-bench appearances at Venue.
season_stat_pairs(PlayerId, all, Stat, Triples) :-
    findall(Season-Date-S, (
        player_appearance(Mid, PlayerId, _, Role, _), Role \= bench,
        match(Mid, Season, Date, _, _, _, _),
        (call(Stat, Mid, PlayerId) -> S=1 ; S=0)
    ), Triples).
season_stat_pairs(PlayerId, home, Stat, Triples) :-
    findall(Season-Date-S, (
        player_appearance(Mid, PlayerId, Team, Role, _), Role \= bench,
        match(Mid, Season, Date, Team, _, _, _),
        (call(Stat, Mid, PlayerId) -> S=1 ; S=0)
    ), Triples).
season_stat_pairs(PlayerId, away, Stat, Triples) :-
    findall(Season-Date-S, (
        player_appearance(Mid, PlayerId, Team, Role, _), Role \= bench,
        match(Mid, Season, Date, _, Team, _, _),
        (call(Stat, Mid, PlayerId) -> S=1 ; S=0)
    ), Triples).

% ── Across-season goal streaks ────────────────────────────────────────────────

% player_goal_streak(+PlayerId, -MaxStreak)
player_goal_streak(PlayerId, MaxStreak) :-
    stat_pairs(PlayerId, all, has_goal, Pairs),
    pairs_to_streak(Pairs, MaxStreak).

% player_home_goal_streak(+PlayerId, -MaxStreak)
player_home_goal_streak(PlayerId, MaxStreak) :-
    stat_pairs(PlayerId, home, has_goal, Pairs),
    pairs_to_streak(Pairs, MaxStreak).

% player_away_goal_streak(+PlayerId, -MaxStreak)
player_away_goal_streak(PlayerId, MaxStreak) :-
    stat_pairs(PlayerId, away, has_goal, Pairs),
    pairs_to_streak(Pairs, MaxStreak).

% ── Within-season goal streaks ────────────────────────────────────────────────

% player_season_goal_streak(+PlayerId, -MaxStreak)
player_season_goal_streak(PlayerId, MaxStreak) :-
    season_stat_pairs(PlayerId, all, has_goal, Triples),
    season_triples_to_streak(Triples, MaxStreak).

% player_season_home_goal_streak(+PlayerId, -MaxStreak)
player_season_home_goal_streak(PlayerId, MaxStreak) :-
    season_stat_pairs(PlayerId, home, has_goal, Triples),
    season_triples_to_streak(Triples, MaxStreak).

% player_season_away_goal_streak(+PlayerId, -MaxStreak)
player_season_away_goal_streak(PlayerId, MaxStreak) :-
    season_stat_pairs(PlayerId, away, has_goal, Triples),
    season_triples_to_streak(Triples, MaxStreak).

% ── Across-season assist streaks ──────────────────────────────────────────────

% player_assist_streak(+PlayerId, -MaxStreak)
player_assist_streak(PlayerId, MaxStreak) :-
    stat_pairs(PlayerId, all, has_assist, Pairs),
    pairs_to_streak(Pairs, MaxStreak).

% player_home_assist_streak(+PlayerId, -MaxStreak)
player_home_assist_streak(PlayerId, MaxStreak) :-
    stat_pairs(PlayerId, home, has_assist, Pairs),
    pairs_to_streak(Pairs, MaxStreak).

% player_away_assist_streak(+PlayerId, -MaxStreak)
player_away_assist_streak(PlayerId, MaxStreak) :-
    stat_pairs(PlayerId, away, has_assist, Pairs),
    pairs_to_streak(Pairs, MaxStreak).

% ── Within-season assist streaks ──────────────────────────────────────────────

% player_season_assist_streak(+PlayerId, -MaxStreak)
player_season_assist_streak(PlayerId, MaxStreak) :-
    season_stat_pairs(PlayerId, all, has_assist, Triples),
    season_triples_to_streak(Triples, MaxStreak).

% player_season_home_assist_streak(+PlayerId, -MaxStreak)
player_season_home_assist_streak(PlayerId, MaxStreak) :-
    season_stat_pairs(PlayerId, home, has_assist, Triples),
    season_triples_to_streak(Triples, MaxStreak).

% player_season_away_assist_streak(+PlayerId, -MaxStreak)
player_season_away_assist_streak(PlayerId, MaxStreak) :-
    season_stat_pairs(PlayerId, away, has_assist, Triples),
    season_triples_to_streak(Triples, MaxStreak).

% ── Best across all players ───────────────────────────────────────────────────

% best_player_goal_streak(-PlayerId, -MaxStreak)
best_player_goal_streak(PlayerId, MaxStreak) :-
    findall(S-P, (player(P, _, _), player_goal_streak(P, S), S > 0), Pairs),
    max_member(MaxStreak-PlayerId, Pairs).

% best_player_assist_streak(-PlayerId, -MaxStreak)
best_player_assist_streak(PlayerId, MaxStreak) :-
    findall(S-P, (player(P, _, _), player_assist_streak(P, S), S > 0), Pairs),
    max_member(MaxStreak-PlayerId, Pairs).

% ── Season aggregates ─────────────────────────────────────────────────────────

% top_scorers(+Season, -Pairs)
% Pairs = [Goals-PlayerId-TeamAtom, ...] descending. Season = start year.
top_scorers(Season, Sorted) :-
    findall(G-P-T, (player_season(P, T, Season, _, _, _, _, G, _), G > 0), Raw),
    sort(0, @>=, Raw, Sorted).

% top_n_scorers(+Season, +N, -TopN)
top_n_scorers(Season, N, TopN) :-
    top_scorers(Season, All),
    length(TopN, N),
    append(TopN, _, All).

% top_assisters(+Season, -Pairs)
% Pairs = [Assists-PlayerId-TeamAtom, ...] descending.
top_assisters(Season, Sorted) :-
    findall(A-P-T, (player_season(P, T, Season, _, _, _, _, _, A), A > 0), Raw),
    sort(0, @>=, Raw, Sorted).

% player_season_goals(+PlayerId, +Season, -TotalGoals)
% Sums across teams for mid-season transfers.
player_season_goals(PlayerId, Season, TotalGoals) :-
    findall(G, player_season(PlayerId, _, Season, _, _, _, _, G, _), Gs),
    sumlist(Gs, TotalGoals).

% player_career_goals(+PlayerId, -TotalGoals)
player_career_goals(PlayerId, TotalGoals) :-
    findall(G, player_season(PlayerId, _, _, _, _, _, _, G, _), Gs),
    sumlist(Gs, TotalGoals).

% player_career_assists(+PlayerId, -TotalAssists)
player_career_assists(PlayerId, TotalAssists) :-
    findall(A, player_season(PlayerId, _, _, _, _, _, _, _, A), As),
    sumlist(As, TotalAssists).
