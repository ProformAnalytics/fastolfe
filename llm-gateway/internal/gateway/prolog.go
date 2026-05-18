package gateway

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
)

type PrologClient struct {
	baseURL string
	http    *http.Client
}

func NewPrologClient(baseURL string) *PrologClient {
	return &PrologClient{
		baseURL: strings.TrimRight(baseURL, "/"),
		http:    &http.Client{Timeout: 30 * time.Second},
	}
}

type queryRequest struct {
	Goal string `json:"goal"`
}

type QueryResult struct {
	Success bool   `json:"success"`
	Result  string `json:"result"`
	Error   string `json:"error"`
}

func (c *PrologClient) Query(ctx context.Context, goal string) (*QueryResult, error) {
	body, err := json.Marshal(queryRequest{Goal: goal})
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/query", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("prolog query: %w", err)
	}
	defer resp.Body.Close()

	var result QueryResult
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decode prolog response: %w", err)
	}
	return &result, nil
}

// FetchAtoms executes findall(X, predicate(X), Xs) and returns the atom list.
func (c *PrologClient) FetchAtoms(ctx context.Context, predicate string) ([]string, error) {
	goal := fmt.Sprintf("findall(X, %s(X), Xs)", predicate)
	result, err := c.Query(ctx, goal)
	if err != nil {
		return nil, err
	}
	if !result.Success {
		return nil, fmt.Errorf("fetch atoms for %s: %s", predicate, result.Error)
	}
	return parseAtomList(result.Result, predicate), nil
}

// parseAtomList extracts atom strings from a Prolog result like
// "findall(X,team(X),Xs)" → [arsenal_fc, chelsea, ...]
func parseAtomList(resultAtom, predicate string) []string {
	// The result is a Prolog term string e.g. findall(_,team(_),[arsenal_fc,chelsea,...])
	// Find the last [...] block.
	start := strings.LastIndex(resultAtom, "[")
	end := strings.LastIndex(resultAtom, "]")
	if start < 0 || end <= start {
		return nil
	}
	inner := resultAtom[start+1 : end]
	if inner == "" {
		return nil
	}
	parts := strings.Split(inner, ",")
	atoms := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			atoms = append(atoms, p)
		}
	}
	return atoms
}
