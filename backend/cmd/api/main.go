package main

import (
	"context"
	"database/sql"
	"errors"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"karbar/backend/internal/api"
)

func main() {
	databaseURL := strings.TrimSpace(os.Getenv("DATABASE_URL"))
	jwtSecret := os.Getenv("JWT_SECRET")
	if databaseURL == "" {
		log.Fatal("DATABASE_URL is required")
	}
	if len(jwtSecret) < 32 {
		log.Fatal("JWT_SECRET must contain at least 32 characters")
	}

	db, err := sql.Open("postgres", databaseURL)
	if err != nil {
		log.Fatalf("open database: %v", err)
	}
	defer db.Close()
	db.SetMaxOpenConns(20)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(30 * time.Minute)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err = db.PingContext(ctx); err != nil {
		log.Fatalf("connect to database: %v", err)
	}

	port := strings.TrimSpace(os.Getenv("PORT"))
	if port == "" {
		port = "8080"
	}
	server := &http.Server{
		Addr:              ":" + port,
		Handler:           api.NewServer(db, jwtSecret, os.Getenv("REGISTRATION_SECRET")).Handler(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      35 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
	log.Printf("Karbar sync API listening on :%s", port)
	if err = server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("serve API: %v", err)
	}
}
