package api

import (
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"
)

type catalogMutation struct {
	EntityType   string          `json:"entityType"`
	EntityID     string          `json:"entityId"`
	MutationID   string          `json:"mutationId"`
	BaseRevision int64           `json:"baseRevision"`
	Payload      json.RawMessage `json:"payload"`
	Deleted      bool            `json:"deleted"`
}

var (
	staffPinSaltPattern = regexp.MustCompile(`^[0-9a-f]{32}$`)
	staffPinHashPattern = regexp.MustCompile(`^[0-9a-f]{64}$`)
)

func (s *Server) putCatalogEntity(w http.ResponseWriter, r *http.Request) {
	var input catalogMutation
	if !decodeJSON(w, r, &input) {
		return
	}
	if err := validateCatalogMutation(input); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_catalog_mutation", "The catalog update is invalid.")
		return
	}
	claims := claimsFrom(r)
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "catalog_failed", "The catalog update could not be saved.")
		return
	}
	defer tx.Rollback()

	var oldType, oldEntityID string
	var oldBase, oldRevision, oldCursor int64
	var oldPayload []byte
	var oldDeleted bool
	err = tx.QueryRowContext(r.Context(),
		`SELECT cursor, entity_type, entity_id, base_revision, revision, payload, is_deleted
		 FROM catalog_changes WHERE shop_id = $1 AND mutation_id = $2`,
		claims.ShopID, input.MutationID,
	).Scan(&oldCursor, &oldType, &oldEntityID, &oldBase, &oldRevision, &oldPayload, &oldDeleted)
	if err == nil {
		if oldType != input.EntityType || !strings.EqualFold(oldEntityID, input.EntityID) ||
			oldBase != input.BaseRevision || oldDeleted != input.Deleted ||
			!sameJSON(oldPayload, input.Payload) {
			writeError(w, http.StatusConflict, "mutation_id_conflict", "This mutation ID was already used for different catalog data.")
			return
		}
		if err = tx.Commit(); err != nil {
			writeError(w, http.StatusInternalServerError, "catalog_failed", "The catalog update could not be saved.")
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"accepted": true, "duplicate": true, "cursor": oldCursor, "revision": oldRevision,
		})
		return
	}
	if !errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusInternalServerError, "catalog_failed", "The catalog update could not be saved.")
		return
	}

	var currentRevision int64
	var currentPayload []byte
	var currentDeleted bool
	err = tx.QueryRowContext(r.Context(),
		`SELECT revision, payload, is_deleted FROM catalog_entities
		 WHERE shop_id = $1 AND entity_type = $2 AND entity_id = $3 FOR UPDATE`,
		claims.ShopID, input.EntityType, input.EntityID,
	).Scan(&currentRevision, &currentPayload, &currentDeleted)
	if errors.Is(err, sql.ErrNoRows) {
		if input.BaseRevision != 0 {
			writeCatalogConflict(w, 0, nil, false)
			return
		}
		currentRevision = 0
	} else if err != nil {
		writeError(w, http.StatusInternalServerError, "catalog_failed", "The catalog update could not be loaded.")
		return
	}
	if currentRevision != input.BaseRevision {
		writeCatalogConflict(w, currentRevision, currentPayload, currentDeleted)
		return
	}
	nextRevision := currentRevision + 1
	if currentRevision == 0 {
		_, err = tx.ExecContext(r.Context(),
			`INSERT INTO catalog_entities
			 (shop_id, entity_type, entity_id, revision, payload, is_deleted, updated_by, updated_at)
			 VALUES ($1, $2, $3, $4, $5::jsonb, $6, $7, $8)`,
			claims.ShopID, input.EntityType, input.EntityID, nextRevision,
			string(input.Payload), input.Deleted, claims.UserID, s.clock().UTC(),
		)
	} else {
		_, err = tx.ExecContext(r.Context(),
			`UPDATE catalog_entities SET revision = $4, payload = $5::jsonb,
			 is_deleted = $6, updated_by = $7, updated_at = $8
			 WHERE shop_id = $1 AND entity_type = $2 AND entity_id = $3`,
			claims.ShopID, input.EntityType, input.EntityID, nextRevision,
			string(input.Payload), input.Deleted, claims.UserID, s.clock().UTC(),
		)
	}
	if err != nil {
		writeError(w, http.StatusConflict, "catalog_conflict", "Another device changed this catalog record. Download it and resolve the conflict before retrying.")
		return
	}
	var cursor int64
	err = tx.QueryRowContext(r.Context(),
		`INSERT INTO catalog_changes
		 (shop_id, entity_type, entity_id, mutation_id, base_revision, revision,
		  payload, is_deleted, changed_by, changed_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, $9, $10)
		 RETURNING cursor`,
		claims.ShopID, input.EntityType, input.EntityID, input.MutationID,
		input.BaseRevision, nextRevision, string(input.Payload), input.Deleted,
		claims.UserID, s.clock().UTC(),
	).Scan(&cursor)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "catalog_failed", "The catalog update could not be saved.")
		return
	}
	if err = tx.Commit(); err != nil {
		writeError(w, http.StatusInternalServerError, "catalog_failed", "The catalog update could not be saved.")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"accepted": true, "duplicate": false, "cursor": cursor, "revision": nextRevision,
	})
}

func writeCatalogConflict(w http.ResponseWriter, revision int64, payload []byte, deleted bool) {
	var current json.RawMessage
	if len(payload) > 0 {
		current = payload
	}
	writeJSON(w, http.StatusConflict, map[string]any{
		"error":           "catalog_revision_conflict",
		"message":         "Another device changed this catalog record. Review the latest version before retrying.",
		"currentRevision": revision,
		"currentPayload":  current,
		"deleted":         deleted,
	})
}

func (s *Server) listCatalogChanges(w http.ResponseWriter, r *http.Request) {
	after, err := strconv.ParseInt(r.URL.Query().Get("after"), 10, 64)
	if err != nil || after < 0 {
		writeError(w, http.StatusBadRequest, "invalid_cursor", "The catalog cursor is invalid.")
		return
	}
	claims := claimsFrom(r)
	rows, err := s.db.QueryContext(r.Context(),
		`SELECT cursor, entity_type, entity_id, mutation_id, base_revision,
		 revision, payload, is_deleted, changed_at
		 FROM catalog_changes WHERE shop_id = $1 AND cursor > $2
		 ORDER BY cursor ASC LIMIT 500`, claims.ShopID, after,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "catalog_failed", "Catalog updates could not be loaded.")
		return
	}
	defer rows.Close()
	changes := make([]map[string]any, 0)
	cursor := after
	for rows.Next() {
		var eventCursor, baseRevision, revision int64
		var entityType, entityID, mutationID string
		var payload []byte
		var deleted bool
		var changedAt time.Time
		if err = rows.Scan(&eventCursor, &entityType, &entityID, &mutationID,
			&baseRevision, &revision, &payload, &deleted, &changedAt); err != nil {
			writeError(w, http.StatusInternalServerError, "catalog_failed", "Catalog updates could not be loaded.")
			return
		}
		changes = append(changes, map[string]any{
			"cursor": eventCursor, "entityType": entityType, "entityId": entityID,
			"mutationId": mutationID, "baseRevision": baseRevision,
			"revision": revision, "payload": json.RawMessage(payload),
			"deleted": deleted, "changedAt": changedAt.UTC(),
		})
		cursor = eventCursor
	}
	if err = rows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, "catalog_failed", "Catalog updates could not be loaded.")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"changes": changes, "cursor": cursor})
}

func validateCatalogMutation(input catalogMutation) error {
	if input.EntityType != "product" && input.EntityType != "customer" && input.EntityType != "settings" && input.EntityType != "supplier" && input.EntityType != "staff" {
		return errors.New("unsupported catalog entity")
	}
	if !uuidPattern.MatchString(input.EntityID) || !uuidPattern.MatchString(input.MutationID) ||
		input.BaseRevision < 0 || len(input.Payload) == 0 || len(input.Payload) > 512*1024 {
		return errors.New("invalid catalog mutation")
	}
	var payload map[string]json.RawMessage
	if json.Unmarshal(input.Payload, &payload) != nil || payload == nil || len(payload) == 0 {
		return errors.New("catalog payload must be an object")
	}
	var payloadID, name string
	if json.Unmarshal(payload["syncId"], &payloadID) != nil ||
		!uuidPattern.MatchString(payloadID) || !strings.EqualFold(payloadID, input.EntityID) ||
		json.Unmarshal(payload["name"], &name) != nil || strings.TrimSpace(name) == "" || len(name) > 200 {
		return errors.New("catalog payload identity or name is invalid")
	}
	if input.EntityType == "settings" {
		if input.EntityID != "00000000-0000-4000-8000-000000000001" {
			return errors.New("invalid shop settings identity")
		}
		allowed := map[string]bool{
			"syncId": true, "name": true, "currencySymbol": true,
			"currencyLocale": true, "taxRate": true, "showTax": true,
			"shopName": true, "shopPhone": true, "shopAddress": true,
			"setupComplete": true,
		}
		for key := range payload {
			if !allowed[key] {
				return errors.New("shop settings contain an unsupported field")
			}
		}
		for key := range allowed {
			if _, exists := payload[key]; !exists {
				return errors.New("shop settings payload is incomplete")
			}
		}
		var symbol, locale, shopName, shopPhone, shopAddress string
		var taxRate float64
		var showTax, setupComplete bool
		if json.Unmarshal(payload["currencySymbol"], &symbol) != nil || symbol == "" || len([]rune(symbol)) > 8 ||
			json.Unmarshal(payload["currencyLocale"], &locale) != nil || locale == "" || len(locale) > 32 ||
			json.Unmarshal(payload["taxRate"], &taxRate) != nil || taxRate < 0 || taxRate > 100 ||
			json.Unmarshal(payload["showTax"], &showTax) != nil ||
			json.Unmarshal(payload["shopName"], &shopName) != nil || len(shopName) > 200 ||
			json.Unmarshal(payload["shopPhone"], &shopPhone) != nil || len(shopPhone) > 40 ||
			json.Unmarshal(payload["shopAddress"], &shopAddress) != nil || len(shopAddress) > 500 ||
			json.Unmarshal(payload["setupComplete"], &setupComplete) != nil {
			return errors.New("shop settings payload is invalid")
		}
	}
	if input.EntityType == "supplier" {
		var phone, address, notes string
		if json.Unmarshal(payload["phone"], &phone) != nil || len(phone) > 40 ||
			json.Unmarshal(payload["address"], &address) != nil || len(address) > 500 ||
			json.Unmarshal(payload["notes"], &notes) != nil || len(notes) > 1000 {
			return errors.New("supplier payload is invalid")
		}
		for _, key := range []string{"phone", "address", "notes"} {
			if _, exists := payload[key]; !exists {
				return errors.New("supplier payload is incomplete")
			}
		}
	}
	if input.EntityType == "staff" {
		allowed := map[string]bool{
			"syncId": true, "name": true, "role": true, "pinSalt": true,
			"pinHash": true, "active": true, "createdAt": true,
		}
		for key := range payload {
			if !allowed[key] {
				return errors.New("staff payload contains an unsupported field")
			}
		}
		var role, salt, hash, createdAt string
		var active bool
		if json.Unmarshal(payload["role"], &role) != nil || (role != "owner" && role != "cashier") ||
			json.Unmarshal(payload["pinSalt"], &salt) != nil || !staffPinSaltPattern.MatchString(salt) ||
			json.Unmarshal(payload["pinHash"], &hash) != nil || !staffPinHashPattern.MatchString(hash) ||
			json.Unmarshal(payload["active"], &active) != nil ||
			json.Unmarshal(payload["createdAt"], &createdAt) != nil {
			return errors.New("staff payload is invalid")
		}
		if _, err := time.Parse(time.RFC3339Nano, createdAt); err != nil {
			return errors.New("staff creation date is invalid")
		}
	}
	if input.EntityType == "product" {
		if raw, exists := payload["imageData"]; exists && string(raw) != "null" {
			var encoded string
			if json.Unmarshal(raw, &encoded) != nil {
				return errors.New("product image is invalid")
			}
			if encoded != "" {
				bytes, err := base64.StdEncoding.DecodeString(encoded)
				if err != nil || len(bytes) == 0 || len(bytes) > 280*1024 ||
					len(bytes) < 3 || bytes[0] != 0xff || bytes[1] != 0xd8 || bytes[2] != 0xff {
					return errors.New("product image is invalid")
				}
			}
		}
	}
	return nil
}
