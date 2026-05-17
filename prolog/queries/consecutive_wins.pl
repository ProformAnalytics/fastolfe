:- use_module(library(lists)).
:- use_module(library(pairs)).

% outcome(+HomeGoals, +AwayGoals, -Outcome)
outcome(HG, AG, win)  :- HG > AG.
outcome(HG, AG, draw) :- HG =:= AG.
outcome(HG, AG, loss) :- HG < AG.

% home_results_by_date(+Team, -Results)
% Results is a list of win/draw/loss atoms in chronological order.
% Pipeline: collect (findall) → sort (msort) → strip keys (pairs_values).
home_results_by_date(Team, Results) :-
    findall(
        Date-Outcome,
        ( match(_, _, Date, Team, _, HG, AG),
          outcome(HG, AG, Outcome) ),
        Pairs
    ),
    msort(Pairs, Sorted),       % date(Y,M,D) terms sort correctly by standard term order
    pairs_values(Sorted, Results).

% max_consecutive_home_wins(+Team, -Streak)
max_consecutive_home_wins(Team, Streak) :-
    home_results_by_date(Team, Results),
    max_win_streak(Results, 0, 0, Streak).

% max_win_streak(+Results, +CurrentStreak, +MaxSoFar, -MaxStreak)
% Accumulator pattern: fold over the ordered list tracking current and best streak.
max_win_streak([], Cur, Max, Result) :-
    Result is max(Cur, Max).
max_win_streak([win|Rest], Cur, Max, Result) :-
    NewCur is Cur + 1,
    NewMax is max(NewCur, Max),
    max_win_streak(Rest, NewCur, NewMax, Result).
max_win_streak([H|Rest], _Cur, Max, Result) :-
    H \= win,
    max_win_streak(Rest, 0, Max, Result).

% most_consecutive_home_wins(-Team, -Streak)
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
