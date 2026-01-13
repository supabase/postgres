package spdx

import (
	"crypto/rand"
	"fmt"
)

// GenerateUUID generates a RFC 4122 compliant UUID v4 using crypto/rand.
func GenerateUUID() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("failed to generate UUID: %w", err)
	}

	// Set version 4 bits (0100xxxx)
	b[6] = (b[6] & 0x0f) | 0x40
	// Set variant bits (10xxxxxx)
	b[8] = (b[8] & 0x3f) | 0x80

	return fmt.Sprintf("%x-%x-%x-%x-%x",
		b[0:4], b[4:6], b[6:8], b[8:10], b[10:]), nil
}
