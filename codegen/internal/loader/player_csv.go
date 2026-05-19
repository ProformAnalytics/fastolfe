package loader

import (
	"context"
	"encoding/csv"
	"fmt"
	"io"
	"os"
	"strconv"
	"time"
)

// PlayerCSVSource reads player-in-match data from the player CSV file.
type PlayerCSVSource struct {
	Path string
}

func NewPlayerCSVSource(path string) *PlayerCSVSource {
	return &PlayerCSVSource{Path: path}
}

func (s *PlayerCSVSource) LoadPlayerAppearances(_ context.Context) ([]PlayerAppearance, error) {
	f, err := os.Open(s.Path)
	if err != nil {
		return nil, fmt.Errorf("open %s: %w", s.Path, err)
	}
	defer f.Close()
	return parsePlayerCSV(f)
}

func parsePlayerCSV(r io.Reader) ([]PlayerAppearance, error) {
	cr := csv.NewReader(r)
	cr.ReuseRecord = true

	headers, err := cr.Read()
	if err != nil {
		return nil, fmt.Errorf("read header: %w", err)
	}

	idx := make(map[string]int, len(headers))
	for i, h := range headers {
		idx[h] = i
	}

	required := []string{
		"transfermarkt_id", "date", "player_id", "player_name",
		"is_home_team", "in_lineup", "is_captain",
		"main_position", "minutes_played", "goals", "assists",
		"home_team_name", "away_team_name",
	}
	for _, col := range required {
		if _, ok := idx[col]; !ok {
			return nil, fmt.Errorf("missing required column %q", col)
		}
	}

	var appearances []PlayerAppearance
	lineNum := 1
	for {
		lineNum++
		record, err := cr.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("line %d: %w", lineNum, err)
		}

		a, err := parsePlayerRow(record, idx)
		if err != nil {
			fmt.Fprintf(os.Stderr, "warn: line %d skipped: %v\n", lineNum, err)
			continue
		}
		appearances = append(appearances, a)
	}
	return appearances, nil
}

func parsePlayerRow(record []string, idx map[string]int) (PlayerAppearance, error) {
	get := func(col string) string {
		i, ok := idx[col]
		if !ok || i >= len(record) {
			return ""
		}
		return record[i]
	}

	matchID, err := strconv.ParseInt(get("transfermarkt_id"), 10, 64)
	if err != nil {
		return PlayerAppearance{}, fmt.Errorf("transfermarkt_id: %w", err)
	}

	matchDate, err := parseDateInt(get("date"))
	if err != nil {
		return PlayerAppearance{}, fmt.Errorf("date: %w", err)
	}

	playerID, err := strconv.ParseInt(get("player_id"), 10, 64)
	if err != nil {
		return PlayerAppearance{}, fmt.Errorf("player_id: %w", err)
	}

	minutes, err := strconv.Atoi(get("minutes_played"))
	if err != nil {
		return PlayerAppearance{}, fmt.Errorf("minutes_played: %w", err)
	}

	goals, err := strconv.Atoi(get("goals"))
	if err != nil {
		return PlayerAppearance{}, fmt.Errorf("goals: %w", err)
	}

	assists, err := strconv.Atoi(get("assists"))
	if err != nil {
		return PlayerAppearance{}, fmt.Errorf("assists: %w", err)
	}

	isHome := get("is_home_team") == "True"
	inLineup := get("in_lineup") == "True"
	isCaptain := get("is_captain") == "True"

	var role string
	switch {
	case inLineup:
		role = "starter"
	case minutes > 0:
		role = "sub"
	default:
		role = "bench"
	}

	teamName := get("away_team_name")
	if isHome {
		teamName = get("home_team_name")
	}

	dob := 0
	if dobStr := get("player_date_of_birth"); dobStr != "" {
		if t, e := time.Parse("2006-01-02", dobStr); e == nil {
			dob = t.Year()*10000 + int(t.Month())*100 + t.Day()
		}
	}

	return PlayerAppearance{
		MatchID:     matchID,
		MatchDate:   matchDate,
		Season:      seasonFromDate(matchDate),
		PlayerID:    playerID,
		PlayerName:  get("player_name"),
		DateOfBirth: dob,
		TeamName:    teamName,
		Role:        role,
		IsCaptain:   isCaptain,
		Position:    get("main_position"),
		Minutes:     minutes,
		Goals:       goals,
		Assists:     assists,
	}, nil
}

// seasonFromDate derives the Premier League season start year from a YYYYMMDD date.
// The PL season runs August–May: month>=8 means the season started that year.
func seasonFromDate(dateInt int) int {
	year, month := dateInt/10000, (dateInt/100)%100
	if month >= 8 {
		return year
	}
	return year - 1
}
