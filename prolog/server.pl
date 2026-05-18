:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_json)).

:- consult('data/generated/matches').
:- consult('data/generated/teams').
:- consult('data/generated/results').
:- consult('data/generated/goals').
:- consult('data/generated/sequences').
:- consult('data/generated/season_stats').
:- consult('data/generated/referees').
:- consult('data/generated/venues').
:- consult('data/generated/attendance').

:- consult('queries/home_goals').
:- consult('queries/consecutive_wins').
:- consult('queries/league_table').

:- http_handler('/health', handle_health, [methods([get])]).
:- http_handler('/query',  handle_query,  [methods([post])]).

handle_health(_Request) :-
    reply_json_dict(_{status: ok}).

handle_query(Request) :-
    http_read_json_dict(Request, Body, []),
    term_to_atom(Goal, Body.goal),
    catch(
        (   Goal
        ->  term_to_atom(Goal, ResultAtom),
            reply_json_dict(_{success: true, result: ResultAtom})
        ;   reply_json_dict(_{success: false, error: "Goal failed"})
        ),
        Error,
        ( term_to_atom(Error, ErrAtom),
          reply_json_dict(_{success: false, error: ErrAtom}) )
    ).

:- initialization(main, main).

main :-
    http_server(http_dispatch, [port(8080)]),
    format("Prolog engine running on :8080~n"),
    thread_get_message(_).
