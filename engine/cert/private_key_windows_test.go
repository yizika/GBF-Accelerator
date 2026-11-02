//go:build windows

package cert

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestPrivateKeyPermissionsRepair(t *testing.T) {
	dir := t.TempDir()
	m, err := NewManager(dir)
	if err != nil {
		t.Fatal(err)
	}
	before := m.GetFingerprintSHA256()
	key := filepath.Join(dir, "ca.key")
	// Simulate a key copied from an old installation with a broad read grant.
	if out, err := exec.Command("icacls.exe", key, "/grant", "*S-1-1-0:R").CombinedOutput(); err != nil {
		t.Fatalf("seed ACL: %v: %s", err, out)
	}
	m, err = NewManager(dir)
	if err != nil {
		t.Fatal(err)
	}
	if m.GetFingerprintSHA256() != before {
		t.Fatal("permission repair replaced existing CA")
	}
	cmd := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-Command", `$ErrorActionPreference='Stop'; $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value; $acl=[IO.File]::GetAccessControl($env:GBF_TEST_KEY); if (-not $acl.AreAccessRulesProtected) { throw 'ACL is inherited' }; foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) { if ($rule.IdentityReference.Value -notin @($sid,'S-1-5-18','S-1-5-32-544')) { throw 'Unexpected principal' } }`)
	cmd.Env = append(os.Environ(), "GBF_TEST_KEY="+key)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("verify ACL: %v: %s", err, out)
	}
}
