package db

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	maxConns          int32         = 10
	minConns          int32         = 2
	healthCheckPeriod time.Duration = time.Minute
	maxConnectRetries int           = 5
	maxTextLength     int           = 10_000
)

type SessionStatus string

const (
	SessionStatusQueued            SessionStatus = "queued"
	SessionStatusProcessing        SessionStatus = "processing"
	SessionStatusInferenceComplete SessionStatus = "inference_complete"
	SessionStatusClipsReady        SessionStatus = "clips_ready"
	SessionStatusComplete          SessionStatus = "complete"
	SessionStatusError             SessionStatus = "error"
)

type Practitioner struct {
	ID        uuid.UUID
	Name      string
	CreatedAt time.Time
}

type Session struct {
	ID              uuid.UUID
	PractitionerID  uuid.UUID
	FileName        string
	FilePath        string
	Status          SessionStatus
	ErrorMessage    *string
	SchemaVersion   int
	DurationSeconds *int
	CreatedAt       time.Time
	UpdatedAt       time.Time
}

type EventType struct {
	ID       uuid.UUID
	Slug     string
	Label    string
	Category string
}

type Event struct {
	ID             uuid.UUID
	SessionID      uuid.UUID
	PractitionerID uuid.UUID
	EventTypeID    uuid.UUID
	StartMS        int
	EndMS          int
	Confidence     float64
	BoundingBox    []byte
	LowConfidence  bool
	CreatedAt      time.Time
}

type Clip struct {
	ID              uuid.UUID
	EventID         uuid.UUID
	PractitionerID  uuid.UUID
	FilePath        string
	ThumbnailPath   *string
	DurationSeconds *float64
	CreatedAt       time.Time
}

type CoachingNote struct {
	ID            uuid.UUID
	ClipID        uuid.UUID
	Content       string
	PromptVersion int
	Model         string
	CreatedAt     time.Time
}

type SessionSummary struct {
	ID            uuid.UUID
	SessionID     uuid.UUID
	Content       string
	PromptVersion int
	Model         string
	CreatedAt     time.Time
}

func Connect(ctx context.Context) (*pgxpool.Pool, error) {
	databaseURL := strings.TrimSpace(os.Getenv("DATABASE_URL"))
	if databaseURL == "" {
		return nil, errors.New("DATABASE_URL is required")
	}
	if len(databaseURL) > maxTextLength {
		return nil, errors.New("DATABASE_URL exceeds allowed length")
	}
	if !strings.HasPrefix(databaseURL, "postgres://") && !strings.HasPrefix(databaseURL, "postgresql://") {
		return nil, errors.New("DATABASE_URL must use postgres scheme")
	}

	cfg, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return nil, fmt.Errorf("parse database config: %w", err)
	}
	cfg.MaxConns = maxConns
	cfg.MinConns = minConns
	cfg.HealthCheckPeriod = healthCheckPeriod

	var lastErr error
	backoff := time.Second
	for attempt := 1; attempt <= maxConnectRetries; attempt++ {
		pool, poolErr := pgxpool.NewWithConfig(ctx, cfg)
		if poolErr == nil {
			pingErr := pool.Ping(ctx)
			if pingErr == nil {
				return pool, nil
			}
			lastErr = fmt.Errorf("ping attempt %d/%d failed: %w", attempt, maxConnectRetries, pingErr)
			pool.Close()
		} else {
			lastErr = fmt.Errorf("connect attempt %d/%d failed: %w", attempt, maxConnectRetries, poolErr)
		}

		if attempt == maxConnectRetries {
			break
		}

		select {
		case <-ctx.Done():
			return nil, fmt.Errorf("connect canceled: %w", ctx.Err())
		case <-time.After(backoff):
		}
		backoff *= 2
	}

	return nil, fmt.Errorf("database connection failed after %d attempts: %w", maxConnectRetries, lastErr)
}

func GetDefaultPractitioner(ctx context.Context, pool *pgxpool.Pool) (*Practitioner, error) {
	if pool == nil {
		return nil, errors.New("pool is required")
	}

	row := pool.QueryRow(ctx, `
		SELECT id, name, created_at
		FROM public.practitioners
		ORDER BY created_at ASC
		LIMIT 1
	`)

	var out Practitioner
	if err := row.Scan(&out.ID, &out.Name, &out.CreatedAt); err != nil {
		return nil, fmt.Errorf("get default practitioner: %w", err)
	}
	return &out, nil
}

func CreateSession(ctx context.Context, pool *pgxpool.Pool, filePath string) (*Session, error) {
	if pool == nil {
		return nil, errors.New("pool is required")
	}
	filePath = strings.TrimSpace(filePath)
	if filePath == "" {
		return nil, errors.New("filePath is required")
	}
	if len(filePath) > maxTextLength {
		return nil, errors.New("filePath exceeds allowed length")
	}
	fileName := filepath.Base(filePath)
	if fileName == "." || fileName == "/" || strings.TrimSpace(fileName) == "" {
		return nil, errors.New("filePath must include a file name")
	}

	practitioner, err := GetDefaultPractitioner(ctx, pool)
	if err != nil {
		return nil, err
	}

	row := pool.QueryRow(ctx, `
		INSERT INTO public.sessions (practitioner_id, file_name, file_path, status)
		VALUES ($1, $2, $3, $4)
		RETURNING id, practitioner_id, file_name, file_path, status, error_message, schema_version, duration_seconds, created_at, updated_at
	`, practitioner.ID, fileName, filePath, SessionStatusQueued)

	var out Session
	var status string
	var errorMessage *string
	var durationSeconds *int
	if scanErr := row.Scan(
		&out.ID,
		&out.PractitionerID,
		&out.FileName,
		&out.FilePath,
		&status,
		&errorMessage,
		&out.SchemaVersion,
		&durationSeconds,
		&out.CreatedAt,
		&out.UpdatedAt,
	); scanErr != nil {
		return nil, fmt.Errorf("create session: %w", scanErr)
	}

	out.Status = SessionStatus(status)
	out.ErrorMessage = errorMessage
	out.DurationSeconds = durationSeconds
	return &out, nil
}

func UpdateSessionStatus(ctx context.Context, pool *pgxpool.Pool, id uuid.UUID, status SessionStatus, errMsg string) error {
	if pool == nil {
		return errors.New("pool is required")
	}
	if id == uuid.Nil {
		return errors.New("session id is required")
	}
	if !isValidSessionStatus(status) {
		return fmt.Errorf("invalid session status: %q", status)
	}
	if len(errMsg) > maxTextLength {
		return errors.New("error message exceeds allowed length")
	}

	_, err := pool.Exec(ctx, `
		UPDATE public.sessions
		SET status = $2, error_message = NULLIF($3, '')
		WHERE id = $1
	`, id, string(status), strings.TrimSpace(errMsg))
	if err != nil {
		return fmt.Errorf("update session status: %w", err)
	}
	return nil
}

func GetEventTypeBySlug(ctx context.Context, pool *pgxpool.Pool, slug string) (*EventType, error) {
	if pool == nil {
		return nil, errors.New("pool is required")
	}
	slug = strings.TrimSpace(slug)
	if slug == "" {
		return nil, errors.New("slug is required")
	}
	if len(slug) > 120 {
		return nil, errors.New("slug exceeds allowed length")
	}

	row := pool.QueryRow(ctx, `
		SELECT id, slug, label, category
		FROM public.event_types
		WHERE slug = $1
	`, slug)

	var out EventType
	if err := row.Scan(&out.ID, &out.Slug, &out.Label, &out.Category); err != nil {
		return nil, fmt.Errorf("get event type by slug: %w", err)
	}
	return &out, nil
}

func CreateEvent(ctx context.Context, pool *pgxpool.Pool, event Event) (*Event, error) {
	if pool == nil {
		return nil, errors.New("pool is required")
	}
	if event.SessionID == uuid.Nil || event.PractitionerID == uuid.Nil || event.EventTypeID == uuid.Nil {
		return nil, errors.New("session_id, practitioner_id, and event_type_id are required")
	}
	if event.StartMS < 0 || event.EndMS < 0 || event.EndMS < event.StartMS {
		return nil, errors.New("invalid event timing")
	}
	if event.Confidence < 0 || event.Confidence > 1 {
		return nil, errors.New("confidence must be between 0 and 1")
	}

	row := pool.QueryRow(ctx, `
		INSERT INTO public.events (
			session_id, practitioner_id, event_type_id, start_ms, end_ms, confidence, bounding_box
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING id, session_id, practitioner_id, event_type_id, start_ms, end_ms, confidence, bounding_box, low_confidence, created_at
	`,
		event.SessionID, event.PractitionerID, event.EventTypeID, event.StartMS, event.EndMS, event.Confidence, event.BoundingBox,
	)

	var out Event
	var bbox []byte
	if err := row.Scan(
		&out.ID, &out.SessionID, &out.PractitionerID, &out.EventTypeID,
		&out.StartMS, &out.EndMS, &out.Confidence, &bbox, &out.LowConfidence, &out.CreatedAt,
	); err != nil {
		return nil, fmt.Errorf("create event: %w", err)
	}
	out.BoundingBox = bbox
	return &out, nil
}

func GetEventsBySession(ctx context.Context, pool *pgxpool.Pool, sessionID uuid.UUID) ([]Event, error) {
	if pool == nil {
		return nil, errors.New("pool is required")
	}
	if sessionID == uuid.Nil {
		return nil, errors.New("sessionID is required")
	}

	rows, err := pool.Query(ctx, `
		SELECT id, session_id, practitioner_id, event_type_id, start_ms, end_ms, confidence, bounding_box, low_confidence, created_at
		FROM public.events
		WHERE session_id = $1
		ORDER BY start_ms ASC
	`, sessionID)
	if err != nil {
		return nil, fmt.Errorf("get events by session: %w", err)
	}
	defer rows.Close()

	results := make([]Event, 0)
	for rows.Next() {
		var item Event
		var bbox []byte
		if scanErr := rows.Scan(
			&item.ID, &item.SessionID, &item.PractitionerID, &item.EventTypeID,
			&item.StartMS, &item.EndMS, &item.Confidence, &bbox, &item.LowConfidence, &item.CreatedAt,
		); scanErr != nil {
			return nil, fmt.Errorf("scan event: %w", scanErr)
		}
		item.BoundingBox = bbox
		results = append(results, item)
	}
	if rowsErr := rows.Err(); rowsErr != nil {
		return nil, fmt.Errorf("iterate events: %w", rowsErr)
	}

	return results, nil
}

func CreateClip(ctx context.Context, pool *pgxpool.Pool, clip Clip) (*Clip, error) {
	if pool == nil {
		return nil, errors.New("pool is required")
	}
	if clip.EventID == uuid.Nil || clip.PractitionerID == uuid.Nil {
		return nil, errors.New("event_id and practitioner_id are required")
	}
	clip.FilePath = strings.TrimSpace(clip.FilePath)
	if clip.FilePath == "" {
		return nil, errors.New("file_path is required")
	}
	if len(clip.FilePath) > maxTextLength {
		return nil, errors.New("file_path exceeds allowed length")
	}
	if clip.ThumbnailPath != nil && len(strings.TrimSpace(*clip.ThumbnailPath)) > maxTextLength {
		return nil, errors.New("thumbnail_path exceeds allowed length")
	}
	if clip.DurationSeconds != nil && *clip.DurationSeconds < 0 {
		return nil, errors.New("duration_seconds must be non-negative")
	}

	row := pool.QueryRow(ctx, `
		INSERT INTO public.clips (event_id, practitioner_id, file_path, thumbnail_path, duration_seconds)
		VALUES ($1, $2, $3, NULLIF($4, ''), $5)
		RETURNING id, event_id, practitioner_id, file_path, thumbnail_path, duration_seconds, created_at
	`,
		clip.EventID,
		clip.PractitionerID,
		clip.FilePath,
		nullSafeTrim(clip.ThumbnailPath),
		clip.DurationSeconds,
	)

	var out Clip
	if err := row.Scan(
		&out.ID, &out.EventID, &out.PractitionerID, &out.FilePath, &out.ThumbnailPath, &out.DurationSeconds, &out.CreatedAt,
	); err != nil {
		return nil, fmt.Errorf("create clip: %w", err)
	}
	return &out, nil
}

func CreateCoachingNote(ctx context.Context, pool *pgxpool.Pool, note CoachingNote) (*CoachingNote, error) {
	if pool == nil {
		return nil, errors.New("pool is required")
	}
	if note.ClipID == uuid.Nil {
		return nil, errors.New("clip_id is required")
	}
	note.Content = strings.TrimSpace(note.Content)
	note.Model = strings.TrimSpace(note.Model)
	if note.Content == "" || note.Model == "" {
		return nil, errors.New("content and model are required")
	}
	if len(note.Content) > maxTextLength || len(note.Model) > 255 {
		return nil, errors.New("content or model exceeds allowed length")
	}
	if note.PromptVersion <= 0 {
		return nil, errors.New("prompt_version must be positive")
	}

	row := pool.QueryRow(ctx, `
		INSERT INTO public.coaching_notes (clip_id, content, prompt_version, model)
		VALUES ($1, $2, $3, $4)
		RETURNING id, clip_id, content, prompt_version, model, created_at
	`, note.ClipID, note.Content, note.PromptVersion, note.Model)

	var out CoachingNote
	if err := row.Scan(&out.ID, &out.ClipID, &out.Content, &out.PromptVersion, &out.Model, &out.CreatedAt); err != nil {
		return nil, fmt.Errorf("create coaching note: %w", err)
	}
	return &out, nil
}

func CreateSessionSummary(ctx context.Context, pool *pgxpool.Pool, summary SessionSummary) (*SessionSummary, error) {
	if pool == nil {
		return nil, errors.New("pool is required")
	}
	if summary.SessionID == uuid.Nil {
		return nil, errors.New("session_id is required")
	}
	summary.Content = strings.TrimSpace(summary.Content)
	summary.Model = strings.TrimSpace(summary.Model)
	if summary.Content == "" || summary.Model == "" {
		return nil, errors.New("content and model are required")
	}
	if len(summary.Content) > maxTextLength || len(summary.Model) > 255 {
		return nil, errors.New("content or model exceeds allowed length")
	}
	if summary.PromptVersion <= 0 {
		return nil, errors.New("prompt_version must be positive")
	}

	row := pool.QueryRow(ctx, `
		INSERT INTO public.session_summaries (session_id, content, prompt_version, model)
		VALUES ($1, $2, $3, $4)
		RETURNING id, session_id, content, prompt_version, model, created_at
	`, summary.SessionID, summary.Content, summary.PromptVersion, summary.Model)

	var out SessionSummary
	if err := row.Scan(&out.ID, &out.SessionID, &out.Content, &out.PromptVersion, &out.Model, &out.CreatedAt); err != nil {
		return nil, fmt.Errorf("create session summary: %w", err)
	}
	return &out, nil
}

func isValidSessionStatus(status SessionStatus) bool {
	switch status {
	case SessionStatusQueued,
		SessionStatusProcessing,
		SessionStatusInferenceComplete,
		SessionStatusClipsReady,
		SessionStatusComplete,
		SessionStatusError:
		return true
	default:
		return false
	}
}

func nullSafeTrim(value *string) *string {
	if value == nil {
		return nil
	}
	trimmed := strings.TrimSpace(*value)
	return &trimmed
}

var _ pgx.Row
