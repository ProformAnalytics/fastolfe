package loader

import "context"

// Match is the canonical representation of a single played football match.
// Dates are YYYYMMDD integers: straightforward to sort and compatible with
// Datalog if we ever migrate (compound terms are not valid Datalog).
type Match struct {
	ID         int64  // transfermarkt_id — stable external key
	Season     int    // e.g. 2025 for the 2025/26 season
	Date       int    // YYYYMMDD
	HomeTeam   string // raw name from source, e.g. "Arsenal FC"
	AwayTeam   string
	HomeGoals  int
	AwayGoals  int
	Matchday   int    // 0 if not available
	Referee    string // referee_name from source, empty if not available
	Venue      string // venue_name from source, empty if not available
	Attendance int    // 0 if not available
}

// MatchSource is the single extension point for data backends.
// Swap CSVSource for a PostgresSource when moving to production
// without touching any downstream generator code.
type MatchSource interface {
	LoadMatches(ctx context.Context) ([]Match, error)
}

// PlayerAppearance is one player's record in one match (started, subbed on,
// or listed on the bench but unused). All 158k rows of the player CSV map to
// one struct each.
type PlayerAppearance struct {
	MatchID     int64
	MatchDate   int    // YYYYMMDD
	Season      int    // derived from date: month>=8 → year, else year-1
	PlayerID    int64
	PlayerName  string // raw UTF-8 name from source
	DateOfBirth int    // YYYYMMDD; 0 if missing or unparseable
	TeamName    string // team the player represented (home or away team name)
	Role        string // "starter" | "sub" | "bench"
	IsCaptain   bool
	Position    string // main_position value from source
	Minutes     int
	Goals       int
	Assists     int
}

// PlayerAppearanceSource is the extension point for player data backends.
type PlayerAppearanceSource interface {
	LoadPlayerAppearances(ctx context.Context) ([]PlayerAppearance, error)
}

