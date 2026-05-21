% league_table_on.pl — Premier League table as of a specific date.
%
% league_table_on/2 computes standings by aggregating match/7 facts directly,
% filtered to all matches played on or before the given date. Unlike
% league_table/2 (which reads pre-aggregated team_season/10 facts and covers a
% full season), this works for any mid-season snapshot.
%
% Season is derived automatically from the date using the same rule as the
% Go codegen: month >= 8 → season = year; month < 8 → season = year - 1.
%
% Tiebreaker order: Points → GD → GF → alphabetical.
% H2H tiebreakers are intentionally omitted — they are only meaningful for
% final standings when two teams finish the season level on all three primary
% criteria.
%
% Row format (identical to league_table/2):
%   row(Pos, Team, Played, Won, Drawn, Lost, GF, GA, GD, Points)

:- use_module(library(lists)).
:- use_module(library(apply)).

% league_table_on(+Date, -Rows)
% Date is a YYYYMMDD integer. All matches on or before Date are included.
league_table_on(Date, Rows) :-
    date_to_season(Date, Season),
    findall(T,
        ( match(_, Season, D, H, A, _, _), D =< Date,
          (T = H ; T = A) ),
        Teams0),
    sort(Teams0, Teams),
    findall(
        k(NP, NGD, NGF, Team)-row(Team, Played, Won, Drawn, Lost, GF, GA, GD, Pts),
        ( member(Team, Teams),
          team_record_on(Team, Season, Date, Played, Won, Drawn, Lost, GF, GA),
          GD  is GF - GA,
          Pts is Won * 3 + Drawn,
          NP  is -Pts,
          NGD is -GD,
          NGF is -GF ),
        Keyed),
    msort(Keyed, Sorted),
    assign_positions_on(Sorted, 1, Rows).

% date_to_season(+Date, -Season)
date_to_season(Date, Season) :-
    Year  is Date // 10000,
    Month is (Date // 100) mod 100,
    (Month >= 8 -> Season = Year ; Season is Year - 1).

% team_record_on(+Team, +Season, +Date, -Played, -Won, -Drawn, -Lost, -GF, -GA)
% All match results are expressed from Team's perspective (scored, conceded).
team_record_on(Team, Season, Date, Played, Won, Drawn, Lost, GF, GA) :-
    findall(HG-AG,
        ( match(_, Season, D, Team, _, HG, AG), D =< Date ),
        HomeMatches),
    % Away: flip so the pair is always scored-conceded from Team's view.
    findall(AG-HG,
        ( match(_, Season, D, _, Team, HG, AG), D =< Date ),
        AwayMatches),
    append(HomeMatches, AwayMatches, AllMatches),
    length(AllMatches, Played),
    foldl(tally_result, AllMatches, 0-0-0-0-0, Won-Drawn-Lost-GF-GA).

% tally_result(+Scored-Conceded, +Acc, -Acc1)
tally_result(Scored-Conceded, W0-D0-L0-GF0-GA0, W1-D1-L1-GF1-GA1) :-
    GF1 is GF0 + Scored,
    GA1 is GA0 + Conceded,
    (   Scored > Conceded   -> W1 is W0 + 1, D1 = D0,       L1 = L0
    ;   Scored =:= Conceded -> W1 = W0,       D1 is D0 + 1, L1 = L0
    ;                          W1 = W0,       D1 = D0,       L1 is L0 + 1
    ).

assign_positions_on([], _, []).
assign_positions_on([_-row(Team, P, W, D, L, GF, GA, GD, Pts) | Rest], Pos,
                    [row(Pos, Team, P, W, D, L, GF, GA, GD, Pts) | Rows]) :-
    Pos1 is Pos + 1,
    assign_positions_on(Rest, Pos1, Rows).

% print_league_table_on(+Date) — convenience predicate for manual testing.
print_league_table_on(Date) :-
    league_table_on(Date, Rows),
    date_to_season(Date, Season),
    S1 is (Season + 1) mod 100,
    format('~n~w/~w Premier League — as of ~w~n', [Season, S1, Date]),
    format('Pos  Team                           P  W  D  L  GF  GA  GD  Pts~n'),
    format('--------------------------------------------------------------~n'),
    forall(
        member(row(Pos, Team, P, W, D, L, GF, GA, GD, Pts), Rows),
        format('~t~d~3|  ~w~t~32|~t~d~35|~t~d~38|~t~d~41|~t~d~44|~t~d~49|~t~d~54|~t~d~59|~t~d~63|~n',
            [Pos, Team, P, W, D, L, GF, GA, GD, Pts])
    ).
