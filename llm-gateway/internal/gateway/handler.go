package gateway

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
)

const maxRetries = 3

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
	Question     string `json:"question"`
	PrologQuery  string `json:"prolog_query"`
	PrologResult string `json:"prolog_result"`
	Answer       string `json:"answer"`
}

type errorResponse struct {
	Error string `json:"error"`
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

	goal, prologResult, err := h.translateAndExecute(r.Context(), req.Question)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: err.Error()})
		return
	}

	answer, err := h.llm.FormatAnswer(r.Context(), req.Question, prologResult)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: fmt.Sprintf("format answer: %s", err)})
		return
	}

	writeJSON(w, http.StatusOK, askResponse{
		Question:     req.Question,
		PrologQuery:  goal,
		PrologResult: prologResult,
		Answer:       answer,
	})
}

// translateAndExecute runs the translate → execute → retry loop.
// On Prolog failure it feeds the error back to the LLM for self-correction (up to maxRetries).
func (h *Handler) translateAndExecute(ctx context.Context, question string) (goal, result string, err error) {
	var lastError string

	for attempt := range maxRetries {
		goal, err = h.llm.TranslateToProlog(ctx, question, lastError)
		if err != nil {
			return "", "", fmt.Errorf("translate (attempt %d): %w", attempt+1, err)
		}
		goal = strings.TrimRight(strings.TrimSpace(goal), ".")

		qr, err := h.prolog.Query(ctx, goal)
		if err != nil {
			return "", "", fmt.Errorf("prolog query (attempt %d): %w", attempt+1, err)
		}
		if qr.Success {
			return goal, qr.Result, nil
		}
		lastError = qr.Error
	}

	return goal, "", fmt.Errorf("goal failed after %d attempts, last error: %s", maxRetries, lastError)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
