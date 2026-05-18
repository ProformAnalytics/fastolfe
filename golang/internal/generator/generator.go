package generator

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"prolog-sports/gen/internal/loader"
)

// Generate writes all Prolog fact files to outDir.
// Each file contains a single family of predicates, making it easy
// to extend with new predicate types without touching existing files.
func Generate(matches []loader.Match, outDir string) error {
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		return fmt.Errorf("create output dir: %w", err)
	}

	steps := []struct {
		file          string
		fn            func([]loader.Match, *bufio.Writer) error
		desc          string
		discontiguous []string
	}{
		{"matches.pl", writeMatches, "match/7", nil},
		{"teams.pl", writeTeams, "team/1", nil},
		{"results.pl", writeResults,
			"home_win/2, home_draw/2, home_loss/2, away_win/2, away_draw/2, away_loss/2",
			[]string{"home_win/2", "home_draw/2", "home_loss/2", "away_win/2", "away_draw/2", "away_loss/2"},
		},
		{"goals.pl", writeGoals, "match_goals/3", nil},
		{"sequences.pl", writeSequences,
			"next_home_match/3, prev_home_match/3, next_away_match/3, prev_away_match/3",
			[]string{"next_home_match/3", "prev_home_match/3", "next_away_match/3", "prev_away_match/3"},
		},
		{"season_stats.pl", writeSeasonStats,
			"team_season/10: team_season(Team, Season, Played, Won, Drawn, Lost, GF, GA, GD, Points)",
			nil,
		},
		{"referees.pl", writeReferees, "referee/1, match_referee/2", nil},
		{"venues.pl", writeVenues, "venue/1, match_venue/2", nil},
		{"attendance.pl", writeAttendance, "match_attendance/2", nil},
	}

	for _, step := range steps {
		path := filepath.Join(outDir, step.file)
		if err := writeFile(path, step.desc, step.discontiguous, func(w *bufio.Writer) error {
			return step.fn(matches, w)
		}); err != nil {
			return fmt.Errorf("%s: %w", step.file, err)
		}
		fmt.Printf("  wrote %s\n", path)
	}
	return nil
}

// match(Id, Season, Date, HomeTeam, AwayTeam, HomeGoals, AwayGoals).
// Date is a YYYYMMDD integer: sorts correctly and is Datalog-compatible.
func writeMatches(matches []loader.Match, w *bufio.Writer) error {
	for _, m := range matches {
		fmt.Fprintf(w, "match(%d, %d, %d, %s, %s, %d, %d).\n",
			m.ID, m.Season, m.Date,
			atom(m.HomeTeam), atom(m.AwayTeam),
			m.HomeGoals, m.AwayGoals,
		)
	}
	return nil
}

// team(TeamAtom).
func writeTeams(matches []loader.Match, w *bufio.Writer) error {
	seen := make(map[string]bool)
	for _, m := range matches {
		seen[atom(m.HomeTeam)] = true
		seen[atom(m.AwayTeam)] = true
	}
	teams := sortedKeys(seen)
	for _, t := range teams {
		fmt.Fprintf(w, "team(%s).\n", t)
	}
	return nil
}

// home_win(Team, MatchId), home_draw(...), home_loss(...),
// away_win(Team, MatchId), away_draw(...), away_loss(...).
// Pre-classifying results avoids repeated arithmetic in every query.
func writeResults(matches []loader.Match, w *bufio.Writer) error {
	for _, m := range matches {
		home := atom(m.HomeTeam)
		away := atom(m.AwayTeam)
		switch {
		case m.HomeGoals > m.AwayGoals:
			fmt.Fprintf(w, "home_win(%s, %d).\n", home, m.ID)
			fmt.Fprintf(w, "away_loss(%s, %d).\n", away, m.ID)
		case m.HomeGoals < m.AwayGoals:
			fmt.Fprintf(w, "home_loss(%s, %d).\n", home, m.ID)
			fmt.Fprintf(w, "away_win(%s, %d).\n", away, m.ID)
		default:
			fmt.Fprintf(w, "home_draw(%s, %d).\n", home, m.ID)
			fmt.Fprintf(w, "away_draw(%s, %d).\n", away, m.ID)
		}
	}
	return nil
}

// match_goals(MatchId, Team, Goals).
// Symmetric view: both teams accessible by the same predicate.
func writeGoals(matches []loader.Match, w *bufio.Writer) error {
	for _, m := range matches {
		fmt.Fprintf(w, "match_goals(%d, %s, %d).\n", m.ID, atom(m.HomeTeam), m.HomeGoals)
		fmt.Fprintf(w, "match_goals(%d, %s, %d).\n", m.ID, atom(m.AwayTeam), m.AwayGoals)
	}
	return nil
}

// next_home_match(Team, MatchId1, MatchId2) — MatchId2 is the next home match after MatchId1.
// prev_home_match(Team, MatchId1, MatchId2) — MatchId2 is the previous home match before MatchId1.
// Same for away. Pre-computing these successor chains enables Datalog-style recursive
// streak queries without findall+sort overhead at query time.
func writeSequences(matches []loader.Match, w *bufio.Writer) error {
	type ref struct {
		date int
		id   int64
	}
	home := make(map[string][]ref)
	away := make(map[string][]ref)

	for _, m := range matches {
		h, a := atom(m.HomeTeam), atom(m.AwayTeam)
		home[h] = append(home[h], ref{m.Date, m.ID})
		away[a] = append(away[a], ref{m.Date, m.ID})
	}

	sortRefs := func(refs []ref) {
		sort.Slice(refs, func(i, j int) bool { return refs[i].date < refs[j].date })
	}

	emitChain := func(team string, refs []ref, nextPred, prevPred string) {
		sortRefs(refs)
		for i := 1; i < len(refs); i++ {
			fmt.Fprintf(w, "%s(%s, %d, %d).\n", nextPred, team, refs[i-1].id, refs[i].id)
			fmt.Fprintf(w, "%s(%s, %d, %d).\n", prevPred, team, refs[i].id, refs[i-1].id)
		}
	}

	for _, t := range sortedKeys(home) {
		emitChain(t, home[t], "next_home_match", "prev_home_match")
		emitChain(t, away[t], "next_away_match", "prev_away_match")
	}
	return nil
}

// team_season(Team, Season, Played, Won, Drawn, Lost, GF, GA, GD, Points).
// One fact per (team, season). All stats pre-aggregated so league table queries
// are a single sort over facts with no arithmetic at query time.
func writeSeasonStats(matches []loader.Match, w *bufio.Writer) error {
	type stats struct {
		played, won, drawn, lost int
		gf, ga                   int
	}
	type key struct {
		team   string
		season int
	}

	m := make(map[key]*stats)
	for _, match := range matches {
		h, a := atom(match.HomeTeam), atom(match.AwayTeam)
		hk, ak := key{h, match.Season}, key{a, match.Season}
		if m[hk] == nil {
			m[hk] = &stats{}
		}
		if m[ak] == nil {
			m[ak] = &stats{}
		}
		hs, as := m[hk], m[ak]
		hs.played++
		as.played++
		hs.gf += match.HomeGoals
		hs.ga += match.AwayGoals
		as.gf += match.AwayGoals
		as.ga += match.HomeGoals
		switch {
		case match.HomeGoals > match.AwayGoals:
			hs.won++
			as.lost++
		case match.HomeGoals < match.AwayGoals:
			hs.lost++
			as.won++
		default:
			hs.drawn++
			as.drawn++
		}
	}

	keys := make([]key, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i].team != keys[j].team {
			return keys[i].team < keys[j].team
		}
		return keys[i].season < keys[j].season
	})

	for _, k := range keys {
		s := m[k]
		gd := s.gf - s.ga
		pts := s.won*3 + s.drawn
		fmt.Fprintf(w, "team_season(%s, %d, %d, %d, %d, %d, %d, %d, %d, %d).\n",
			k.team, k.season, s.played, s.won, s.drawn, s.lost, s.gf, s.ga, gd, pts)
	}
	return nil
}

// referee(RefereeAtom).
// match_referee(MatchId, RefereeAtom).
func writeReferees(matches []loader.Match, w *bufio.Writer) error {
	seen := make(map[string]bool)
	for _, m := range matches {
		if m.Referee != "" {
			seen[atom(m.Referee)] = true
		}
	}
	for _, r := range sortedKeys(seen) {
		fmt.Fprintf(w, "referee(%s).\n", r)
	}
	fmt.Fprintln(w)
	for _, m := range matches {
		if m.Referee != "" {
			fmt.Fprintf(w, "match_referee(%d, %s).\n", m.ID, atom(m.Referee))
		}
	}
	return nil
}

// venue(VenueAtom).
// match_venue(MatchId, VenueAtom).
func writeVenues(matches []loader.Match, w *bufio.Writer) error {
	seen := make(map[string]bool)
	for _, m := range matches {
		if m.Venue != "" {
			seen[atom(m.Venue)] = true
		}
	}
	for _, v := range sortedKeys(seen) {
		fmt.Fprintf(w, "venue(%s).\n", v)
	}
	fmt.Fprintln(w)
	for _, m := range matches {
		if m.Venue != "" {
			fmt.Fprintf(w, "match_venue(%d, %s).\n", m.ID, atom(m.Venue))
		}
	}
	return nil
}

// match_attendance(MatchId, Attendance).
func writeAttendance(matches []loader.Match, w *bufio.Writer) error {
	for _, m := range matches {
		fmt.Fprintf(w, "match_attendance(%d, %d).\n", m.ID, m.Attendance)
	}
	return nil
}

// writeFile creates path and calls fn with a buffered writer.
// discontiguous lists predicate indicators (e.g. "home_win/2") that need
// :- discontiguous declarations because their clauses are interleaved.
func writeFile(path, predicates string, discontiguous []string, fn func(*bufio.Writer) error) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()

	w := bufio.NewWriter(f)
	fmt.Fprintf(w, "%% Generated by prolog-sports codegen — do not edit by hand.\n")
	fmt.Fprintf(w, "%% Predicates: %s\n\n", predicates)
	for _, d := range discontiguous {
		fmt.Fprintf(w, ":- discontiguous %s.\n", d)
	}
	if len(discontiguous) > 0 {
		fmt.Fprintln(w)
	}
	if err := fn(w); err != nil {
		return err
	}
	return w.Flush()
}

var nonAlnum = regexp.MustCompile(`[^a-z0-9]+`)

// atom converts a raw team name to a valid unquoted Prolog atom.
func atom(name string) string {
	s := strings.ToLower(name)
	s = strings.ReplaceAll(s, " & ", "_and_")
	s = strings.ReplaceAll(s, "&", "_and_")
	s = nonAlnum.ReplaceAllString(s, "_")
	return strings.Trim(s, "_")
}

func sortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}
