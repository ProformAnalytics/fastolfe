package gateway

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
)

type Handler struct {
	llm    *LLMClient
	prolog *PrologClient
}

func NewHandler(llm *LLMClient, prolog *PrologClient) *Handler {
	return &Handler{llm: llm, prolog: prolog}
}

func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /health", h.handleHealth)
	mux.HandleFunc("POST /ask", h.handleAsk)
}

func (h *Handler) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

type askRequest struct {
	Question string `json:"question"`
}

type askResponse struct {
	Question  string     `json:"question"`
	ToolCalls []ToolCall `json:"tool_calls"`
	Answer    string     `json:"answer"`
}

type errorResponse struct {
	Error     string     `json:"error"`
	ToolCalls []ToolCall `json:"tool_calls,omitempty"`
}

func (h *Handler) handleAsk(w http.ResponseWriter, r *http.Request) {
	var req askRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "invalid JSON"})
		return
	}
	req.Question = strings.TrimSpace(req.Question)
	if req.Question == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "question is required"})
		return
	}

	answer, toolCalls, err := h.llm.Answer(r.Context(), req.Question, h.prolog)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorResponse{
			Error:     fmt.Sprintf("answer failed: %s", err),
			ToolCalls: toolCalls,
		})
		return
	}

	writeJSON(w, http.StatusOK, askResponse{
		Question:  req.Question,
		ToolCalls: toolCalls,
		Answer:    answer,
	})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// stripMarkdown removes markdown formatting an LLM may produce around a Prolog goal.
// In SWI-Prolog, backtick-delimited strings are character code lists, so a
// backtick-wrapped goal silently evaluates to a list of ASCII integers.
func stripMarkdown(s string) string {
	s = strings.TrimSpace(s)
	if strings.HasPrefix(s, "```") {
		s = strings.TrimPrefix(s, "```")
		if i := strings.Index(s, "```"); i >= 0 {
			s = s[:i]
		}
		if nl := strings.Index(s, "\n"); nl >= 0 {
			s = s[nl+1:]
		}
	}
	s = strings.Trim(s, "`")
	s = strings.TrimRight(strings.TrimSpace(s), ".")
	return strings.TrimSpace(s)
}
