package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"prolog-sports/llm-gateway/internal/gateway"
)

const (
	secretPath     = "/run/secrets/anthropic_api_key"
	defaultPort    = "8081"
	defaultProlog  = "http://prolog-engine:8080"
	defaultQueries = "./prolog-engine/queries"
	startupTimeout = 30 * time.Second
)

func main() {
	apiKey, err := readSecret(secretPath)
	if err != nil {
		log.Fatalf("read API key: %v", err)
	}

	prologURL := envOr("PROLOG_ENGINE_URL", defaultProlog)
	queriesDir := envOr("PROLOG_QUERIES_DIR", defaultQueries)

	prologClient := gateway.NewPrologClient(prologURL)

	ctx, cancel := context.WithTimeout(context.Background(), startupTimeout)
	defer cancel()

	log.Printf("fetching atom lists from prolog engine at %s…", prologURL)
	teams, referees, venues, err := fetchAtoms(ctx, prologClient)
	if err != nil {
		log.Fatalf("startup atom fetch: %v", err)
	}
	log.Printf("loaded %d teams, %d referees, %d venues", len(teams), len(referees), len(venues))

	log.Printf("loading query modules from %s…", queriesDir)
	queryModules, err := gateway.LoadQueryFiles(queriesDir)
	if err != nil {
		log.Fatalf("load query files: %v", err)
	}

	systemPrompt := gateway.BuildSystemPrompt(queryModules, teams, referees, venues)
	llmClient := gateway.NewLLMClient(apiKey, systemPrompt)
	handler := gateway.NewHandler(llmClient, prologClient)

	mux := http.NewServeMux()
	handler.RegisterRoutes(mux)

	port := envOr("PORT", defaultPort)
	addr := ":" + port
	log.Printf("llm-gateway listening on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("server: %v", err)
	}
}

func fetchAtoms(ctx context.Context, c *gateway.PrologClient) (teams, referees, venues []string, err error) {
	teams, err = c.FetchAtoms(ctx, "team")
	if err != nil {
		return nil, nil, nil, fmt.Errorf("teams: %w", err)
	}
	referees, err = c.FetchAtoms(ctx, "referee")
	if err != nil {
		return nil, nil, nil, fmt.Errorf("referees: %w", err)
	}
	venues, err = c.FetchAtoms(ctx, "venue")
	if err != nil {
		return nil, nil, nil, fmt.Errorf("venues: %w", err)
	}
	return
}

func readSecret(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("read %s: %w", path, err)
	}
	key := strings.TrimSpace(string(data))
	if key == "" {
		return "", fmt.Errorf("%s is empty", path)
	}
	return key, nil
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
