package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/fsnotify/fsnotify"
	"github.com/google/uuid"
	"github.com/grappl/shared/db"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	defaultInputFolder      = "/data/input"
	defaultProcessingFolder = "/data/processing"
	defaultInferenceURL     = "http://inference.grappl.svc.cluster.local/process"
	httpAddr                = ":8080"
	maxPathLength           = 4096
	maxURILength            = 2048
	fileSettleWait          = 2 * time.Second
	fileStableWindow        = time.Second
	httpTimeout             = 10 * time.Second
)

type config struct {
	InputFolder      string
	ProcessingFolder string
	InferenceURL     string
}

type ingestService struct {
	cfg         config
	logger      *slog.Logger
	pool        *pgxpool.Pool
	watcher     *fsnotify.Watcher
	httpClient  *http.Client
	mu          sync.Mutex
	inFlightSet map[string]struct{}
}

type processRequest struct {
	SessionID string `json:"session_id"`
	FilePath  string `json:"file_path"`
}

type healthResponse struct {
	Status   string `json:"status"`
	Watching string `json:"watching"`
}

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	rootCtx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	cfg, err := loadConfig()
	if err != nil {
		logger.Error("failed to load config", "error", err.Error())
		os.Exit(1)
	}

	if err := os.MkdirAll(cfg.InputFolder, 0o755); err != nil {
		logger.Error("failed to create input folder", "error", err.Error(), "file_path", cfg.InputFolder)
		os.Exit(1)
	}
	if err := os.MkdirAll(cfg.ProcessingFolder, 0o755); err != nil {
		logger.Error("failed to create processing folder", "error", err.Error(), "file_path", cfg.ProcessingFolder)
		os.Exit(1)
	}

	pool, err := db.Connect(rootCtx)
	if err != nil {
		logger.Error("failed to connect to database", "error", err.Error())
		os.Exit(1)
	}
	defer pool.Close()

	logger.Info("database connected")
	logger.Info("starting ingest watcher", "watching", cfg.InputFolder)

	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		logger.Error("failed to initialize fsnotify watcher", "error", err.Error())
		os.Exit(1)
	}
	defer watcher.Close()

	svc := &ingestService{
		cfg:     cfg,
		logger:  logger,
		pool:    pool,
		watcher: watcher,
		httpClient: &http.Client{
			Timeout: httpTimeout,
		},
		inFlightSet: make(map[string]struct{}),
	}

	if err := svc.addWatchRecursive(cfg.InputFolder); err != nil {
		logger.Error("failed to register directory watcher", "error", err.Error(), "file_path", cfg.InputFolder)
		os.Exit(1)
	}

	httpServer := &http.Server{
		Addr:    httpAddr,
		Handler: svc.healthMux(),
	}

	serverErr := make(chan error, 1)
	go func() {
		err := httpServer.ListenAndServe()
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			serverErr <- err
		}
		close(serverErr)
	}()

	watchErr := make(chan error, 1)
	go func() {
		watchErr <- svc.watchLoop(rootCtx)
	}()

	select {
	case <-rootCtx.Done():
	case err := <-watchErr:
		if err != nil {
			logger.Error("watch loop terminated", "error", err.Error())
		}
	case err := <-serverErr:
		if err != nil {
			logger.Error("health server terminated", "error", err.Error())
		}
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := httpServer.Shutdown(shutdownCtx); err != nil {
		logger.Error("failed to shutdown health server", "error", err.Error())
	}
	logger.Info("Ingest watcher shutting down")
}

func loadConfig() (config, error) {
	inputFolder := strings.TrimSpace(os.Getenv("INPUT_FOLDER"))
	if inputFolder == "" {
		inputFolder = defaultInputFolder
	}
	if len(inputFolder) > maxPathLength {
		return config{}, fmt.Errorf("INPUT_FOLDER exceeds max length (%d)", maxPathLength)
	}
	inputFolder, err := filepath.Abs(filepath.Clean(inputFolder))
	if err != nil {
		return config{}, fmt.Errorf("resolve INPUT_FOLDER: %w", err)
	}

	inferenceURL := strings.TrimSpace(os.Getenv("INFERENCE_URL"))
	if inferenceURL == "" {
		inferenceURL = defaultInferenceURL
	}
	if len(inferenceURL) > maxURILength {
		return config{}, fmt.Errorf("INFERENCE_URL exceeds max length (%d)", maxURILength)
	}
	parsedURL, err := url.Parse(inferenceURL)
	if err != nil {
		return config{}, fmt.Errorf("parse INFERENCE_URL: %w", err)
	}
	if parsedURL.Scheme != "http" && parsedURL.Scheme != "https" {
		return config{}, errors.New("INFERENCE_URL must use http or https")
	}
	if strings.TrimSpace(parsedURL.Host) == "" {
		return config{}, errors.New("INFERENCE_URL host is required")
	}

	processingFolder, err := filepath.Abs(filepath.Clean(defaultProcessingFolder))
	if err != nil {
		return config{}, fmt.Errorf("resolve processing folder: %w", err)
	}

	return config{
		InputFolder:      inputFolder,
		ProcessingFolder: processingFolder,
		InferenceURL:     inferenceURL,
	}, nil
}

func (s *ingestService) healthMux() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		resp := healthResponse{Status: "ok", Watching: s.cfg.InputFolder}
		if err := json.NewEncoder(w).Encode(resp); err != nil {
			s.logger.Error("failed to encode health response", "error", err.Error())
		}
	})
	return mux
}

func (s *ingestService) watchLoop(ctx context.Context) error {
	for {
		select {
		case <-ctx.Done():
			return nil
		case err, ok := <-s.watcher.Errors:
			if !ok {
				return nil
			}
			s.logger.Error("watcher error", "error", err.Error())
		case event, ok := <-s.watcher.Events:
			if !ok {
				return nil
			}
			s.handleFsEvent(ctx, event)
		}
	}
}

func (s *ingestService) handleFsEvent(ctx context.Context, event fsnotify.Event) {
	if event.Name == "" {
		return
	}

	path, err := filepath.Abs(filepath.Clean(event.Name))
	if err != nil {
		s.logger.Error("failed to normalize event path", "error", err.Error(), "file_path", event.Name)
		return
	}

	if event.Op&fsnotify.Create != 0 {
		stat, statErr := os.Stat(path)
		if statErr == nil && stat.IsDir() {
			if addErr := s.addWatchRecursive(path); addErr != nil {
				s.logger.Error("failed to watch new directory", "error", addErr.Error(), "file_path", path)
			}
			return
		}
	}

	if (event.Op&fsnotify.Create == 0) && (event.Op&fsnotify.Write == 0) {
		return
	}
	if !isSupportedVideoPath(path) {
		return
	}
	if !s.tryAcquire(path) {
		return
	}

	go func(filePath string) {
		defer s.release(filePath)
		s.processVideoFile(ctx, filePath)
	}(path)
}

func (s *ingestService) addWatchRecursive(root string) error {
	root = filepath.Clean(root)
	return filepath.WalkDir(root, func(path string, d fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if !d.IsDir() {
			return nil
		}
		return s.watcher.Add(path)
	})
}

func (s *ingestService) processVideoFile(ctx context.Context, filePath string) {
	if err := ensurePathWithinRoot(filePath, s.cfg.InputFolder); err != nil {
		s.logger.Error("ignoring file outside input folder", "error", err.Error(), "file_path", filePath)
		return
	}
	if !waitForStableFile(filePath) {
		s.logger.Warn("file not stable after wait window", "file_path", filePath)
		return
	}

	session, err := db.CreateSession(ctx, s.pool, filePath)
	if err != nil {
		s.logger.Error("failed to create session", "error", err.Error(), "file_path", filePath)
		return
	}

	processingPath, err := s.moveToProcessing(session.ID, filePath)
	if err != nil {
		s.logger.Error("failed to move file to processing", "error", err.Error(), "session_id", session.ID.String(), "file_path", filePath)
		_ = db.UpdateSessionStatus(ctx, s.pool, session.ID, db.SessionStatusError, sanitizeErrorMessage(err.Error()))
		return
	}

	if err := db.UpdateSessionStatus(ctx, s.pool, session.ID, db.SessionStatusProcessing, ""); err != nil {
		s.logger.Error("failed to set session status to processing", "error", err.Error(), "session_id", session.ID.String(), "file_path", processingPath)
		return
	}

	if err := s.notifyInference(ctx, session.ID, processingPath); err != nil {
		s.logger.Error("failed to trigger inference", "error", err.Error(), "session_id", session.ID.String(), "file_path", processingPath)
		_ = db.UpdateSessionStatus(ctx, s.pool, session.ID, db.SessionStatusError, sanitizeErrorMessage(err.Error()))
		return
	}

	s.logger.Info("Session created: "+session.ID.String()+" for file: "+session.FileName, "session_id", session.ID.String(), "file_path", processingPath)
}

func (s *ingestService) moveToProcessing(sessionID uuid.UUID, sourcePath string) (string, error) {
	if sessionID == uuid.Nil {
		return "", errors.New("session_id is required")
	}
	sessionDir := filepath.Join(s.cfg.ProcessingFolder, sessionID.String())
	if err := ensurePathWithinRoot(sessionDir, s.cfg.ProcessingFolder); err != nil {
		return "", err
	}
	if err := os.MkdirAll(sessionDir, 0o755); err != nil {
		return "", fmt.Errorf("create session processing directory: %w", err)
	}

	targetPath := filepath.Join(sessionDir, filepath.Base(sourcePath))
	if err := ensurePathWithinRoot(targetPath, s.cfg.ProcessingFolder); err != nil {
		return "", err
	}
	if err := os.Rename(sourcePath, targetPath); err != nil {
		return "", fmt.Errorf("move video file: %w", err)
	}

	return targetPath, nil
}

func (s *ingestService) notifyInference(ctx context.Context, sessionID uuid.UUID, filePath string) error {
	reqBody := processRequest{
		SessionID: sessionID.String(),
		FilePath:  filePath,
	}

	payload, err := json.Marshal(reqBody)
	if err != nil {
		return fmt.Errorf("marshal process payload: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.cfg.InferenceURL, strings.NewReader(string(payload)))
	if err != nil {
		return fmt.Errorf("create inference request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("call inference endpoint: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < http.StatusOK || resp.StatusCode >= http.StatusMultipleChoices {
		return fmt.Errorf("inference endpoint returned status %d", resp.StatusCode)
	}
	return nil
}

func (s *ingestService) tryAcquire(path string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, exists := s.inFlightSet[path]; exists {
		return false
	}
	s.inFlightSet[path] = struct{}{}
	return true
}

func (s *ingestService) release(path string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.inFlightSet, path)
}

func ensurePathWithinRoot(path string, root string) error {
	pathAbs, err := filepath.Abs(filepath.Clean(path))
	if err != nil {
		return fmt.Errorf("resolve path: %w", err)
	}
	rootAbs, err := filepath.Abs(filepath.Clean(root))
	if err != nil {
		return fmt.Errorf("resolve root: %w", err)
	}
	rel, err := filepath.Rel(rootAbs, pathAbs)
	if err != nil {
		return fmt.Errorf("resolve relative path: %w", err)
	}
	if rel == "." {
		return nil
	}
	if strings.HasPrefix(rel, "..") {
		return fmt.Errorf("path escapes root: %s", pathAbs)
	}
	return nil
}

func waitForStableFile(path string) bool {
	time.Sleep(fileSettleWait)

	initial, err := os.Stat(path)
	if err != nil || initial.IsDir() {
		return false
	}

	time.Sleep(fileStableWindow)
	followUp, err := os.Stat(path)
	if err != nil || followUp.IsDir() {
		return false
	}

	return initial.Size() == followUp.Size()
}

func isSupportedVideoPath(path string) bool {
	if len(path) == 0 || len(path) > maxPathLength {
		return false
	}
	switch strings.ToLower(filepath.Ext(path)) {
	case ".mp4", ".mov", ".avi":
		return true
	default:
		return false
	}
}

func sanitizeErrorMessage(msg string) string {
	msg = strings.TrimSpace(msg)
	if len(msg) == 0 {
		return ""
	}
	const maxErrorLength = 500
	if len(msg) > maxErrorLength {
		return msg[:maxErrorLength]
	}
	return msg
}
