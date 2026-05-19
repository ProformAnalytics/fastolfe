% consecutive_wins.pl — Home win streak analysis across all seasons.
%
% "Consecutive home wins" means successive home matches without a non-win
% result in between. The streak is NOT reset by away results — only home
% draws and home losses break it.
%
% All predicates operate across ALL seasons combined. Season boundaries do
% not reset streaks; a streak that spans the summer break is counted.
%
% Algorithm: collect (date, outcome) pairs with findall, sort by date with
% msort (chronological order), then fold the list with an accumulator that
% tracks current streak and best streak seen so far.
%
% This module uses match/7 directly rather than the precomputed
% next_home_match/3 sequences, so it is self-contained.

:- use_module(library(lists)).
:- use_module(library(pairs)).

% outcome(+HomeGoals, +AwayGoals, -Outcome)
% Maps a scoreline to win/draw/loss from the home team's perspective.
outcome(HG, AG, win)  :- HG > AG.
outcome(HG, AG, draw) :- HG =:= AG.
outcome(HG, AG, loss) :- HG < AG.

% home_results_by_date(+Team, -Results)
% Results is a list of win/draw/loss atoms for Team's home matches in
% chronological order. Uses msort (not sort) to preserve duplicates if
% two matches share a date.
% Pipeline: findall → msort → pairs_values strips the date keys.
home_results_by_date(Team, Results) :-
    findall(
        Date-Outcome,
        ( match(_, _, Date, Team, _, HG, AG),
          outcome(HG, AG, Outcome) ),
        Pairs
    ),
    msort(Pairs, Sorted),
    pairs_values(Sorted, Results).

% max_consecutive_home_wins(+Team, -Streak)
% Streak is the length of the longest consecutive home win run for Team.
max_consecutive_home_wins(Team, Streak) :-
    home_results_by_date(Team, Results),
    max_win_streak(Results, 0, 0, Streak).

% max_win_streak(+Results, +CurrentStreak, +MaxSoFar, -MaxStreak)
% Accumulator fold over the result list.
% On win: increment current streak, update max if needed.
% On draw/loss: reset current streak to 0, max is unchanged.
max_win_streak([], Cur, Max, Result) :-
    Result is max(Cur, Max).
max_win_streak([win|Rest], Cur, Max, Result) :-
    !,
    NewCur is Cur + 1,
    NewMax is max(NewCur, Max),
    max_win_streak(Rest, NewCur, NewMax, Result).
max_win_streak([_|Rest], _Cur, Max, Result) :-
    max_win_streak(Rest, 0, Max, Result).

% most_consecutive_home_wins(-Team, -Streak)
% Team is the club with the longest single home win streak across all seasons.
% Streak is the length of that streak.
most_consecutive_home_wins(Team, Streak) :-
    findall(S-T, (team(T), max_consecutive_home_wins(T, S)), Pairs),
    max_member(Streak-Team, Pairs).

print_home_win_streaks :-
    forall(
        (team(T), max_consecutive_home_wins(T, S)),
        format('  ~w: ~w~n', [T, S])
    ).

print_most_consecutive_home_wins :-
    most_consecutive_home_wins(Team, Streak),
    format('Most consecutive home wins: ~w (~w in a row)~n', [Team, Streak]).

% ── All-match win streaks (home + away combined) ──────────────────────────────
%
% Unlike the home-only predicates above, these consider every match a team
% plays — away results count and away losses/draws break the streak.

% all_results_by_date(+Team, -Results)
% Results is a list of win/draw/loss atoms for ALL of Team's matches
% in chronological order. Outcome is from Team's perspective.
all_results_by_date(Team, Results) :-
    findall(
        Date-Outcome,
        ( match(_, _, Date, Home, Away, HG, AG),
          ( Team = Home -> outcome(HG, AG, Outcome)
          ; Team = Away -> outcome(AG, HG, Outcome)
          )
        ),
        Pairs
    ),
    msort(Pairs, Sorted),
    pairs_values(Sorted, Results).

% max_consecutive_wins(+Team, -Streak)
% Longest consecutive win streak across ALL matches (home and away).
max_consecutive_wins(Team, Streak) :-
    all_results_by_date(Team, Results),
    max_win_streak(Results, 0, 0, Streak).

% most_consecutive_wins(-Team, -Streak)
% Team with the longest all-match consecutive win streak across all seasons.
most_consecutive_wins(Team, Streak) :-
    findall(S-T, (team(T), max_consecutive_wins(T, S)), Pairs),
    max_member(Streak-Team, Pairs).

% last_n_consecutive_wins(+Team, +N, -EndDate)
% EndDate (YYYYMMDD integer) of the last match in the most recent run of N or
% more consecutive wins across all matches. Fails if Team never achieved N
% consecutive wins.
last_n_consecutive_wins(Team, N, EndDate) :-
    findall(
        Date-Outcome,
        ( match(_, _, Date, Home, Away, HG, AG),
          ( Team = Home -> outcome(HG, AG, Outcome)
          ; Team = Away -> outcome(AG, HG, Outcome)
          )
        ),
        Pairs
    ),
    msort(Pairs, Sorted),
    last_streak_end(Sorted, N, 0, -1, EndDate),
    EndDate \= -1.

% last_streak_end(+Pairs, +N, +CurLen, +BestDate, -EndDate)
% Walk chronologically, tracking current streak length. Whenever streak
% reaches N, record Date as a candidate EndDate (later dates overwrite
% earlier ones, so we keep the most recent).
last_streak_end([], _, _, Best, Best).
last_streak_end([D-win|Rest], N, Cur, SoFar, End) :-
    !,
    NewCur is Cur + 1,
    ( NewCur >= N -> NewBest = D ; NewBest = SoFar ),
    last_streak_end(Rest, N, NewCur, NewBest, End).
last_streak_end([_|Rest], N, _, SoFar, End) :-
    last_streak_end(Rest, N, 0, SoFar, End).
