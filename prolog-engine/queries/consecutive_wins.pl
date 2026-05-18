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
