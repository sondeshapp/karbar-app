package api

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"image"
	"image/jpeg"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

const testSecret = "test-signing-key-that-is-longer-than-32-bytes"

func TestAccessTokenSignatureAndExpiry(t *testing.T) {
	now := time.Date(2026, 10, 26, 12, 0, 0, 0, time.UTC)
	claims := tokenClaims{
		UserID: "a6b946f8-0239-4af7-8504-293bda2ac733",
		ShopID: "96cb3919-08ed-49b1-9439-1e3f7ecfb34d",
		Role:   "owner",
		Issued: now.Unix(),
		Expiry: now.Add(accessTokenLifetime).Unix(),
	}
	token, err := signToken(claims, []byte(testSecret))
	if err != nil {
		t.Fatalf("sign token: %v", err)
	}
	verified, err := verifyToken(token, []byte(testSecret), now)
	if err != nil || verified.UserID != claims.UserID || verified.ShopID != claims.ShopID {
		t.Fatalf("verify token = %#v, %v", verified, err)
	}
	if _, err = verifyToken(token, []byte("wrong-key-that-is-also-longer-than-32-bytes"), now); err == nil {
		t.Fatal("token verified with the wrong secret")
	}
	if _, err = verifyToken(token, []byte(testSecret), now.Add(accessTokenLifetime)); err == nil {
		t.Fatal("expired token was accepted")
	}
}

func TestSyncEventValidationBindsHeaderAndPayloadKeys(t *testing.T) {
	event := syncEventRequest{
		EventID:   "a6b946f8-0239-4af7-8504-293bda2ac733",
		EventType: "sale.created",
		EntityID:  28,
		CreatedAt: time.Date(2026, 10, 26, 10, 0, 0, 0, time.UTC),
		Payload:   []byte(`{"idempotencyKey":"a6b946f8-0239-4af7-8504-293bda2ac733","totalAmount":20}`),
	}
	if err := validateSyncEvent(event, event.EventID); err != nil {
		t.Fatalf("valid event rejected: %v", err)
	}
	purchase := event
	purchase.EventType = "purchase.recorded"
	if err := validateSyncEvent(purchase, purchase.EventID); err != nil {
		t.Fatalf("valid purchase event rejected: %v", err)
	}
	if err := validateSyncEvent(event, "different-key"); err == nil {
		t.Fatal("mismatched header key was accepted")
	}
	event.Payload = []byte(`{"idempotencyKey":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}`)
	if err := validateSyncEvent(event, event.EventID); err == nil {
		t.Fatal("mismatched payload key was accepted")
	}
}

func TestCatalogMutationValidation(t *testing.T) {
	valid := catalogMutation{
		EntityType:   "product",
		EntityID:     "a6b946f8-0239-4af7-8504-293bda2ac733",
		MutationID:   "b6b946f8-0239-4af7-8504-293bda2ac733",
		BaseRevision: 0,
		Payload:      []byte(`{"syncId":"a6b946f8-0239-4af7-8504-293bda2ac733","name":"Tea"}`),
	}
	if err := validateCatalogMutation(valid); err != nil {
		t.Fatalf("valid catalog mutation rejected: %v", err)
	}
	invalid := valid
	invalid.EntityType = "sale"
	if err := validateCatalogMutation(invalid); err == nil {
		t.Fatal("unsupported catalog type was accepted")
	}
	invalid = valid
	invalid.BaseRevision = -1
	if err := validateCatalogMutation(invalid); err == nil {
		t.Fatal("negative base revision was accepted")
	}
	invalid = valid
	invalid.Payload = []byte(`[]`)
	if err := validateCatalogMutation(invalid); err == nil {
		t.Fatal("non-object catalog payload was accepted")
	}
	settings := catalogMutation{
		EntityType:   "settings",
		EntityID:     "00000000-0000-4000-8000-000000000001",
		MutationID:   "c6b946f8-0239-4af7-8504-293bda2ac733",
		BaseRevision: 0,
		Payload:      []byte(`{"syncId":"00000000-0000-4000-8000-000000000001","name":"Shop settings","currencySymbol":"৳","currencyLocale":"en_BD","taxRate":5,"showTax":true,"shopName":"Corner shop","shopPhone":"01700000000","shopAddress":"Dhaka","setupComplete":true}`),
	}
	if err := validateCatalogMutation(settings); err != nil {
		t.Fatalf("valid shop settings rejected: %v", err)
	}
	settings.Payload = []byte(`{"syncId":"00000000-0000-4000-8000-000000000001","name":"Shop settings","unexpected":"value"}`)
	if err := validateCatalogMutation(settings); err == nil {
		t.Fatal("unknown shop settings field was accepted")
	}
	supplier := catalogMutation{
		EntityType:   "supplier",
		EntityID:     "d6b946f8-0239-4af7-8504-293bda2ac733",
		MutationID:   "e6b946f8-0239-4af7-8504-293bda2ac733",
		BaseRevision: 0,
		Payload:      []byte(`{"syncId":"d6b946f8-0239-4af7-8504-293bda2ac733","name":"Rice wholesaler","phone":"01700000000","address":"Dhaka","notes":"Weekly delivery"}`),
	}
	if err := validateCatalogMutation(supplier); err != nil {
		t.Fatalf("valid supplier mutation rejected: %v", err)
	}
	staff := catalogMutation{
		EntityType:   "staff",
		EntityID:     "f6b946f8-0239-4af7-8504-293bda2ac733",
		MutationID:   "a7b946f8-0239-4af7-8504-293bda2ac733",
		BaseRevision: 0,
		Payload:      []byte(`{"syncId":"f6b946f8-0239-4af7-8504-293bda2ac733","name":"Asha","role":"owner","pinSalt":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","pinHash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","active":true,"createdAt":"2026-10-26T00:00:00Z"}`),
	}
	if err := validateCatalogMutation(staff); err != nil {
		t.Fatalf("valid staff mutation rejected: %v", err)
	}
	var jpegBytes bytes.Buffer
	if err := jpeg.Encode(&jpegBytes, image.NewRGBA(image.Rect(0, 0, 2, 2)), nil); err != nil {
		t.Fatal(err)
	}
	imageMutation := catalogMutation{
		EntityType: "product", EntityID: "b7b946f8-0239-4af7-8504-293bda2ac733",
		MutationID: "c7b946f8-0239-4af7-8504-293bda2ac733", BaseRevision: 0,
		Payload: []byte(fmt.Sprintf(`{"syncId":"b7b946f8-0239-4af7-8504-293bda2ac733","name":"Tea","imageData":%q}`, base64.StdEncoding.EncodeToString(jpegBytes.Bytes()))),
	}
	if err := validateCatalogMutation(imageMutation); err != nil {
		t.Fatalf("valid product image mutation rejected: %v", err)
	}
	imageMutation.Payload = []byte(`{"syncId":"b7b946f8-0239-4af7-8504-293bda2ac733","name":"Tea","imageData":"not-base64"}`)
	if err := validateCatalogMutation(imageMutation); err == nil {
		t.Fatal("invalid product image was accepted")
	}
}

func TestRegistrationIsClosedWithoutOperatorCode(t *testing.T) {
	server := NewServer(nil, testSecret, "")
	request := httptest.NewRequest(http.MethodPost, "/v1/auth/register", strings.NewReader(`{}`))
	response := httptest.NewRecorder()
	server.Handler().ServeHTTP(response, request)
	if response.Code != http.StatusForbidden {
		t.Fatalf("registration status = %d, want %d", response.Code, http.StatusForbidden)
	}
}

func TestSyncEndpointRequiresBearerToken(t *testing.T) {
	server := NewServer(nil, testSecret, "")
	request := httptest.NewRequest(http.MethodPost, "/v1/sync/events", strings.NewReader(`{}`))
	response := httptest.NewRecorder()
	server.Handler().ServeHTTP(response, request)
	if response.Code != http.StatusUnauthorized {
		t.Fatalf("sync status = %d, want %d", response.Code, http.StatusUnauthorized)
	}
}

func TestCatalogEndpointRequiresBearerToken(t *testing.T) {
	server := NewServer(nil, testSecret, "")
	for _, method := range []string{http.MethodGet, http.MethodPut} {
		request := httptest.NewRequest(method, "/v1/sync/catalog?after=0", strings.NewReader(`{}`))
		response := httptest.NewRecorder()
		server.Handler().ServeHTTP(response, request)
		if response.Code != http.StatusUnauthorized {
			t.Fatalf("%s catalog status = %d, want %d", method, response.Code, http.StatusUnauthorized)
		}
	}
}

func TestNormalizePhone(t *testing.T) {
	if got := normalizePhone("+880 (1712) 345-678"); got != "8801712345678" {
		t.Fatalf("normalized phone = %q", got)
	}
	if got := normalizePhone("17x12345678"); got != "" {
		t.Fatalf("invalid phone normalized to %q", got)
	}
}

func TestSameJSONIgnoresObjectKeyOrder(t *testing.T) {
	if !sameJSON([]byte(`{"a":1,"b":{"x":true}}`), []byte(`{"b":{"x":true},"a":1}`)) {
		t.Fatal("semantically equal JSON was considered different")
	}
}
