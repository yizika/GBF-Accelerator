//go:build windows

package cert

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"time"
)

// Restrict the directory before writing keys, and repair existing key ACLs.
// The directory ACL also prevents other ordinary users from replacing the key.
func protectPrivateKeyDirectory(dir string) error {
	abs, err := filepath.Abs(dir)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	const script = `$ErrorActionPreference='Stop'
$sid=[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$dir=$env:GBF_PRIVATE_CERT_DIR
$item=Get-Item -LiteralPath $dir -Force
if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Certificate directory must not be a reparse point' }
$acl=New-Object System.Security.AccessControl.DirectorySecurity
$acl.SetSecurityDescriptorSddlForm(('D:P(A;OICI;FA;;;'+$sid+')(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)'), [Security.AccessControl.AccessControlSections]::Access)
[IO.Directory]::SetAccessControl($dir, $acl)
$key=Join-Path $dir 'ca.key'
if (Test-Path -LiteralPath $key) {
  $item=Get-Item -LiteralPath $key -Force
  if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Private key must not be a reparse point' }
  $acl=New-Object System.Security.AccessControl.FileSecurity
  $acl.SetSecurityDescriptorSddlForm(('D:P(A;;FA;;;'+$sid+')(A;;FA;;;SY)(A;;FA;;;BA)'), [Security.AccessControl.AccessControlSections]::Access)
  [IO.File]::SetAccessControl($key, $acl)
}`
	cmd := exec.CommandContext(ctx, "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", script)
	cmd.Env = append(os.Environ(), "GBF_PRIVATE_CERT_DIR="+abs)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("protect CA private key permissions: %w: %s", err, output)
	}
	return nil
}
