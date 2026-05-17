package loader

import "context"

// Match is the canonical representation of a single played football match.
// Dates are YYYYMMDD integers: straightforward to sort and compatible with
// Datalog if we ever migrate (compound terms are not valid Datalog).
type Match struct {
	ID        int64  // transfermarkt_id — stable external key
	Season    int    // e.g. 2025 for the 2025/26 season
	Date      int    // YYYYMMDD
	HomeTeam  string // raw name from source, e.g. "Arsenal FC"
	AwayTeam  string
	HomeGoals int
	AwayGoals int
	Matchday  int // 0 if not available
}

// MatchSource is the single extension point for data backends.
// Swap CSVSource for a PostgresSource when moving to production
// without touching any downstream generator code.
type MatchSource interface {
	LoadMatches(ctx context.Context) ([]Match, error)
}
