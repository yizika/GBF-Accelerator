//go:build !windows

package cert

// Existing Unix private-key creation already uses mode 0600.
func protectPrivateKeyDirectory(string) error { return nil }
