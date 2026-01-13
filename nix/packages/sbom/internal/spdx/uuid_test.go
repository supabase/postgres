package spdx

import (
	"regexp"
	"testing"
)

func TestGenerateUUID(t *testing.T) {
	uuid, err := GenerateUUID()
	if err != nil {
		t.Fatalf("GenerateUUID() returned error: %v", err)
	}

	if uuid == "" {
		t.Error("GenerateUUID() returned empty string")
	}
}

func TestGenerateUUIDFormat(t *testing.T) {
	uuid, err := GenerateUUID()
	if err != nil {
		t.Fatalf("GenerateUUID() returned error: %v", err)
	}

	// UUID format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
	// 8-4-4-4-12 hex characters
	pattern := regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)
	if !pattern.MatchString(uuid) {
		t.Errorf("GenerateUUID() = %q, does not match UUID format", uuid)
	}
}

func TestGenerateUUIDVersion4Bits(t *testing.T) {
	uuid, err := GenerateUUID()
	if err != nil {
		t.Fatalf("GenerateUUID() returned error: %v", err)
	}

	// Version 4 UUIDs have the format xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
	// where y is one of 8, 9, a, or b
	// The 13th character (index 14 with dashes) should be '4'
	if len(uuid) < 15 {
		t.Fatalf("UUID too short: %q", uuid)
	}

	// Check version nibble (character at position 14, which is the first char of the 3rd group)
	versionChar := uuid[14]
	if versionChar != '4' {
		t.Errorf("GenerateUUID() version nibble = %c, want '4'", versionChar)
	}
}

func TestGenerateUUIDVariantBits(t *testing.T) {
	uuid, err := GenerateUUID()
	if err != nil {
		t.Fatalf("GenerateUUID() returned error: %v", err)
	}

	// The variant bits are in the 17th character (index 19 with dashes)
	// Should be 8, 9, a, or b for RFC 4122 variant
	if len(uuid) < 20 {
		t.Fatalf("UUID too short: %q", uuid)
	}

	variantChar := uuid[19]
	validVariants := map[byte]bool{'8': true, '9': true, 'a': true, 'b': true}
	if !validVariants[variantChar] {
		t.Errorf("GenerateUUID() variant nibble = %c, want one of 8, 9, a, b", variantChar)
	}
}

func TestGenerateUUIDUniqueness(t *testing.T) {
	const numUUIDs = 1000
	uuids := make(map[string]bool)

	for i := 0; i < numUUIDs; i++ {
		uuid, err := GenerateUUID()
		if err != nil {
			t.Fatalf("GenerateUUID() returned error on iteration %d: %v", i, err)
		}

		if uuids[uuid] {
			t.Errorf("GenerateUUID() produced duplicate UUID: %s", uuid)
		}
		uuids[uuid] = true
	}

	if len(uuids) != numUUIDs {
		t.Errorf("Expected %d unique UUIDs, got %d", numUUIDs, len(uuids))
	}
}

func TestGenerateUUIDLength(t *testing.T) {
	uuid, err := GenerateUUID()
	if err != nil {
		t.Fatalf("GenerateUUID() returned error: %v", err)
	}

	// UUID should be 36 characters: 32 hex + 4 dashes
	expectedLen := 36
	if len(uuid) != expectedLen {
		t.Errorf("GenerateUUID() length = %d, want %d", len(uuid), expectedLen)
	}
}

func TestGenerateUUIDNotZero(t *testing.T) {
	uuid, err := GenerateUUID()
	if err != nil {
		t.Fatalf("GenerateUUID() returned error: %v", err)
	}

	zeroUUID := "00000000-0000-0000-0000-000000000000"
	if uuid == zeroUUID {
		t.Error("GenerateUUID() returned zero UUID, expected random UUID")
	}
}

func BenchmarkGenerateUUID(b *testing.B) {
	for i := 0; i < b.N; i++ {
		_, err := GenerateUUID()
		if err != nil {
			b.Fatalf("GenerateUUID() returned error: %v", err)
		}
	}
}
