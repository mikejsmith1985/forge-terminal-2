// Package terminal provides WebSocket terminal handler.
package terminal

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/mikejsmith1985/forge-terminal/internal/am"
	"github.com/mikejsmith1985/forge-terminal/internal/assistant"
	"github.com/mikejsmith1985/forge-terminal/internal/terminal/vision"
)

// Custom WebSocket close codes (4000-4999 range is for application use)
const (
	CloseCodePTYExited = 4000 // Shell process exited normally
	CloseCodeTimeout   = 4001 // Session timed out
	CloseCodePTYError  = 4002 // PTY read/write error
)

// Handler manages WebSocket terminal connections.
type Handler struct {
	upgrader      websocket.Upgrader
	sessions      sync.Map // map[string]*TerminalSession
	assistantCore *assistant.Core
	assistant     assistant.Service
}

// wsMessage represents a message to be written to the WebSocket.
// All writes go through a single channel to eliminate race conditions.
type wsMessage struct {
	messageType int    // websocket.BinaryMessage or websocket.TextMessage
	data        []byte // For binary messages
	json        any    // For JSON messages (if data is nil, marshal this)
}

// ResizeMessage represents a terminal resize request from the client.
type ResizeMessage struct {
	Type string `json:"type"`
	Cols uint16 `json:"cols"`
	Rows uint16 `json:"rows"`
}

// VisionControlMessage represents vision control commands from client.
type VisionControlMessage struct {
	Type    string `json:"type"` // "VISION_ENABLE", "VISION_DISABLE", "INJECT_COMMAND"
	Command string `json:"command,omitempty"`
}

// VisionOverlayMessage represents vision overlay data sent to client.
type VisionOverlayMessage struct {
	Type        string                 `json:"type"` // "VISION_OVERLAY"
	OverlayType string                 `json:"overlayType"`
	Payload     map[string]interface{} `json:"payload"`
}

// AMControlMessage represents AM control commands from client.
type AMControlMessage struct {
	Type        string `json:"type"` // "AM_AUTO_RESPOND"
	AutoRespond bool   `json:"autoRespond"`
}

// NewHandler creates a new terminal WebSocket handler.
func NewHandler(service assistant.Service, core *assistant.Core) *Handler {
	return &Handler{
		upgrader: websocket.Upgrader{
			CheckOrigin: func(r *http.Request) bool {
				// Check allowed origins for GitHub Pages deployment support
				origin := r.Header.Get("Origin")

				// Allow localhost for local development
				if strings.HasPrefix(origin, "http://localhost") || strings.HasPrefix(origin, "http://127.0.0.1") {
					return true
				}

				// Allow GitHub Pages deployments (github.io domain)
				if strings.Contains(origin, ".github.io") {
					return true
				}

				// Allow GitHub Codespaces
				if strings.Contains(origin, "app.github.dev") || strings.Contains(origin, ".csb.app") {
					return true
				}

				// Allow any origin for backward compatibility (can be restricted via ALLOWED_ORIGINS env var)
				return true
			},
			ReadBufferSize:  1024,
			WriteBufferSize: 1024,
		},
		assistantCore: core,
		assistant:     service,
	}
}

// HandleWebSocket upgrades the HTTP connection to WebSocket and manages PTY I/O.
func (h *Handler) HandleWebSocket(w http.ResponseWriter, r *http.Request) {
	// Upgrade to WebSocket
	conn, err := h.upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[Terminal] Failed to upgrade connection: %v", err)
		return
	}
	defer conn.Close()

	// Parse shell config from query params
	query := r.URL.Query()
	shellConfig := &ShellConfig{
		ShellType:   query.Get("shell"),
		WSLDistro:   query.Get("distro"),
		WSLHomePath: query.Get("wslHome"),
		CmdHomePath: query.Get("cmdHome"),
		PSHomePath:  query.Get("psHome"),
	}

	// Get tabID from query params (for AM/LLM logging)
	// If not provided, fall back to WebSocket session ID
	tabID := query.Get("tabId")
	if tabID == "" {
		tabID = uuid.New().String()
		log.Printf("[Terminal] Warning: No tabID provided, using session ID: %s", tabID)
	}

	// Create terminal session with config
	sessionID := tabID // Use tabID as session ID for consistency
	session, err := NewTerminalSessionWithConfig(sessionID, shellConfig)
	if err != nil {
		log.Printf("[Terminal] Failed to create session: %v", err)
		_ = conn.WriteJSON(map[string]string{"error": "Failed to create terminal session: " + err.Error()})
		return
	}
	defer func() {
		session.Close()
		h.sessions.Delete(sessionID)
	}()

	h.sessions.Store(sessionID, session)
	log.Printf("[Terminal] Session %s created (shell: %s, tabID: %s)", sessionID, shellConfig.ShellType, tabID)

	// Set initial terminal size (default 80x24)
	_ = session.Resize(80, 24)

	// ═══════════════════════════════════════════════════════════════════════════
	// CHANNEL-BASED ARCHITECTURE FOR FREEZE PREVENTION
	// ═══════════════════════════════════════════════════════════════════════════
	//
	// Problem: gorilla/websocket is NOT thread-safe for concurrent writes.
	// Previously, multiple goroutines wrote simultaneously:
	// - PTY reader goroutine (main terminal output)
	// - Vision parser goroutines (overlay messages)
	// - AM callback goroutines (low-confidence notifications)
	//
	// Solution: All writes go through a single buffered channel.
	// One dedicated writer goroutine processes the channel sequentially.
	// This eliminates all race conditions and prevents freezes.
	// ═══════════════════════════════════════════════════════════════════════════

	// Buffered channel for WebSocket writes - large enough to avoid blocking
	writeChan := make(chan wsMessage, 256)

	// Channel for Vision data processing
	visionChan := make(chan []byte, 64)

	// Channel for AM data processing
	amChan := make(chan string, 64)

	// Shutdown coordination
	done := make(chan struct{})
	var closeOnce sync.Once
	closeDone := func() { closeOnce.Do(func() { close(done) }) }

	// Get Vision parser from assistant core
	visionParser := h.assistantCore.GetVisionParser()

	// Initialize AM/Vision/LLM systems
	var llmLogger *am.LLMLogger
	var llmLoggerMu sync.RWMutex // Protects llmLogger access
	amSystem := h.assistantCore.GetAMSystem()

	// Initialize AM system (now synchronous since we need llmLogger for callbacks)
	if amSystem != nil {
		llmLoggerMu.Lock()
		llmLogger = amSystem.GetLLMLogger(tabID)
		llmLoggerMu.Unlock()

		if llmLogger != nil {
			activeConv := llmLogger.GetActiveConversationID()
			log.Printf("[Terminal] Using LLM logger for tabID: %s, activeConv: %s", tabID, activeConv)
		} else {
			log.Printf("[Terminal] NO LLM logger available for tabID: %s", tabID)
		}

		// Record PTY heartbeat for Layer 1
		if amSystem.HealthMonitor != nil {
			amSystem.HealthMonitor.RecordPTYHeartbeat()
		}

		// Initialize Vision Insights tracker
		cwd, _ := os.Getwd()
		sessionInfo := vision.SessionInfo{
			TabID:      tabID,
			WorkingDir: cwd,
			ShellType:  shellConfig.ShellType,
			InAutoMode: false,
		}
		insightsTracker := vision.NewInsightsTracker(amSystem.AMDir, sessionInfo)
		visionParser.SetInsightsTracker(insightsTracker)
		log.Printf("[Terminal] Vision insights tracker initialized for session %s", sessionID)

		// Set up low-confidence callback for AM v2.0
		// This callback sends to writeChan instead of writing directly
		if llmLogger != nil {
			llmLogger.SetLowConfidenceCallback(func(raw string) {
				log.Printf("[AM] Low confidence parsing detected, queueing Vision notification")
				overlayMsg := VisionOverlayMessage{
					Type:        "VISION_OVERLAY",
					OverlayType: "AM_LOW_CONFIDENCE",
					Payload: map[string]interface{}{
						"message":     "AM detected low-confidence parsing. Raw data preserved for manual review.",
						"severity":    "warning",
						"autoRespond": true,
						"rawLength":   len(raw),
					},
				}
				select {
				case writeChan <- wsMessage{json: overlayMsg}:
				case <-done:
				}
			})
		}
		log.Printf("[Terminal] Session %s: AM system initialized with tabID %s", sessionID, tabID)
	}

	detector := h.assistantCore.GetLLMDetector()
	var inputBuffer strings.Builder
	const flushTimeout = 2 * time.Second

	// ═══ GOROUTINE 1: WebSocket Writer ═══
	// Single goroutine that handles ALL WebSocket writes
	// This eliminates race conditions entirely
	go func() {
		defer closeDone()

		var writeCount int64
		var slowWriteCount int64
		lastStatsReport := time.Now()

		for {
			select {
			case msg, ok := <-writeChan:
				if !ok {
					return // Channel closed
				}

				writeStart := time.Now()
				var err error

				if msg.json != nil {
					// JSON message
					err = conn.WriteJSON(msg.json)
				} else {
					// Binary message
					err = conn.WriteMessage(msg.messageType, msg.data)
				}

				writeDuration := time.Since(writeStart)
				writeCount++

				// Freeze detection logging
				if writeDuration > 100*time.Millisecond {
					slowWriteCount++
					log.Printf("[FREEZE-DETECT] Slow write: %v (total slow: %d)", writeDuration, slowWriteCount)
				}
				if writeDuration > 500*time.Millisecond {
					log.Printf("[FREEZE-CRITICAL] Write blocked for %v!", writeDuration)
				}

				// Periodic stats
				if time.Since(lastStatsReport) > 30*time.Second {
					log.Printf("[WS-STATS] Writes: %d, SlowWrites: %d, QueueLen: %d",
						writeCount, slowWriteCount, len(writeChan))
					lastStatsReport = time.Now()
				}

				if err != nil {
					log.Printf("[Terminal] WebSocket write error: %v", err)
					return
				}

			case <-done:
				return
			}
		}
	}()

	// ═══ GOROUTINE 2: Vision Worker ═══
	// Processes Vision data and queues overlay messages
	go func() {
		for {
			select {
			case data, ok := <-visionChan:
				if !ok {
					return
				}
				if visionParser.Enabled() {
					if match := visionParser.Feed(data); match != nil {
						overlayMsg := VisionOverlayMessage{
							Type:        "VISION_OVERLAY",
							OverlayType: match.Type,
							Payload:     match.Payload,
						}
						select {
						case writeChan <- wsMessage{json: overlayMsg}:
						case <-done:
							return
						}
					}
				}
			case <-done:
				return
			}
		}
	}()

	// ═══ GOROUTINE 3: AM Worker ═══
	// Processes AM data with time-based snapshot backup
	// This ensures TUI sessions are captured even if screen clear detection fails
	go func() {
		const snapshotInterval = 10 * time.Second // Time-based backup interval
		lastSnapshot := time.Now()
		activitySinceSnapshot := false

		snapshotTicker := time.NewTicker(snapshotInterval)
		defer snapshotTicker.Stop()

		for {
			select {
			case data, ok := <-amChan:
				if !ok {
					return
				}
				llmLoggerMu.RLock()
				logger := llmLogger
				llmLoggerMu.RUnlock()

				if logger != nil && logger.GetActiveConversationID() != "" {
					logger.AddOutput(data)
					activitySinceSnapshot = true
				}

			case <-snapshotTicker.C:
				// Time-based snapshot backup for TUI sessions
				// Only triggers if there's been activity since last snapshot
				llmLoggerMu.RLock()
				logger := llmLogger
				llmLoggerMu.RUnlock()

				if logger != nil && logger.IsTUICaptureMode() && activitySinceSnapshot {
					// Rate limit: ensure minimum interval between snapshots
					if time.Since(lastSnapshot) >= snapshotInterval {
						log.Printf("[AM-Worker] Time-based snapshot trigger (activity since last: %v)", time.Since(lastSnapshot))
						logger.TriggerPeriodicSnapshot()
						lastSnapshot = time.Now()
						activitySinceSnapshot = false
					}
				}

			case <-done:
				return
			}
		}
	}()

	// ═══ GOROUTINE 4: PTY Heartbeat ═══
	go func() {
		ticker := time.NewTicker(15 * time.Second)
		defer ticker.Stop()

		for {
			select {
			case <-ticker.C:
				if amSystem != nil && amSystem.HealthMonitor != nil {
					amSystem.HealthMonitor.RecordPTYHeartbeat()
				}
			case <-done:
				return
			}
		}
	}()

	// Channel to coordinate shutdown with reason
	type closeReason struct {
		code   int
		reason string
	}
	closeChan := make(chan closeReason, 1)

	// ═══ GOROUTINE 5: PTY Reader ═══
	// Reads from PTY and queues data to appropriate channels
	go func() {
		defer closeDone()
		buf := make([]byte, 4096)

		for {
			// Time PTY reads for freeze detection
			readStart := time.Now()
			n, err := session.Read(buf)
			readDuration := time.Since(readStart)

			if readDuration > 100*time.Millisecond {
				log.Printf("[FREEZE-DEBUG] Slow PTY read: %v for %d bytes", readDuration, n)
			}

			if err != nil {
				log.Printf("[Terminal] PTY read error: %v", err)
				select {
				case closeChan <- closeReason{CloseCodePTYError, "Terminal read error"}:
				default:
				}
				return
			}

			if n > 0 {
				// CRITICAL: Copy the buffer before sending to channels
				// The original buf is reused on the next Read() call
				dataCopy := make([]byte, n)
				copy(dataCopy, buf[:n])

				// Queue terminal output to WebSocket (highest priority)
				select {
				case writeChan <- wsMessage{messageType: websocket.BinaryMessage, data: dataCopy}:
				case <-done:
					return
				}

				// Queue to Vision worker (non-blocking, drop if full)
				select {
				case visionChan <- dataCopy:
				default:
					// Vision queue full, skip this chunk (non-critical)
				}

				// Queue to AM worker (non-blocking, drop if full)
				select {
				case amChan <- string(dataCopy):
				default:
					// AM queue full, skip this chunk (non-critical)
				}
			}
		}
	}()

	// ═══ GOROUTINE 6: WebSocket Reader ═══
	// Reads from WebSocket and writes to PTY
	lastFlushCheck := time.Now()

	go func() {
		defer closeDone()
		for {
			msgType, data, err := conn.ReadMessage()
			if err != nil {
				log.Printf("[Terminal] WebSocket read error: %v", err)
				return
			}

			// Check if it's a control message (JSON)
			if msgType == websocket.TextMessage {
				var msg ResizeMessage
				if err := json.Unmarshal(data, &msg); err == nil && msg.Type == "resize" {
					if err := session.Resize(msg.Cols, msg.Rows); err != nil {
						log.Printf("[Terminal] Resize error: %v", err)
					} else {
						log.Printf("[Terminal] Resized to %dx%d", msg.Cols, msg.Rows)
					}
					continue
				}

				// Check for Vision control messages
				var visionMsg VisionControlMessage
				if err := json.Unmarshal(data, &visionMsg); err == nil {
					switch visionMsg.Type {
					case "VISION_ENABLE":
						visionParser.SetEnabled(true)
						log.Printf("[Vision] Enabled for session %s", sessionID)
					case "VISION_DISABLE":
						visionParser.SetEnabled(false)
						visionParser.Clear()
						log.Printf("[Vision] Disabled for session %s", sessionID)
					case "INJECT_COMMAND":
						if visionMsg.Command != "" {
							log.Printf("[Vision] Injecting command: %s", visionMsg.Command)
							if _, err := session.Write([]byte(visionMsg.Command + "\r")); err != nil {
								log.Printf("[Vision] Command injection error: %v", err)
							}
						}
					}
					continue
				}

				// Check for AM control messages (auto-respond state sync)
				var amMsg AMControlMessage
				if err := json.Unmarshal(data, &amMsg); err == nil && amMsg.Type == "AM_AUTO_RESPOND" {
					llmLoggerMu.RLock()
					logger := llmLogger
					llmLoggerMu.RUnlock()
					if logger != nil {
						logger.SetAutoRespond(amMsg.AutoRespond)
						log.Printf("[AM] Auto-respond set to %v for session %s", amMsg.AutoRespond, sessionID)
					}
					continue
				}
			}

			// Write to PTY (this is the critical path for responsiveness)
			if _, err := session.Write(data); err != nil {
				log.Printf("[Terminal] PTY write error: %v", err)
				select {
				case closeChan <- closeReason{CloseCodePTYError, "Terminal write error"}:
				default:
				}
				return
			}

			// Accumulate input for LLM detection
			dataStr := string(data)
			inputBuffer.WriteString(dataStr)

			// AM: Capture user input when inside active LLM session
			llmLoggerMu.RLock()
			logger := llmLogger
			llmLoggerMu.RUnlock()

			if logger != nil {
				activeConv := logger.GetActiveConversationID()
				if activeConv != "" {
					go logger.AddUserInput(dataStr)
				}
			}

			// Check for newline/enter (command submission)
			if strings.Contains(dataStr, "\r") || strings.Contains(dataStr, "\n") {
				commandLine := strings.TrimSpace(inputBuffer.String())
				inputBuffer.Reset()

				if commandLine != "" && logger != nil {
					activeConv := logger.GetActiveConversationID()
					if activeConv == "" {
						detected := detector.DetectCommand(commandLine)

						if detected.Detected {
							isTUITool := detected.Provider == "github-copilot" || detected.Provider == "claude"

							if isTUITool {
								logger.StartConversationFromProcess(
									string(detected.Provider),
									string(detected.Type),
									0,
								)
							} else {
								logger.StartConversation(detected)
							}
						}
					}
				}
			}

			// Periodic flush check for LLM output
			if logger != nil && time.Since(lastFlushCheck) > flushTimeout {
				if logger.ShouldFlushOutput(flushTimeout) {
					go logger.FlushOutput()
				}
				lastFlushCheck = time.Now()
			}
		}
	}()

	// Wait for shutdown or session termination
	var finalReason closeReason
	select {
	case <-done:
		log.Printf("[Terminal] Session %s: I/O loop ended", sessionID)
		select {
		case finalReason = <-closeChan:
		default:
			finalReason = closeReason{websocket.CloseNormalClosure, "Connection closed"}
		}
	case <-session.Done():
		log.Printf("[Terminal] Session %s: Process exited", sessionID)
		finalReason = closeReason{CloseCodePTYExited, "Shell process exited"}
	case <-time.After(24 * time.Hour):
		log.Printf("[Terminal] Session %s: Timeout (24h)", sessionID)
		finalReason = closeReason{CloseCodeTimeout, "Session timed out after 24 hours"}
	}

	// Close channels to stop workers
	close(writeChan)
	close(visionChan)
	close(amChan)

	// CRITICAL: Clean up LLM logger when session ends
	llmLoggerMu.RLock()
	logger := llmLogger
	llmLoggerMu.RUnlock()

	if logger != nil {
		if activeConv := logger.GetActiveConversationID(); activeConv != "" {
			log.Printf("[Terminal] Ending active conversation %s on session close", activeConv)
			logger.EndConversation()
		}
		am.RemoveLLMLogger(tabID)
		log.Printf("[Terminal] LLM logger cleaned up for tab %s", tabID)
	}

	// Send close message with reason
	closeMessage := websocket.FormatCloseMessage(finalReason.code, finalReason.reason)
	_ = conn.WriteControl(websocket.CloseMessage, closeMessage, time.Now().Add(time.Second))
}
