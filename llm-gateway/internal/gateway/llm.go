package gateway

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	_ "embed"

	"github.com/anthropics/anthropic-sdk-go"
	"github.com/anthropics/anthropic-sdk-go/option"
)

//go:embed prompt.md
var promptTemplate string

// queryFiles lists the hand-authored query files passed verbatim to the LLM.
// Order matters: simpler predicates first so the LLM sees building blocks before
// the complex ones that depend on them.
var queryFiles = []string{
	"home_goals.pl",
	"consecutive_wins.pl",
	"league_table.pl",
}

// LoadQueryFiles reads the hand-authored Prolog query files from dir and
// returns them formatted as a single block for injection into the system prompt.
// Only the small, hand-authored files are included — generated data files are
// described via examples in prompt.md, not passed verbatim.
func LoadQueryFiles(dir string) (string, error) {
	var sb strings.Builder
	for _, name := range queryFiles {
		path := filepath.Join(dir, name)
		data, err := os.ReadFile(path)
		if err != nil {
			return "", fmt.Errorf("read query file %s: %w", name, err)
		}
		fmt.Fprintf(&sb, "### %s\n```prolog\n%s\n```\n\n", name, strings.TrimSpace(string(data)))
	}
	return strings.TrimSpace(sb.String()), nil
}

// BuildSystemPrompt constructs the final system prompt by injecting:
//   - queryModules: content from LoadQueryFiles
//   - teams, referees, venues: atom lists fetched from the Prolog engine at startup
func BuildSystemPrompt(queryModules string, teams, referees, venues []string) string {
	prompt := promptTemplate
	prompt = strings.ReplaceAll(prompt, "%QUERY_MODULES%", queryModules)
	prompt = strings.ReplaceAll(prompt, "%TEAMS%", formatAtomList(teams))
	prompt = strings.ReplaceAll(prompt, "%REFEREES%", formatAtomList(referees))
	prompt = strings.ReplaceAll(prompt, "%VENUES%", formatAtomList(venues))
	return prompt
}

func formatAtomList(atoms []string) string {
	if len(atoms) == 0 {
		return "(none loaded)"
	}
	return strings.Join(atoms, ", ")
}

type LLMClient struct {
	client       anthropic.Client
	systemPrompt string
}

func NewLLMClient(apiKey string, systemPrompt string) *LLMClient {
	return &LLMClient{
		client:       anthropic.NewClient(option.WithAPIKey(apiKey)),
		systemPrompt: systemPrompt,
	}
}

// TranslateToProlog converts a natural language question into a Prolog goal string.
// priorError, if non-empty, is appended so Claude can self-correct a previously
// failed goal without losing the original question context.
func (c *LLMClient) TranslateToProlog(ctx context.Context, question, priorError string) (string, error) {
	messages := []anthropic.MessageParam{
		anthropic.NewUserMessage(anthropic.NewTextBlock(question)),
	}
	if priorError != "" {
		messages = append(messages,
			anthropic.NewAssistantMessage(anthropic.NewTextBlock("(previous goal attempt)")),
			anthropic.NewUserMessage(anthropic.NewTextBlock(
				fmt.Sprintf("That goal failed with this error: %s\nPlease return a corrected goal.", priorError),
			)),
		)
	}

	resp, err := c.client.Messages.New(ctx, anthropic.MessageNewParams{
		Model:     anthropic.ModelClaudeOpus4_7,
		MaxTokens: 300,
		System: []anthropic.TextBlockParam{{
			Text:         c.systemPrompt,
			CacheControl: anthropic.NewCacheControlEphemeralParam(),
		}},
		Messages: messages,
	})
	if err != nil {
		return "", fmt.Errorf("LLM translate: %w", err)
	}

	return extractText(resp.Content), nil
}

// FormatAnswer converts a raw Prolog result into a natural language response.
func (c *LLMClient) FormatAnswer(ctx context.Context, question, prologResult string) (string, error) {
	userMsg := fmt.Sprintf(
		"Question: %s\n\nProlog result: %s\n\nAnswer the question naturally based on the result. Be concise. Format team names properly (e.g. arsenal_fc → Arsenal FC).",
		question, prologResult,
	)

	resp, err := c.client.Messages.New(ctx, anthropic.MessageNewParams{
		Model:     anthropic.ModelClaudeOpus4_7,
		MaxTokens: 400,
		System: []anthropic.TextBlockParam{{
			Text: `You are Giskard, a Premier League football analyst assistant. Given a question and a raw Prolog query result, provide a clear, concise natural language answer.

Rules:
- Do not mention Prolog, atoms, or technical query details.
- Convert atom names to proper English (e.g. arsenal_fc → Arsenal FC, manchester_united → Manchester United).
- When the result contains specific match details (teams, goals, dates, seasons), ALWAYS state them explicitly — never give only a number without identifying the match(es).
- If multiple matches share the same record, list all of them.
- For dates encoded as YYYYMMDD integers, format them as readable dates (e.g. 20231105 → 5 November 2023).
- For seasons, use the start/end year format (e.g. season 2023 → 2023/24).
- Keep answers factual and focused on the question.`,
		}},
		Messages: []anthropic.MessageParam{
			anthropic.NewUserMessage(anthropic.NewTextBlock(userMsg)),
		},
	})
	if err != nil {
		return "", fmt.Errorf("LLM format answer: %w", err)
	}

	return extractText(resp.Content), nil
}

func extractText(blocks []anthropic.ContentBlockUnion) string {
	var sb strings.Builder
	for _, block := range blocks {
		switch b := block.AsAny().(type) {
		case anthropic.TextBlock:
			sb.WriteString(b.Text)
		}
	}
	return strings.TrimSpace(sb.String())
}
