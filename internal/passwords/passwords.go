// Package passwords handles bcrypt credentials and the transition from legacy hashes.
package passwords

import (
	"crypto/md5"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"strings"

	"golang.org/x/crypto/bcrypt"
)

const (
	Cost             = 12
	MaxPasswordBytes = 72
	sha256Prefix     = "$csac$sha256$"
	md5Prefix        = "$csac$md5$"
)

func Hash(password string) (string, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), Cost)
	return string(hash), err
}

// Verify accepts legacy hashes only as stored credentials, never as passwords.
func Verify(stored, password, username string) bool {
	if strings.HasPrefix(stored, sha256Prefix) {
		hash := strings.TrimPrefix(stored, sha256Prefix)
		digest := legacyDigest("sha256", password, username)
		return bcrypt.CompareHashAndPassword([]byte(hash), []byte(digest)) == nil
	}
	if strings.HasPrefix(stored, md5Prefix) {
		hash := strings.TrimPrefix(stored, md5Prefix)
		digest := legacyDigest("md5", password, username)
		return bcrypt.CompareHashAndPassword([]byte(hash), []byte(digest)) == nil
	}
	if algorithm := legacyAlgorithm(stored); algorithm != "" {
		return subtle.ConstantTimeCompare([]byte(strings.ToLower(stored)), []byte(legacyDigest(algorithm, password, username))) == 1
	}
	if len(password) > MaxPasswordBytes {
		return false
	}
	return bcrypt.CompareHashAndPassword([]byte(stored), []byte(password)) == nil
}

// WrapLegacy protects existing digests without needing the plaintext password.
// A successful password login replaces this transitional format with direct bcrypt.
func WrapLegacy(stored string) (string, error) {
	algorithm := legacyAlgorithm(stored)
	if algorithm == "" {
		return stored, nil
	}
	hash, err := Hash(strings.ToLower(stored))
	if err != nil {
		return "", err
	}
	return "$csac$" + algorithm + "$" + hash, nil
}

func legacyAlgorithm(stored string) string {
	var algorithm string
	switch len(stored) {
	case 32:
		algorithm = "md5"
	case 64:
		algorithm = "sha256"
	default:
		return ""
	}
	if _, err := hex.DecodeString(stored); err != nil {
		return ""
	}
	return algorithm
}

func legacyDigest(algorithm, password, username string) string {
	if algorithm == "md5" {
		sum := md5.Sum([]byte(password))
		return hex.EncodeToString(sum[:])
	}
	sum := sha256.Sum256([]byte(password + username))
	return hex.EncodeToString(sum[:])
}
