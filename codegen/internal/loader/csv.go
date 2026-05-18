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

// CSVSource reads match data from a CSV file produced by the data pipeline.
type CSVSource struct {
	Path string
}

func NewCSVSource(path string) *CSVSource {
	return &CSVSource{Path: path}
}

func (s *CSVSource) LoadMatches(_ context.Context) ([]Match, error) {
	f, err := os.Open(s.Path)
	if err != nil {
		return nil, fmt.Errorf("open %s: %w", s.Path, err)
	}
	defer f.Close()
	return parseCSV(f)
}

func parseCSV(r io.Reader) ([]Match, error) {
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
		"transfermarkt_id", "season", "date",
		"home_team_name", "away_team_name",
		"score_home", "score_away",
	}
	for _, col := range required {
		if _, ok := idx[col]; !ok {
			return nil, fmt.Errorf("missing required column %q", col)
		}
	}

	var matches []Match
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

		m, err := parseRow(record, idx)
		if err != nil {
			fmt.Fprintf(os.Stderr, "warn: line %d skipped: %v\n", lineNum, err)
			continue
		}
		matches = append(matches, m)
	}
	return matches, nil
}

func parseRow(record []string, idx map[string]int) (Match, error) {
	get := func(col string) string {
		i, ok := idx[col]
		if !ok || i >= len(record) {
			return ""
		}
		return record[i]
	}

	id, err := strconv.ParseInt(get("transfermarkt_id"), 10, 64)
	if err != nil {
		return Match{}, fmt.Errorf("transfermarkt_id: %w", err)
	}

	season, err := strconv.Atoi(get("season"))
	if err != nil {
		return Match{}, fmt.Errorf("season: %w", err)
	}

	date, err := parseDateInt(get("date"))
	if err != nil {
		return Match{}, fmt.Errorf("date: %w", err)
	}

	homeGoals, err := strconv.Atoi(get("score_home"))
	if err != nil {
		return Match{}, fmt.Errorf("score_home: %w", err)
	}

	awayGoals, err := strconv.Atoi(get("score_away"))
	if err != nil {
		return Match{}, fmt.Errorf("score_away: %w", err)
	}

	matchday := 0
	if md := get("matchday"); md != "" && md != "NULL" {
		matchday, err = strconv.Atoi(md)
		if err != nil {
			return Match{}, fmt.Errorf("matchday: %w", err)
		}
	}

	attendance := 0
	if att := get("attendance"); att != "" && att != "NULL" {
		if n, e := strconv.Atoi(att); e == nil {
			attendance = n
		} else if f, e := strconv.ParseFloat(att, 64); e == nil {
			attendance = int(f)
		}
	}

	return Match{
		ID:         id,
		Season:     season,
		Date:       date,
		HomeTeam:   get("home_team_name"),
		AwayTeam:   get("away_team_name"),
		HomeGoals:  homeGoals,
		AwayGoals:  awayGoals,
		Matchday:   matchday,
		Referee:    get("referee_name"),
		Venue:      get("venue_name"),
		Attendance: attendance,
	}, nil
}

func parseDateInt(s string) (int, error) {
	t, err := time.Parse("2006-01-02 15:04:05", s)
	if err != nil {
		t, err = time.Parse("2006-01-02", s)
		if err != nil {
			return 0, fmt.Errorf("parse %q: %w", s, err)
		}
	}
	return t.Year()*10000 + int(t.Month())*100 + t.Day(), nil
}
