package api

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"
)

const refreshTokenLifetime = 30 * 24 * time.Hour

type tokenPair struct {
	AccessToken  string
	RefreshToken string
	ExpiresAt    time.Time
}

func createTokenPair(userID, shopID, role string, secret []byte, now time.Time) (tokenPair, error) {
	claims := tokenClaims{
		UserID: userID,
		ShopID: shopID,
		Role:   role,
		Issued: now.UTC().Unix(),
		Expiry: now.UTC().Add(accessTokenLifetime).Unix(),
	}
	accessToken, err := signToken(claims, secret)
	if err != nil {
		return tokenPair{}, err
	}
	bytes := make([]byte, 32)
	if _, err = rand.Read(bytes); err != nil {
		return tokenPair{}, err
	}
	return tokenPair{
		AccessToken:  accessToken,
		RefreshToken: base64.RawURLEncoding.EncodeToString(bytes),
		ExpiresAt:    now.UTC().Add(refreshTokenLifetime),
	}, nil
}

func hashRefreshToken(token string) string {
	digest := sha256.Sum256([]byte(token))
	return hex.EncodeToString(digest[:])
}

type claimsContextKey struct{}

func withClaims(r *http.Request, claims tokenClaims) *http.Request {
	return r.WithContext(context.WithValue(r.Context(), claimsContextKey{}, claims))
}

func claimsFrom(r *http.Request) tokenClaims {
	claims, _ := r.Context().Value(claimsContextKey{}).(tokenClaims)
	return claims
}

func signToken(claims tokenClaims, secret []byte) (string, error) {
	if len(secret) < 32 || claims.UserID == "" || claims.ShopID == "" ||
		(claims.Role != "owner" && claims.Role != "staff") || claims.Expiry <= claims.Issued {
		return "", errors.New("invalid signing inputs")
	}
	header, err := json.Marshal(map[string]string{"alg": "HS256", "typ": "JWT"})
	if err != nil {
		return "", err
	}
	payload, err := json.Marshal(claims)
	if err != nil {
		return "", err
	}
	unsigned := base64.RawURLEncoding.EncodeToString(header) + "." + base64.RawURLEncoding.EncodeToString(payload)
	mac := hmac.New(sha256.New, secret)
	_, _ = mac.Write([]byte(unsigned))
	return unsigned + "." + base64.RawURLEncoding.EncodeToString(mac.Sum(nil)), nil
}

func verifyToken(token string, secret []byte, now time.Time) (tokenClaims, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 || len(secret) < 32 {
		return tokenClaims{}, errors.New("invalid token")
	}
	headerJSON, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return tokenClaims{}, errors.New("invalid token")
	}
	var header struct {
		Algorithm string `json:"alg"`
		Type      string `json:"typ"`
	}
	if json.Unmarshal(headerJSON, &header) != nil || header.Algorithm != "HS256" || header.Type != "JWT" {
		return tokenClaims{}, errors.New("invalid token")
	}
	providedMAC, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		return tokenClaims{}, errors.New("invalid token")
	}
	mac := hmac.New(sha256.New, secret)
	_, _ = mac.Write([]byte(parts[0] + "." + parts[1]))
	if !hmac.Equal(providedMAC, mac.Sum(nil)) {
		return tokenClaims{}, errors.New("invalid token")
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return tokenClaims{}, errors.New("invalid token")
	}
	var claims tokenClaims
	if json.Unmarshal(payload, &claims) != nil || claims.UserID == "" || claims.ShopID == "" ||
		(claims.Role != "owner" && claims.Role != "staff") || claims.Expiry <= now.Unix() ||
		claims.Issued > now.Add(time.Minute).Unix() || claims.Expiry <= claims.Issued {
		return tokenClaims{}, errors.New("invalid token")
	}
	return claims, nil
}
