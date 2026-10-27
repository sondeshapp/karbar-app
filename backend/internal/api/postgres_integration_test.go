package api

import (
	"bytes"
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	_ "github.com/lib/pq"
	"golang.org/x/crypto/bcrypt"
)

func TestPostgresSyncAndCatalogAreRevisionedAndShopScoped(t *testing.T) {
	databaseURL := os.Getenv("TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("set TEST_DATABASE_URL to run PostgreSQL integration tests")
	}
	admin, err := sql.Open("postgres", databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer admin.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if err = admin.PingContext(ctx); err != nil {
		t.Fatal(err)
	}
	schema := "karbar_test_" + strings.ReplaceAll(strings.ToLower(newUUIDForTest()), "-", "")
	if _, err = admin.ExecContext(ctx, `CREATE SCHEMA `+schema); err != nil {
		t.Fatal(err)
	}
	defer func() { _, _ = admin.ExecContext(context.Background(), `DROP SCHEMA `+schema+` CASCADE`) }()

	parsed, err := url.Parse(databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	query := parsed.Query()
	query.Set("search_path", schema)
	parsed.RawQuery = query.Encode()
	testDB, err := sql.Open("postgres", parsed.String())
	if err != nil {
		t.Fatal(err)
	}
	defer testDB.Close()
	testDB.SetMaxOpenConns(1)
	for _, migrationName := range []string{"001_initial.sql", "002_catalog.sql", "003_catalog_settings.sql", "004_catalog_suppliers.sql", "005_catalog_staff.sql"} {
		migration, readErr := os.ReadFile("../../migrations/" + migrationName)
		if readErr != nil {
			t.Fatal(readErr)
		}
		if _, err = testDB.ExecContext(ctx, string(migration)); err != nil {
			t.Fatalf("apply %s: %v", migrationName, err)
		}
	}
	var shopID, userID string
	if err = testDB.QueryRowContext(ctx, `INSERT INTO shops(name) VALUES ('Test shop') RETURNING id`).Scan(&shopID); err != nil {
		t.Fatal(err)
	}
	hash, err := bcrypt.GenerateFromPassword([]byte("test-password-long"), bcrypt.MinCost)
	if err != nil {
		t.Fatal(err)
	}
	if err = testDB.QueryRowContext(ctx,
		`INSERT INTO users(shop_id,name,phone,password_hash,role) VALUES ($1,'Owner','8801234567890',$2,'owner') RETURNING id`, shopID, string(hash),
	).Scan(&userID); err != nil {
		t.Fatal(err)
	}
	handler := NewServer(testDB, testSecret, "registration-secret").Handler()
	loginRequest := httptest.NewRequest(http.MethodPost, "/v1/auth/login", strings.NewReader(
		`{"phone":"+8801234567890","password":"test-password-long"}`,
	))
	loginResponse := httptest.NewRecorder()
	handler.ServeHTTP(loginResponse, loginRequest)
	if loginResponse.Code != http.StatusOK {
		t.Fatalf("login status = %d, body=%s", loginResponse.Code, loginResponse.Body.String())
	}
	var loginResult struct {
		AccessToken  string `json:"accessToken"`
		RefreshToken string `json:"refreshToken"`
	}
	if err = json.Unmarshal(loginResponse.Body.Bytes(), &loginResult); err != nil || loginResult.AccessToken == "" || loginResult.RefreshToken == "" {
		t.Fatalf("login response missing tokens: %v", err)
	}
	token := loginResult.AccessToken
	now := time.Now().UTC().Truncate(time.Microsecond)
	eventID := newUUIDForTest()
	payload := map[string]any{"idempotencyKey": eventID, "totalAmount": 20}
	post := func(body map[string]any) *httptest.ResponseRecorder {
		data, marshalErr := json.Marshal(body)
		if marshalErr != nil {
			t.Fatal(marshalErr)
		}
		request := httptest.NewRequest(http.MethodPost, "/v1/sync/events", bytes.NewReader(data))
		request.Header.Set("Authorization", "Bearer "+token)
		request.Header.Set("Idempotency-Key", eventID)
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		return response
	}
	event := map[string]any{
		"eventId": eventID, "eventType": "sale.created", "entityId": 77,
		"createdAt": now.Format(time.RFC3339Nano), "payload": payload,
	}
	first := post(event)
	if first.Code != http.StatusCreated {
		t.Fatalf("first event status = %d, body=%s", first.Code, first.Body.String())
	}
	var firstResult struct {
		Cursor int64 `json:"cursor"`
	}
	if err = json.Unmarshal(first.Body.Bytes(), &firstResult); err != nil {
		t.Fatal(err)
	}
	duplicate := post(event)
	if duplicate.Code != http.StatusOK {
		t.Fatalf("duplicate status = %d, body=%s", duplicate.Code, duplicate.Body.String())
	}
	var duplicateResult struct {
		Cursor    int64 `json:"cursor"`
		Duplicate bool  `json:"duplicate"`
	}
	if err = json.Unmarshal(duplicate.Body.Bytes(), &duplicateResult); err != nil {
		t.Fatal(err)
	}
	if !duplicateResult.Duplicate || duplicateResult.Cursor != firstResult.Cursor {
		t.Fatalf("duplicate result = %#v; expected same cursor %d", duplicateResult, firstResult.Cursor)
	}
	changed := map[string]any{
		"eventId": eventID, "eventType": "sale.created", "entityId": 77,
		"createdAt": now.Format(time.RFC3339Nano),
		"payload":   map[string]any{"idempotencyKey": eventID, "totalAmount": 99},
	}
	conflict := post(changed)
	if conflict.Code != http.StatusConflict {
		t.Fatalf("changed duplicate status = %d, want 409", conflict.Code)
	}
	var count int
	if err = testDB.QueryRowContext(ctx, `SELECT COUNT(*) FROM sync_events WHERE shop_id=$1 AND event_id=$2`, shopID, eventID).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if count != 1 {
		t.Fatalf("stored duplicate count = %d, want 1", count)
	}
	if firstResult.Cursor <= 0 {
		t.Fatalf("invalid event cursor: %d", firstResult.Cursor)
	}

	feedRequest := httptest.NewRequest(http.MethodGet, "/v1/sync/events?after=0", nil)
	feedRequest.Header.Set("Authorization", "Bearer "+token)
	feedResponse := httptest.NewRecorder()
	handler.ServeHTTP(feedResponse, feedRequest)
	if feedResponse.Code != http.StatusOK {
		t.Fatalf("feed status = %d, body=%s", feedResponse.Code, feedResponse.Body.String())
	}
	var feed struct {
		Events []json.RawMessage `json:"events"`
		Cursor int64             `json:"cursor"`
	}
	if err = json.Unmarshal(feedResponse.Body.Bytes(), &feed); err != nil || len(feed.Events) != 1 || feed.Cursor != firstResult.Cursor {
		t.Fatalf("event feed = %#v, error=%v", feed, err)
	}
	var otherShopID, otherUserID string
	if err = testDB.QueryRowContext(ctx, `INSERT INTO shops(name) VALUES ('Other shop') RETURNING id`).Scan(&otherShopID); err != nil {
		t.Fatal(err)
	}
	if err = testDB.QueryRowContext(ctx,
		`INSERT INTO users(shop_id,name,phone,password_hash,role) VALUES ($1,'Other owner','8801987654321',$2,'owner') RETURNING id`, otherShopID, string(hash),
	).Scan(&otherUserID); err != nil {
		t.Fatal(err)
	}
	otherToken, err := signToken(tokenClaims{
		UserID: otherUserID, ShopID: otherShopID, Role: "owner",
		Issued: now.Unix(), Expiry: now.Add(time.Minute).Unix(),
	}, []byte(testSecret))
	if err != nil {
		t.Fatal(err)
	}
	otherFeedRequest := httptest.NewRequest(http.MethodGet, "/v1/sync/events?after=0", nil)
	otherFeedRequest.Header.Set("Authorization", "Bearer "+otherToken)
	otherFeedResponse := httptest.NewRecorder()
	handler.ServeHTTP(otherFeedResponse, otherFeedRequest)
	var otherFeed struct {
		Events []json.RawMessage `json:"events"`
	}
	if otherFeedResponse.Code != http.StatusOK ||
		json.Unmarshal(otherFeedResponse.Body.Bytes(), &otherFeed) != nil || len(otherFeed.Events) != 0 {
		t.Fatalf("other shop received a foreign event: status=%d body=%s", otherFeedResponse.Code, otherFeedResponse.Body.String())
	}

	productID := newUUIDForTest()
	mutationID := newUUIDForTest()
	productPayload := map[string]any{"syncId": productID, "name": "Tea", "variants": []any{}}
	putCatalog := func(baseRevision int64, mutation string, payload map[string]any) *httptest.ResponseRecorder {
		body, marshalErr := json.Marshal(map[string]any{
			"entityType": "product", "entityId": productID, "mutationId": mutation,
			"baseRevision": baseRevision, "payload": payload, "deleted": false,
		})
		if marshalErr != nil {
			t.Fatal(marshalErr)
		}
		request := httptest.NewRequest(http.MethodPut, "/v1/sync/catalog", bytes.NewReader(body))
		request.Header.Set("Authorization", "Bearer "+token)
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		return response
	}
	firstCatalog := putCatalog(0, mutationID, productPayload)
	if firstCatalog.Code != http.StatusOK {
		t.Fatalf("catalog create status = %d, body=%s", firstCatalog.Code, firstCatalog.Body.String())
	}
	var catalogResult struct {
		Cursor   int64 `json:"cursor"`
		Revision int64 `json:"revision"`
	}
	if err = json.Unmarshal(firstCatalog.Body.Bytes(), &catalogResult); err != nil || catalogResult.Revision != 1 {
		t.Fatalf("catalog create result = %#v, error=%v", catalogResult, err)
	}
	duplicateCatalog := putCatalog(0, mutationID, productPayload)
	var duplicateCatalogResult struct {
		Cursor    int64 `json:"cursor"`
		Revision  int64 `json:"revision"`
		Duplicate bool  `json:"duplicate"`
	}
	if duplicateCatalog.Code != http.StatusOK || json.Unmarshal(duplicateCatalog.Body.Bytes(), &duplicateCatalogResult) != nil ||
		!duplicateCatalogResult.Duplicate || duplicateCatalogResult.Cursor != catalogResult.Cursor {
		t.Fatalf("catalog duplicate = %d %s", duplicateCatalog.Code, duplicateCatalog.Body.String())
	}
	staleCatalog := putCatalog(0, newUUIDForTest(), map[string]any{"syncId": productID, "name": "Stale"})
	if staleCatalog.Code != http.StatusConflict || !strings.Contains(staleCatalog.Body.String(), `"currentRevision":1`) {
		t.Fatalf("stale catalog update status=%d body=%s", staleCatalog.Code, staleCatalog.Body.String())
	}
	updatedCatalog := putCatalog(1, newUUIDForTest(), map[string]any{"syncId": productID, "name": "Updated tea"})
	if updatedCatalog.Code != http.StatusOK || !strings.Contains(updatedCatalog.Body.String(), `"revision":2`) {
		t.Fatalf("catalog update status=%d body=%s", updatedCatalog.Code, updatedCatalog.Body.String())
	}
	staffID, staffMutationID := newUUIDForTest(), newUUIDForTest()
	staffPayload, _ := json.Marshal(map[string]any{
		"syncId": staffID, "name": "Cashier", "role": "cashier",
		"pinSalt": strings.Repeat("a", 32), "pinHash": strings.Repeat("b", 64),
		"active": true, "createdAt": now.Format(time.RFC3339Nano),
	})
	staffBody, _ := json.Marshal(catalogMutation{
		EntityType: "staff", EntityID: staffID, MutationID: staffMutationID,
		BaseRevision: 0, Payload: staffPayload,
	})
	staffRequest := httptest.NewRequest(http.MethodPut, "/v1/sync/catalog", bytes.NewReader(staffBody))
	staffRequest.Header.Set("Authorization", "Bearer "+token)
	staffResponse := httptest.NewRecorder()
	handler.ServeHTTP(staffResponse, staffRequest)
	if staffResponse.Code != http.StatusOK {
		t.Fatalf("staff catalog create status=%d body=%s", staffResponse.Code, staffResponse.Body.String())
	}
	catalogFeedRequest := httptest.NewRequest(http.MethodGet, "/v1/sync/catalog?after=0", nil)
	catalogFeedRequest.Header.Set("Authorization", "Bearer "+token)
	catalogFeed := httptest.NewRecorder()
	handler.ServeHTTP(catalogFeed, catalogFeedRequest)
	var catalogFeedResult struct {
		Changes []json.RawMessage `json:"changes"`
		Cursor  int64             `json:"cursor"`
	}
	if catalogFeed.Code != http.StatusOK || json.Unmarshal(catalogFeed.Body.Bytes(), &catalogFeedResult) != nil ||
		len(catalogFeedResult.Changes) != 3 || catalogFeedResult.Cursor <= catalogResult.Cursor {
		t.Fatalf("catalog feed status=%d body=%s", catalogFeed.Code, catalogFeed.Body.String())
	}
	otherCatalogRequest := httptest.NewRequest(http.MethodGet, "/v1/sync/catalog?after=0", nil)
	otherCatalogRequest.Header.Set("Authorization", "Bearer "+otherToken)
	otherCatalogResponse := httptest.NewRecorder()
	handler.ServeHTTP(otherCatalogResponse, otherCatalogRequest)
	var otherCatalog struct {
		Changes []json.RawMessage `json:"changes"`
	}
	if otherCatalogResponse.Code != http.StatusOK || json.Unmarshal(otherCatalogResponse.Body.Bytes(), &otherCatalog) != nil ||
		len(otherCatalog.Changes) != 0 {
		t.Fatalf("other shop received catalog data: status=%d body=%s", otherCatalogResponse.Code, otherCatalogResponse.Body.String())
	}

	refreshRequest := func(refreshToken string) *httptest.ResponseRecorder {
		request := httptest.NewRequest(http.MethodPost, "/v1/auth/refresh", strings.NewReader(
			fmt.Sprintf(`{"refreshToken":%q}`, refreshToken),
		))
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		return response
	}
	refreshed := refreshRequest(loginResult.RefreshToken)
	if refreshed.Code != http.StatusOK {
		t.Fatalf("refresh status = %d, body=%s", refreshed.Code, refreshed.Body.String())
	}
	var refreshResult struct {
		RefreshToken string `json:"refreshToken"`
	}
	if err = json.Unmarshal(refreshed.Body.Bytes(), &refreshResult); err != nil || refreshResult.RefreshToken == "" {
		t.Fatalf("refresh response missing token: %v", err)
	}
	if replay := refreshRequest(loginResult.RefreshToken); replay.Code != http.StatusUnauthorized {
		t.Fatalf("replayed refresh status = %d, want 401", replay.Code)
	}
	logoutRequest := httptest.NewRequest(http.MethodPost, "/v1/auth/logout", strings.NewReader(
		fmt.Sprintf(`{"refreshToken":%q}`, refreshResult.RefreshToken),
	))
	logoutResponse := httptest.NewRecorder()
	handler.ServeHTTP(logoutResponse, logoutRequest)
	if logoutResponse.Code != http.StatusNoContent {
		t.Fatalf("logout status = %d, want 204", logoutResponse.Code)
	}
	if replay := refreshRequest(refreshResult.RefreshToken); replay.Code != http.StatusUnauthorized {
		t.Fatalf("logged-out refresh status = %d, want 401", replay.Code)
	}
}

func newUUIDForTest() string {
	bytes := make([]byte, 16)
	if _, err := rand.Read(bytes); err != nil {
		panic(fmt.Sprintf("generate UUID: %v", err))
	}
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	hex := fmt.Sprintf("%x", bytes)
	return fmt.Sprintf("%s-%s-%s-%s-%s", hex[:8], hex[8:12], hex[12:16], hex[16:20], hex[20:])
}
