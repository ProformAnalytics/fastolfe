:- use_module(library(lists)).
:- use_module(library(pairs)).

% league_table(+Season, -Rows)
% Rows = ordered list of row(Pos, Team, P, W, D, L, GF, GA, GD, Pts).
% Tiebreaker order:
%   1. Points  2. GD  3. GF
%   4. H2H points among tied teams  5. H2H away goals among tied teams
%   6. True tie — arbitrary ordering preserved from step 3.
league_table(Season, Rows) :-
    findall(t(NP,NGD,NGF,Team,P,W,D,L,GF,GA,GD,Pts),
        ( team_season(Team, Season, P, W, D, L, GF, GA, GD, Pts),
          NP is -Pts, NGD is -GD, NGF is -GF ),
    All),
    msort(All, Sorted),
    resolve_groups(Sorted, Season, 1, Rows).

% resolve_groups(+PrimarySorted, +Season, +NextPos, -Rows)
resolve_groups([], _, _, []).
resolve_groups([H|T], Season, Pos, Rows) :-
    H = t(NP, NGD, NGF, _, _, _, _, _, _, _, _, _),
    take_group(NP, NGD, NGF, [H|T], Group, Rest),
    sort_h2h(Group, Season, Pos, GroupRows, Pos1),
    append(GroupRows, RestRows, Rows),
    resolve_groups(Rest, Season, Pos1, RestRows).

% take_group(+NP, +NGD, +NGF, +List, -Group, -Rest)
% Splits List into a leading run matching the primary key and the remainder.
take_group(_, _, _, [], [], []).
take_group(NP, NGD, NGF,
           [t(NP,NGD,NGF,Team,P,W,D,L,GF,GA,GD,Pts)|T],
           [t(NP,NGD,NGF,Team,P,W,D,L,GF,GA,GD,Pts)|Group], Rest) :-
    !,
    take_group(NP, NGD, NGF, T, Group, Rest).
take_group(_, _, _, Rest, [], Rest).

% sort_h2h(+Group, +Season, +Pos, -Rows, -NextPos)
% Single team: no H2H needed.
sort_h2h([Elem], _, Pos, [row(Pos,Team,P,W,D,L,GF,GA,GD,Pts)], Pos1) :-
    !,
    Elem = t(_,_,_,Team,P,W,D,L,GF,GA,GD,Pts),
    Pos1 is Pos + 1.
% Tied group: re-rank within the group by H2H stats.
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
% Computes H2H points and away goals for Team against all other teams in GroupTeams.
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
% Team is home — away goals contribution is 0.
h2h_result(Team, Opp, Season, Pts, 0) :-
    match(_, Season, _, Team, Opp, HG, AG),
    (HG > AG -> Pts = 3 ; HG =:= AG -> Pts = 1 ; Pts = 0).
% Team is away — away goals contribution is goals scored.
h2h_result(Team, Opp, Season, Pts, TeamAG) :-
    match(_, Season, _, Opp, Team, HG, TeamAG),
    (TeamAG > HG -> Pts = 3 ; TeamAG =:= HG -> Pts = 1 ; Pts = 0).

% print_league_table(+Season)
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
