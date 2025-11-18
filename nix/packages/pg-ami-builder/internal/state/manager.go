package state

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// PhaseState represents the state for a specific phase
type PhaseState struct {
	InstanceID  string `json:"instance_id,omitempty"`
	ExecutionID string `json:"execution_id,omitempty"`
	AMIID       string `json:"ami_id,omitempty"`
	Timestamp   string `json:"timestamp,omitempty"`
}

// State represents the build state
type State struct {
	Phase1          *PhaseState `json:"phase1,omitempty"`
	Phase2          *PhaseState `json:"phase2,omitempty"`
	Region          string      `json:"region"`
	PostgresVersion string      `json:"postgres_version"`
	GitSHA          string      `json:"git_sha"`

	// Legacy fields for backward compatibility
	InstanceID  string `json:"instance_id,omitempty"`
	Phase       string `json:"phase,omitempty"`
	ExecutionID string `json:"execution_id,omitempty"`
	AMIID       string `json:"ami_id,omitempty"`
	Timestamp   string `json:"timestamp,omitempty"`
}

// GetDefaultStateFile returns the default state file path
func GetDefaultStateFile() (string, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("failed to get home directory: %w", err)
	}

	stateDir := filepath.Join(homeDir, ".pg-ami-build")
	if err := os.MkdirAll(stateDir, 0o755); err != nil {
		return "", fmt.Errorf("failed to create state directory: %w", err)
	}

	return filepath.Join(stateDir, "state.json"), nil
}

// SaveState saves the state to a file
func SaveState(filePath string, state *State) error {
	// Ensure directory exists
	dir := filepath.Dir(filePath)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fmt.Errorf("failed to create state directory: %w", err)
	}

	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal state: %w", err)
	}

	if err := os.WriteFile(filePath, data, 0o644); err != nil {
		return fmt.Errorf("failed to write state file: %w", err)
	}

	return nil
}

// LoadState loads the state from a file
func LoadState(filePath string) (*State, error) {
	data, err := os.ReadFile(filePath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("state file does not exist: %s", filePath)
		}
		return nil, fmt.Errorf("failed to read state file: %w", err)
	}

	var state State
	if err := json.Unmarshal(data, &state); err != nil {
		return nil, fmt.Errorf("failed to unmarshal state: %w", err)
	}

	return &state, nil
}

// ClearState removes the state file
func ClearState(filePath string) error {
	if err := os.Remove(filePath); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("failed to remove state file: %w", err)
	}
	return nil
}

// GetPhaseState returns the state for a specific phase
func (s *State) GetPhaseState(phase string) *PhaseState {
	// Try new structure first
	if phase == "phase1" && s.Phase1 != nil {
		return s.Phase1
	}
	if phase == "phase2" && s.Phase2 != nil {
		return s.Phase2
	}

	// Fall back to legacy fields
	if s.Phase == phase {
		return &PhaseState{
			InstanceID:  s.InstanceID,
			ExecutionID: s.ExecutionID,
			AMIID:       s.AMIID,
			Timestamp:   s.Timestamp,
		}
	}

	return nil
}

// SetPhaseState sets the state for a specific phase
func (s *State) SetPhaseState(phase string, ps *PhaseState) {
	if phase == "phase1" {
		s.Phase1 = ps
	} else if phase == "phase2" {
		s.Phase2 = ps
	}
}
