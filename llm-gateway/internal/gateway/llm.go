package gateway

import (
	"context"
	"encoding/json"
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
var queryFiles = []string{
	"home_goals.pl",
	"consecutive_wins.pl",
	"league_table.pl",
	"player_streaks.pl",
}

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

// ToolCall records one Prolog query and its result for the audit trail.
type ToolCall struct {
	Goal    string `json:"goal"`
	Result  string `json:"result,omitempty"`
	Error   string `json:"error,omitempty"`
	Success bool   `json:"success"`
}

// prologTool is the single tool exposed to Claude. It is defined once and
// reused across all requests; the description is part of the cached system prompt.
var prologTool = anthropic.ToolParam{
	Name: "query_prolog",
	Description: anthropic.String(
		"Execute a SWI-Prolog goal against the Premier League database. " +
			"Returns the fully-instantiated goal term on success, or an error string on failure. " +
			"Call this tool as many times as needed — first to find key IDs or statistics, " +
			"then again to enrich the result with match details, team names, dates, and scores. " +
			"NEVER report a fact you have not confirmed with a successful call to this tool.",
	),
	InputSchema: anthropic.ToolInputSchemaParam{
		Properties: map[string]any{
			"goal": map[string]any{
				"type":        "string",
				"description": "A valid SWI-Prolog goal. No trailing period. Variables must start with an uppercase letter or underscore.",
			},
		},
	},
}

// maxToolCalls caps the agentic loop to prevent runaway API spend.
// Set to 12 to leave room for verification queries after the main result
// is fetched — derived claims (e.g. "Team X won Y of these N matches")
// must be confirmed with follow-up queries, not inferred mentally.
const maxToolCalls = 12

// maxResultLen truncates very large Prolog results before feeding them back to
// Claude. Raw findall dumps of hundreds of matches are rarely useful in full and
// consume context budget that is better spent on follow-up reasoning.
const maxResultLen = 3000

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

// Answer runs the agentic tool-use loop.
//
// Claude (Sonnet 4.6 with adaptive thinking) reasons about the question,
// calls query_prolog as many times as it needs, and produces a natural language
// answer. The full tool call audit trail is returned alongside the answer.
func (c *LLMClient) Answer(ctx context.Context, question string, prolog *PrologClient) (string, []ToolCall, error) {
	adaptive := anthropic.ThinkingConfigAdaptiveParam{}
	tools := []anthropic.ToolUnionParam{{OfTool: &prologTool}}

	messages := []anthropic.MessageParam{
		anthropic.NewUserMessage(anthropic.NewTextBlock(question)),
	}

	var toolCalls []ToolCall

	for range maxToolCalls {
		resp, err := c.client.Messages.New(ctx, anthropic.MessageNewParams{
			Model:     anthropic.ModelClaudeSonnet4_6,
			MaxTokens: 8192,
			Thinking:  anthropic.ThinkingConfigParamUnion{OfAdaptive: &adaptive},
			System: []anthropic.TextBlockParam{{
				Text:         c.systemPrompt,
				CacheControl: anthropic.NewCacheControlEphemeralParam(),
			}},
			Tools:    tools,
			Messages: messages,
		})
		if err != nil {
			return "", toolCalls, fmt.Errorf("LLM call: %w", err)
		}

		// Append Claude's full response to history before processing.
		messages = append(messages, resp.ToParam())

		if resp.StopReason != anthropic.StopReasonToolUse {
			return extractText(resp.Content), toolCalls, nil
		}

		// Execute every tool call Claude requested and collect results.
		var results []anthropic.ContentBlockParamUnion
		for _, block := range resp.Content {
			tu, ok := block.AsAny().(anthropic.ToolUseBlock)
			if !ok {
				continue
			}

			var input struct {
				Goal string `json:"goal"`
			}
			if err := json.Unmarshal([]byte(tu.JSON.Input.Raw()), &input); err != nil {
				input.Goal = ""
			}
			goal := stripMarkdown(input.Goal)

			qr, err := prolog.Query(ctx, goal)

			var tc ToolCall
			var resultStr string
			var isError bool

			switch {
			case err != nil:
				tc = ToolCall{Goal: goal, Error: err.Error(), Success: false}
				resultStr = "Error: " + err.Error()
				isError = true
			case !qr.Success:
				tc = ToolCall{Goal: goal, Error: qr.Error, Success: false}
				resultStr = "Goal failed: " + qr.Error
				isError = true
			default:
				result := truncate(qr.Result, maxResultLen)
				tc = ToolCall{Goal: goal, Result: result, Success: true}
				resultStr = result
				isError = false
			}

			toolCalls = append(toolCalls, tc)
			results = append(results, anthropic.NewToolResultBlock(tu.ID, resultStr, isError))
		}

		messages = append(messages, anthropic.NewUserMessage(results...))
	}

	return "", toolCalls, fmt.Errorf("exceeded maximum tool calls (%d)", maxToolCalls)
}

func extractText(blocks []anthropic.ContentBlockUnion) string {
	var sb strings.Builder
	for _, block := range blocks {
		if b, ok := block.AsAny().(anthropic.TextBlock); ok {
			sb.WriteString(b.Text)
		}
	}
	return strings.TrimSpace(sb.String())
}

func truncate(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max] + fmt.Sprintf("... [truncated %d chars]", len(s)-max)
}
