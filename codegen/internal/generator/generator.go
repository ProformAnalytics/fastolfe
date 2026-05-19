package generator

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"prolog-sports/codegen/internal/loader"
)

// Generate writes all match-level Prolog fact files to outDir.
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
			"next_home_match/3, prev_home_match/3, next_away_match/3, prev_away_match/3, next_match/3, prev_match/3",
			[]string{"next_home_match/3", "prev_home_match/3", "next_away_match/3", "prev_away_match/3", "next_match/3", "prev_match/3"},
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

// GeneratePlayers writes all player-level Prolog fact files to outDir.
func GeneratePlayers(appearances []loader.PlayerAppearance, outDir string) error {
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		return fmt.Errorf("create output dir: %w", err)
	}

	steps := []struct {
		file          string
		fn            func([]loader.PlayerAppearance, *bufio.Writer) error
		desc          string
		discontiguous []string
	}{
		{"players.pl", writePlayers,
			"player/3, player_name/2",
			[]string{"player/3", "player_name/2"},
		},
		{"player_appearances.pl", writePlayerAppearances,
			"player_appearance/5",
			nil,
		},
		{"player_stats.pl", writePlayerStats,
			"player_goals/3, player_assists/3, player_captain/2",
			[]string{"player_goals/3", "player_assists/3", "player_captain/2"},
		},
		{"player_season_stats.pl", writePlayerSeasonStats,
			"player_season/9: player_season(PlayerId, Team, Season, Appearances, Starts, Subs, Minutes, Goals, Assists)",
			nil,
		},
		{"player_sequences.pl", writePlayerSequences,
			"next_player_match/3, prev_player_match/3",
			[]string{"next_player_match/3", "prev_player_match/3"},
		},
	}

	for _, step := range steps {
		path := filepath.Join(outDir, step.file)
		if err := writeFile(path, step.desc, step.discontiguous, func(w *bufio.Writer) error {
			return step.fn(appearances, w)
		}); err != nil {
			return fmt.Errorf("%s: %w", step.file, err)
		}
		fmt.Printf("  wrote %s\n", path)
	}
	return nil
}

// ── Match-level writers ───────────────────────────────────────────────────────

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

func writeGoals(matches []loader.Match, w *bufio.Writer) error {
	for _, m := range matches {
		fmt.Fprintf(w, "match_goals(%d, %s, %d).\n", m.ID, atom(m.HomeTeam), m.HomeGoals)
		fmt.Fprintf(w, "match_goals(%d, %s, %d).\n", m.ID, atom(m.AwayTeam), m.AwayGoals)
	}
	return nil
}

func writeSequences(matches []loader.Match, w *bufio.Writer) error {
	type ref struct {
		date int
		id   int64
	}
	home := make(map[string][]ref)
	away := make(map[string][]ref)
	all := make(map[string][]ref)

	for _, m := range matches {
		h, a := atom(m.HomeTeam), atom(m.AwayTeam)
		home[h] = append(home[h], ref{m.Date, m.ID})
		away[a] = append(away[a], ref{m.Date, m.ID})
		all[h] = append(all[h], ref{m.Date, m.ID})
		all[a] = append(all[a], ref{m.Date, m.ID})
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
		emitChain(t, all[t], "next_match", "prev_match")
	}
	return nil
}

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

func writeAttendance(matches []loader.Match, w *bufio.Writer) error {
	for _, m := range matches {
		fmt.Fprintf(w, "match_attendance(%d, %d).\n", m.ID, m.Attendance)
	}
	return nil
}

// ── Player-level writers ──────────────────────────────────────────────────────

// writePlayers emits player/3 (one per unique player) and player_name/2 (name→id
// mapping; multiple clauses for shared names across different players).
func writePlayers(appearances []loader.PlayerAppearance, w *bufio.Writer) error {
	type playerInfo struct {
		name string
		dob  int
	}
	seen := make(map[int64]playerInfo)
	for _, a := range appearances {
		if _, ok := seen[a.PlayerID]; !ok {
			seen[a.PlayerID] = playerInfo{name: a.PlayerName, dob: a.DateOfBirth}
		}
	}

	ids := make([]int64, 0, len(seen))
	for id := range seen {
		ids = append(ids, id)
	}
	sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })

	for _, id := range ids {
		info := seen[id]
		fmt.Fprintf(w, "player(%d, %s, %d).\n", id, atom(info.name), info.dob)
	}
	fmt.Fprintln(w)
	for _, id := range ids {
		info := seen[id]
		fmt.Fprintf(w, "player_name(%s, %d).\n", atom(info.name), id)
	}
	return nil
}

// writePlayerAppearances emits player_appearance/5 for all rows.
func writePlayerAppearances(appearances []loader.PlayerAppearance, w *bufio.Writer) error {
	for _, a := range appearances {
		fmt.Fprintf(w, "player_appearance(%d, %d, %s, %s, %d).\n",
			a.MatchID, a.PlayerID, atom(a.TeamName), a.Role, a.Minutes)
	}
	return nil
}

// writePlayerStats emits sparse facts — only non-zero goals/assists and captain flags.
func writePlayerStats(appearances []loader.PlayerAppearance, w *bufio.Writer) error {
	for _, a := range appearances {
		if a.Goals > 0 {
			fmt.Fprintf(w, "player_goals(%d, %d, %d).\n", a.MatchID, a.PlayerID, a.Goals)
		}
	}
	fmt.Fprintln(w)
	for _, a := range appearances {
		if a.Assists > 0 {
			fmt.Fprintf(w, "player_assists(%d, %d, %d).\n", a.MatchID, a.PlayerID, a.Assists)
		}
	}
	fmt.Fprintln(w)
	for _, a := range appearances {
		if a.IsCaptain {
			fmt.Fprintf(w, "player_captain(%d, %d).\n", a.PlayerID, a.MatchID)
		}
	}
	return nil
}

// writePlayerSeasonStats emits player_season/9 — one fact per (player, team, season).
// Players who transferred mid-season get two facts (one per team).
// Appearances = starters + subs who played (minutes > 0). Bench unused excluded.
func writePlayerSeasonStats(appearances []loader.PlayerAppearance, w *bufio.Writer) error {
	type key struct {
		playerID int64
		team     string
		season   int
	}
	type stats struct {
		apps, starts, subs, minutes, goals, assists int
	}

	m := make(map[key]*stats)
	for _, a := range appearances {
		if a.Minutes == 0 {
			continue
		}
		k := key{a.PlayerID, atom(a.TeamName), a.Season}
		if m[k] == nil {
			m[k] = &stats{}
		}
		s := m[k]
		s.apps++
		s.minutes += a.Minutes
		s.goals += a.Goals
		s.assists += a.Assists
		if a.Role == "starter" {
			s.starts++
		} else {
			s.subs++
		}
	}

	keys := make([]key, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i].playerID != keys[j].playerID {
			return keys[i].playerID < keys[j].playerID
		}
		if keys[i].team != keys[j].team {
			return keys[i].team < keys[j].team
		}
		return keys[i].season < keys[j].season
	})

	for _, k := range keys {
		s := m[k]
		fmt.Fprintf(w, "player_season(%d, %s, %d, %d, %d, %d, %d, %d, %d).\n",
			k.playerID, k.team, k.season,
			s.apps, s.starts, s.subs, s.minutes, s.goals, s.assists)
	}
	return nil
}

// writePlayerSequences emits next_player_match/3 and prev_player_match/3.
// Chains are built from appearances where Minutes > 0 only.
// Bench games are excluded so consecutive-scoring queries use only actual appearances.
func writePlayerSequences(appearances []loader.PlayerAppearance, w *bufio.Writer) error {
	type ref struct {
		date    int
		matchID int64
	}

	byPlayer := make(map[int64][]ref)
	for _, a := range appearances {
		if a.Minutes == 0 {
			continue
		}
		byPlayer[a.PlayerID] = append(byPlayer[a.PlayerID], ref{a.MatchDate, a.MatchID})
	}

	playerIDs := make([]int64, 0, len(byPlayer))
	for id := range byPlayer {
		playerIDs = append(playerIDs, id)
	}
	sort.Slice(playerIDs, func(i, j int) bool { return playerIDs[i] < playerIDs[j] })

	for _, pid := range playerIDs {
		refs := byPlayer[pid]
		sort.Slice(refs, func(i, j int) bool { return refs[i].date < refs[j].date })
		for i := 1; i < len(refs); i++ {
			fmt.Fprintf(w, "next_player_match(%d, %d, %d).\n", pid, refs[i-1].matchID, refs[i].matchID)
			fmt.Fprintf(w, "prev_player_match(%d, %d, %d).\n", pid, refs[i].matchID, refs[i-1].matchID)
		}
	}
	return nil
}

// ── Shared helpers ────────────────────────────────────────────────────────────

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

// accentReplacer maps common accented/special characters to ASCII equivalents.
// Applied before the regex in atom() so player names like "Martínez" → "martinez".
// Pure stdlib — no external dependencies required.
var accentReplacer = strings.NewReplacer(
	"á", "a", "à", "a", "â", "a", "ä", "a", "ã", "a", "å", "a", "ā", "a",
	"é", "e", "è", "e", "ê", "e", "ë", "e", "ě", "e", "ē", "e",
	"í", "i", "ì", "i", "î", "i", "ï", "i", "ī", "i", "ı", "i",
	"ó", "o", "ò", "o", "ô", "o", "ö", "o", "õ", "o", "ø", "o", "ō", "o",
	"ú", "u", "ù", "u", "û", "u", "ü", "u", "ū", "u",
	"ý", "y", "ÿ", "y",
	"ñ", "n", "ń", "n", "ň", "n",
	"ç", "c", "č", "c", "ć", "c",
	"ž", "z", "ź", "z", "ż", "z",
	"š", "s", "ś", "s", "ş", "s",
	"ř", "r", "ğ", "g", "ł", "l",
	"đ", "d", "ď", "d", "ť", "t",
	"ß", "ss", "æ", "ae", "œ", "oe",
)

// atom converts a raw name to a valid unquoted Prolog atom.
func atom(name string) string {
	s := strings.ToLower(name)
	s = accentReplacer.Replace(s)
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
