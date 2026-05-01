package db

import (
	"context"
	"os"
	"testing"
	"time"
)

func setupTestPool(t *testing.T) context.Context {
	t.Helper()
	if os.Getenv("DATABASE_URL") == "" {
		t.Skip("DATABASE_URL not set; skipping integration tests")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	t.Cleanup(cancel)
	return ctx
}

func TestConnect(t *testing.T) {
	ctx := setupTestPool(t)
	pool, err := Connect(ctx)
	if err != nil {
		t.Fatalf("Connect() error = %v", err)
	}
	t.Cleanup(pool.Close)
}

func TestGetDefaultPractitioner(t *testing.T) {
	ctx := setupTestPool(t)
	pool, err := Connect(ctx)
	if err != nil {
		t.Fatalf("Connect() error = %v", err)
	}
	t.Cleanup(pool.Close)

	practitioner, err := GetDefaultPractitioner(ctx, pool)
	if err != nil {
		t.Fatalf("GetDefaultPractitioner() error = %v", err)
	}
	if practitioner == nil {
		t.Fatal("GetDefaultPractitioner() returned nil")
	}
	if practitioner.ID.String() == "" {
		t.Fatal("GetDefaultPractitioner() returned empty id")
	}
	if practitioner.Name == "" {
		t.Fatal("GetDefaultPractitioner() returned empty name")
	}
}

func TestCreateSession(t *testing.T) {
	ctx := setupTestPool(t)
	pool, err := Connect(ctx)
	if err != nil {
		t.Fatalf("Connect() error = %v", err)
	}
	t.Cleanup(pool.Close)

	session, err := CreateSession(ctx, pool, "/tmp/grappl-test-video.mp4")
	if err != nil {
		t.Fatalf("CreateSession() error = %v", err)
	}
	if session == nil {
		t.Fatal("CreateSession() returned nil")
	}
	if session.ID.String() == "" {
		t.Fatal("CreateSession() returned empty id")
	}
	if session.FileName != "grappl-test-video.mp4" {
		t.Fatalf("CreateSession() file name = %q, want %q", session.FileName, "grappl-test-video.mp4")
	}
	if session.Status != SessionStatusQueued {
		t.Fatalf("CreateSession() status = %q, want %q", session.Status, SessionStatusQueued)
	}
}
