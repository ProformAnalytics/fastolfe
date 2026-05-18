% league_table.pl — Premier League table with full official tiebreaker rules.
%
% league_table/2 produces the exact standings you would see on the Premier
% League website. Tiebreaker priority:
%   1. Points (descending)
%   2. Goal difference (descending)
%   3. Goals for (descending)
%   4. Head-to-head points among exactly the tied teams (descending)
%   5. Head-to-head away goals among exactly the tied teams (descending)
%   6. True tie — order preserved from step 3.
%
% Rows are row/10 terms:
%   row(Pos, Team, Played, Won, Drawn, Lost, GF, GA, GD, Points)
%
% Data source: team_season/10 facts (pre-aggregated by the Go generator).
% H2H data is derived live from match/7 facts for the same season.

:- use_module(library(lists)).
:- use_module(library(pairs)).

% league_table(+Season, -Rows)
% Rows is the ordered list of row/10 terms for Season.
% Season is the start year (2025 = 2025/26, 2024 = 2024/25, etc.).
%
% Primary sort: negate Pts, GD, GF so msort ascending becomes descending.
% Ties are broken in resolve_groups/4.
league_table(Season, Rows) :-
    findall(t(NP,NGD,NGF,Team,P,W,D,L,GF,GA,GD,Pts),
        ( team_season(Team, Season, P, W, D, L, GF, GA, GD, Pts),
          NP is -Pts, NGD is -GD, NGF is -GF ),
    All),
    msort(All, Sorted),
    resolve_groups(Sorted, Season, 1, Rows).

% resolve_groups(+PrimarySorted, +Season, +NextPos, -Rows)
% Walks the primary-sorted list, splitting it into groups of teams that
% share the same (Pts, GD, GF) triple. Each group is passed to sort_h2h/5.
resolve_groups([], _, _, []).
resolve_groups([H|T], Season, Pos, Rows) :-
    H = t(NP, NGD, NGF, _, _, _, _, _, _, _, _, _),
    take_group(NP, NGD, NGF, [H|T], Group, Rest),
    sort_h2h(Group, Season, Pos, GroupRows, Pos1),
    append(GroupRows, RestRows, Rows),
    resolve_groups(Rest, Season, Pos1, RestRows).

% take_group(+NP, +NGD, +NGF, +List, -Group, -Rest)
% Splits List into a leading run of t/12 terms with matching primary key
% and the remaining terms. The cut prevents backtracking into Rest.
take_group(_, _, _, [], [], []).
take_group(NP, NGD, NGF,
           [t(NP,NGD,NGF,Team,P,W,D,L,GF,GA,GD,Pts)|T],
           [t(NP,NGD,NGF,Team,P,W,D,L,GF,GA,GD,Pts)|Group], Rest) :-
    !,
    take_group(NP, NGD, NGF, T, Group, Rest).
take_group(_, _, _, Rest, [], Rest).

% sort_h2h(+Group, +Season, +Pos, -Rows, -NextPos)
%
% Single-team group: assign position directly, no H2H needed.
sort_h2h([Elem], _, Pos, [row(Pos,Team,P,W,D,L,GF,GA,GD,Pts)], Pos1) :-
    !,
    Elem = t(_,_,_,Team,P,W,D,L,GF,GA,GD,Pts),
    Pos1 is Pos + 1.
% Multi-team group: re-rank by H2H stats among only the tied teams.
sort_h2h(Group, Season, Pos, Rows, NextPos) :-
    Group = [_,_|_],
    findall(Team, member(t(_,_,_,Team,_,_,_,_,_,_,_,_), Group), Teams),
    findall(NH-NAG-t(NP,NGD,NGF,Team,P,W,D,L,GF,GA,GD,Pts),
        ( member(t(NP,NGD,NGF,Team,P,W,D,L,GF,GA,GD,Pts), Group),
          h2h_stats(Team, Teams, Season, H2HPts, H2HAG),
          NH is -H2HPts, NAG is -H2HAG ),
    H2HKeyed),
    msort(H2HKeyed, H2HSorted),
    length(Group, Len),
    NextPos is Pos + Len,
    assign_positions(H2HSorted, Pos, Rows).

assign_positions([], _, []).
assign_positions([_-_-t(_,_,_,Team,P,W,D,L,GF,GA,GD,Pts)|Rest], Pos,
                 [row(Pos,Team,P,W,D,L,GF,GA,GD,Pts)|Rows]) :-
    Pos1 is Pos + 1,
    assign_positions(Rest, Pos1, Rows).

% h2h_stats(+Team, +GroupTeams, +Season, -H2HPts, -H2HAwayGoals)
% H2HPts: points Team earned against the other GroupTeams in Season.
% H2HAwayGoals: goals Team scored as the away side against GroupTeams.
% Only matches between teams within the tied group are counted.
h2h_stats(Team, GroupTeams, Season, TotalPts, TotalAway) :-
    findall(Pts-AG,
        ( member(Opp, GroupTeams), Opp \= Team,
          h2h_result(Team, Opp, Season, Pts, AG) ),
    Pairs),
    pairs_keys(Pairs, PtsList),
    pairs_values(Pairs, AGList),
    sum_list(PtsList, TotalPts),
    sum_list(AGList, TotalAway).

% h2h_result(+Team, +Opp, +Season, -Pts, -TeamAwayGoals)
% Two clauses: Team as home side, Team as away side.
% Home clause: Team's away goals contribution is 0 (they are at home).
h2h_result(Team, Opp, Season, Pts, 0) :-
    match(_, Season, _, Team, Opp, HG, AG),
    (HG > AG -> Pts = 3 ; HG =:= AG -> Pts = 1 ; Pts = 0).
% Away clause: away goals are the goals Team scored at Opp's ground.
h2h_result(Team, Opp, Season, Pts, TeamAG) :-
    match(_, Season, _, Opp, Team, HG, TeamAG),
    (TeamAG > HG -> Pts = 3 ; TeamAG =:= HG -> Pts = 1 ; Pts = 0).

% print_league_table(+Season) — convenience predicate for the Makefile target.
print_league_table(Season) :-
    league_table(Season, Rows),
    S1 is (Season + 1) mod 100,
    format('~n~w/~w Premier League~n', [Season, S1]),
    format('Pos  Team                           P  W  D  L  GF  GA  GD  Pts~n'),
    format('--------------------------------------------------------------~n'),
    forall(
        member(row(Pos,Team,P,W,D,L,GF,GA,GD,Pts), Rows),
        format('~t~d~3|  ~w~t~32|~t~d~35|~t~d~38|~t~d~41|~t~d~44|~t~d~49|~t~d~54|~t~d~59|~t~d~63|~n',
            [Pos,Team,P,W,D,L,GF,GA,GD,Pts])
    ).
