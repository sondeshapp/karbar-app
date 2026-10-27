package api

import (
	"context"
	"crypto/hmac"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/lib/pq"
	"golang.org/x/crypto/bcrypt"
)

const accessTokenLifetime = 15 * time.Minute

var (
	phonePattern   = regexp.MustCompile(`^[0-9]{8,15}$`)
	uuidPattern    = regexp.MustCompile(`(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`)
	acceptedEvents = map[string]bool{
		"sale.created":          true,
		"sale.returned":         true,
		"baki.payment_recorded": true,
		"purchase.recorded":     true,
	}
)

type Server struct {
	db                 *sql.DB
	jwtSecret          []byte
	registrationSecret string
	clock              func() time.Time
}

func NewServer(db *sql.DB, jwtSecret, registrationSecret string) *Server {
	return &Server{
		db:                 db,
		jwtSecret:          []byte(jwtSecret),
		registrationSecret: registrationSecret,
		clock:              time.Now,
	}
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/healthz", s.health)
	mux.HandleFunc("POST /v1/auth/register", s.register)
	mux.HandleFunc("POST /v1/auth/login", s.login)
	mux.HandleFunc("POST /v1/auth/refresh", s.refresh)
	mux.HandleFunc("POST /v1/auth/logout", s.logout)
	mux.Handle("POST /v1/sync/events", s.requireUser(http.HandlerFunc(s.acceptEvent)))
	mux.Handle("GET /v1/sync/events", s.requireUser(http.HandlerFunc(s.listEvents)))
	mux.Handle("PUT /v1/sync/catalog", s.requireUser(http.HandlerFunc(s.putCatalogEntity)))
	mux.Handle("GET /v1/sync/catalog", s.requireUser(http.HandlerFunc(s.listCatalogChanges)))
	return recoverPanics(mux)
}

func recoverPanics(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if recover() != nil {
				writeError(w, http.StatusInternalServerError, "internal_error", "The server could not complete the request.")
			}
		}()
		next.ServeHTTP(w, r)
	})
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	if err := s.db.PingContext(r.Context()); err != nil {
		writeError(w, http.StatusServiceUnavailable, "database_unavailable", "The database is unavailable.")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"status": "ok"})
}

type registerRequest struct {
	ShopName string `json:"shopName"`
	Name     string `json:"name"`
	Phone    string `json:"phone"`
	Password string `json:"password"`
}

func (s *Server) register(w http.ResponseWriter, r *http.Request) {
	if s.registrationSecret == "" || !constantTimeEqual(r.Header.Get("X-Registration-Code"), s.registrationSecret) {
		writeError(w, http.StatusForbidden, "registration_closed", "Shop registration is not enabled for this server.")
		return
	}
	var input registerRequest
	if !decodeJSON(w, r, &input) {
		return
	}
	phone := normalizePhone(input.Phone)
	if strings.TrimSpace(input.ShopName) == "" || len(input.ShopName) > 120 ||
		strings.TrimSpace(input.Name) == "" || len(input.Name) > 120 ||
		!phonePattern.MatchString(phone) || len(input.Password) < 10 || len(input.Password) > 72 {
		writeError(w, http.StatusBadRequest, "invalid_registration", "Enter a shop name, name, valid phone number, and a password of 10–72 bytes.")
		return
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(input.Password), bcrypt.DefaultCost)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "password_hash_failed", "The account could not be created.")
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "registration_failed", "The account could not be created.")
		return
	}
	defer tx.Rollback()
	var shopID, userID string
	if err = tx.QueryRowContext(r.Context(),
		`INSERT INTO shops (name) VALUES ($1) RETURNING id`, strings.TrimSpace(input.ShopName),
	).Scan(&shopID); err == nil {
		err = tx.QueryRowContext(r.Context(),
			`INSERT INTO users (shop_id, name, phone, password_hash, role)
			 VALUES ($1, $2, $3, $4, 'owner') RETURNING id`,
			shopID, strings.TrimSpace(input.Name), phone, string(hash),
		).Scan(&userID)
	}
	if err != nil {
		if isUniqueViolation(err) {
			writeError(w, http.StatusConflict, "phone_in_use", "An account already uses this phone number.")
		} else {
			writeError(w, http.StatusInternalServerError, "registration_failed", "The account could not be created.")
		}
		return
	}
	if err = tx.Commit(); err != nil {
		writeError(w, http.StatusInternalServerError, "registration_failed", "The account could not be created.")
		return
	}
	s.writeToken(r.Context(), w, http.StatusCreated, userID, shopID, "owner")
}

type loginRequest struct {
	Phone    string `json:"phone"`
	Password string `json:"password"`
}

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	var input loginRequest
	if !decodeJSON(w, r, &input) {
		return
	}
	phone := normalizePhone(input.Phone)
	var userID, shopID, role, passwordHash string
	err := s.db.QueryRowContext(r.Context(),
		`SELECT id, shop_id, role, password_hash FROM users
		 WHERE phone = $1 AND is_active = true`, phone,
	).Scan(&userID, &shopID, &role, &passwordHash)
	if err != nil || bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(input.Password)) != nil {
		writeError(w, http.StatusUnauthorized, "invalid_credentials", "The phone number or password is incorrect.")
		return
	}
	s.writeToken(r.Context(), w, http.StatusOK, userID, shopID, role)
}

type tokenClaims struct {
	UserID string `json:"sub"`
	ShopID string `json:"shop_id"`
	Role   string `json:"role"`
	Issued int64  `json:"iat"`
	Expiry int64  `json:"exp"`
}

func (s *Server) writeToken(ctx context.Context, w http.ResponseWriter, status int, userID, shopID, role string) {
	pair, err := createTokenPair(userID, shopID, role, s.jwtSecret, s.clock())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "token_failed", "The account could not be signed in.")
		return
	}
	_, err = s.db.ExecContext(ctx,
		`INSERT INTO refresh_tokens (token_hash, user_id, expires_at) VALUES ($1, $2, $3)`,
		hashRefreshToken(pair.RefreshToken), userID, pair.ExpiresAt,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "token_failed", "The account could not be signed in.")
		return
	}
	writeJSON(w, status, map[string]any{
		"accessToken":  pair.AccessToken,
		"refreshToken": pair.RefreshToken,
		"tokenType":    "Bearer",
		"expiresIn":    int(accessTokenLifetime.Seconds()),
		"user": map[string]string{
			"id": userID, "shopId": shopID, "role": role,
		},
	})
}

type refreshRequest struct {
	RefreshToken string `json:"refreshToken"`
}

func (s *Server) refresh(w http.ResponseWriter, r *http.Request) {
	var input refreshRequest
	if !decodeJSON(w, r, &input) {
		return
	}
	if input.RefreshToken == "" || len(input.RefreshToken) > 256 {
		writeError(w, http.StatusBadRequest, "invalid_refresh_token", "A refresh token is required.")
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "refresh_failed", "The session could not be refreshed.")
		return
	}
	defer tx.Rollback()
	var userID, shopID, role string
	var expiresAt time.Time
	var revokedAt sql.NullTime
	var active bool
	err = tx.QueryRowContext(r.Context(),
		`SELECT u.id, u.shop_id, u.role, rt.expires_at, rt.revoked_at, u.is_active
		 FROM refresh_tokens rt JOIN users u ON u.id = rt.user_id
		 WHERE rt.token_hash = $1 FOR UPDATE OF rt`,
		hashRefreshToken(input.RefreshToken),
	).Scan(&userID, &shopID, &role, &expiresAt, &revokedAt, &active)
	if err != nil || !active || revokedAt.Valid || !s.clock().Before(expiresAt) {
		writeError(w, http.StatusUnauthorized, "invalid_refresh_token", "The session has expired. Sign in again.")
		return
	}
	pair, err := createTokenPair(userID, shopID, role, s.jwtSecret, s.clock())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "refresh_failed", "The session could not be refreshed.")
		return
	}
	_, err = tx.ExecContext(r.Context(),
		`UPDATE refresh_tokens SET revoked_at = $1 WHERE token_hash = $2 AND revoked_at IS NULL`,
		s.clock().UTC(), hashRefreshToken(input.RefreshToken),
	)
	if err == nil {
		_, err = tx.ExecContext(r.Context(),
			`INSERT INTO refresh_tokens (token_hash, user_id, expires_at) VALUES ($1, $2, $3)`,
			hashRefreshToken(pair.RefreshToken), userID, pair.ExpiresAt,
		)
	}
	if err != nil || tx.Commit() != nil {
		writeError(w, http.StatusInternalServerError, "refresh_failed", "The session could not be refreshed.")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"accessToken": pair.AccessToken, "refreshToken": pair.RefreshToken,
		"tokenType": "Bearer", "expiresIn": int(accessTokenLifetime.Seconds()),
	})
}

func (s *Server) logout(w http.ResponseWriter, r *http.Request) {
	var input refreshRequest
	if !decodeJSON(w, r, &input) {
		return
	}
	if input.RefreshToken == "" || len(input.RefreshToken) > 256 {
		writeError(w, http.StatusBadRequest, "invalid_refresh_token", "A refresh token is required.")
		return
	}
	_, err := s.db.ExecContext(r.Context(),
		`UPDATE refresh_tokens SET revoked_at = $1 WHERE token_hash = $2 AND revoked_at IS NULL`,
		s.clock().UTC(), hashRefreshToken(input.RefreshToken),
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "logout_failed", "The session could not be signed out.")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) requireUser(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		parts := strings.Fields(r.Header.Get("Authorization"))
		if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
			writeError(w, http.StatusUnauthorized, "unauthorized", "A valid access token is required.")
			return
		}
		claims, err := verifyToken(parts[1], s.jwtSecret, s.clock())
		if err != nil {
			writeError(w, http.StatusUnauthorized, "unauthorized", "A valid access token is required.")
			return
		}
		var active bool
		err = s.db.QueryRowContext(r.Context(),
			`SELECT is_active FROM users WHERE id = $1 AND shop_id = $2`, claims.UserID, claims.ShopID,
		).Scan(&active)
		if err != nil || !active {
			writeError(w, http.StatusUnauthorized, "unauthorized", "This account is no longer active.")
			return
		}
		ctx := withClaims(r, claims)
		next.ServeHTTP(w, ctx)
	})
}

type syncEventRequest struct {
	EventID   string          `json:"eventId"`
	EventType string          `json:"eventType"`
	EntityID  int64           `json:"entityId"`
	CreatedAt time.Time       `json:"createdAt"`
	Payload   json.RawMessage `json:"payload"`
}

func (s *Server) acceptEvent(w http.ResponseWriter, r *http.Request) {
	var input syncEventRequest
	if !decodeJSON(w, r, &input) {
		return
	}
	if err := validateSyncEvent(input, r.Header.Get("Idempotency-Key")); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_event", "The sync event is invalid.")
		return
	}
	claims := claimsFrom(r)
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "sync_failed", "The sync event could not be saved.")
		return
	}
	defer tx.Rollback()
	var cursor int64
	err = tx.QueryRowContext(r.Context(),
		`INSERT INTO sync_events (shop_id, actor_id, event_id, event_type, local_entity_id, event_created_at, payload)
		 VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb)
		 ON CONFLICT (shop_id, event_id) DO NOTHING
		 RETURNING cursor`,
		claims.ShopID, claims.UserID, input.EventID, input.EventType, input.EntityID,
		input.CreatedAt.UTC(), string(input.Payload),
	).Scan(&cursor)
	if errors.Is(err, sql.ErrNoRows) {
		var oldType string
		var oldEntityID int64
		var oldCreatedAt time.Time
		var oldPayload []byte
		err = tx.QueryRowContext(r.Context(),
			`SELECT cursor, event_type, local_entity_id, event_created_at, payload
			 FROM sync_events WHERE shop_id = $1 AND event_id = $2`,
			claims.ShopID, input.EventID,
		).Scan(&cursor, &oldType, &oldEntityID, &oldCreatedAt, &oldPayload)
		if err != nil || oldType != input.EventType || oldEntityID != input.EntityID ||
			!oldCreatedAt.Equal(input.CreatedAt.UTC()) || !sameJSON(oldPayload, input.Payload) {
			writeError(w, http.StatusConflict, "idempotency_conflict", "This idempotency key was already used for a different event.")
			return
		}
		if err = tx.Commit(); err != nil {
			writeError(w, http.StatusInternalServerError, "sync_failed", "The sync event could not be saved.")
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"accepted": true, "duplicate": true, "cursor": cursor})
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "sync_failed", "The sync event could not be saved.")
		return
	}
	if err = tx.Commit(); err != nil {
		writeError(w, http.StatusInternalServerError, "sync_failed", "The sync event could not be saved.")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"accepted": true, "duplicate": false, "cursor": cursor})
}

func (s *Server) listEvents(w http.ResponseWriter, r *http.Request) {
	claims := claimsFrom(r)
	after, err := strconv.ParseInt(r.URL.Query().Get("after"), 10, 64)
	if err != nil || after < 0 {
		writeError(w, http.StatusBadRequest, "invalid_cursor", "The event cursor is invalid.")
		return
	}
	rows, err := s.db.QueryContext(r.Context(),
		`SELECT cursor, event_id, event_type, local_entity_id, event_created_at, payload
		 FROM sync_events WHERE shop_id = $1 AND cursor > $2
		 ORDER BY cursor ASC LIMIT 500`, claims.ShopID, after,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "sync_failed", "Events could not be loaded.")
		return
	}
	defer rows.Close()
	events := make([]map[string]any, 0)
	var cursor int64 = after
	for rows.Next() {
		var eventID, eventType string
		var localEntityID int64
		var createdAt time.Time
		var payload []byte
		var eventCursor int64
		if err = rows.Scan(&eventCursor, &eventID, &eventType, &localEntityID, &createdAt, &payload); err != nil {
			writeError(w, http.StatusInternalServerError, "sync_failed", "Events could not be loaded.")
			return
		}
		var decodedPayload json.RawMessage = payload
		events = append(events, map[string]any{
			"cursor": eventCursor, "eventId": eventID, "eventType": eventType,
			"entityId": localEntityID, "createdAt": createdAt.UTC(), "payload": decodedPayload,
		})
		cursor = eventCursor
	}
	if err = rows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, "sync_failed", "Events could not be loaded.")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"events": events, "cursor": cursor})
}

func decodeJSON(w http.ResponseWriter, r *http.Request, target any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_json", "The request body is invalid.")
		return false
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		writeError(w, http.StatusBadRequest, "invalid_json", "The request body must contain one JSON object.")
		return false
	}
	return true
}

func normalizePhone(input string) string {
	var digits strings.Builder
	trimmed := strings.TrimSpace(input)
	for index, char := range trimmed {
		if char >= '0' && char <= '9' {
			digits.WriteRune(char)
		} else if char == '+' && index == 0 {
			continue
		} else if char != ' ' && char != '-' && char != '(' && char != ')' {
			return ""
		}
	}
	return digits.String()
}

func validateSyncEvent(input syncEventRequest, headerKey string) error {
	payload := strings.TrimSpace(string(input.Payload))
	if !uuidPattern.MatchString(input.EventID) ||
		!constantTimeEqual(headerKey, input.EventID) ||
		!acceptedEvents[input.EventType] || input.EntityID <= 0 || input.CreatedAt.IsZero() ||
		payload == "" || !json.Valid([]byte(payload)) || payload[0] != '{' {
		return fmt.Errorf("invalid sync event")
	}
	var value map[string]json.RawMessage
	if json.Unmarshal([]byte(payload), &value) != nil {
		return fmt.Errorf("invalid sync payload")
	}
	var payloadKey string
	if err := json.Unmarshal(value["idempotencyKey"], &payloadKey); err != nil || !constantTimeEqual(payloadKey, input.EventID) {
		return fmt.Errorf("sync payload key does not match")
	}
	return nil
}

func isUniqueViolation(err error) bool {
	var postgresError *pq.Error
	return errors.As(err, &postgresError) && postgresError.Code == "23505"
}

func sameJSON(left, right []byte) bool {
	var a, b any
	return json.Unmarshal(left, &a) == nil && json.Unmarshal(right, &b) == nil && jsonEqual(a, b)
}

func jsonEqual(a, b any) bool {
	left, errA := json.Marshal(a)
	right, errB := json.Marshal(b)
	return errA == nil && errB == nil && hmac.Equal(left, right)
}

func constantTimeEqual(a, b string) bool {
	return len(a) == len(b) && hmac.Equal([]byte(a), []byte(b))
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, map[string]any{"error": map[string]string{"code": code, "message": message}})
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
