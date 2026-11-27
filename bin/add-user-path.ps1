# Append a directory to the current user PATH (idempotent).
# Preserves the original registry value kind and unexpanded %vars%.
# Usage: powershell.exe -NoProfile -ExecutionPolicy Bypass -File bin\add-user-path.ps1 -Dir "D:\some\bin"
# NOTE: keep this file ASCII-only. Windows PowerShell 5.1 parses BOM-less
# UTF-8 scripts as ANSI, which breaks any non-ASCII character.
param(
    [Parameter(Mandatory = $true)][string]$Dir
)

$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
if ($null -eq $key) { Write-Error 'Cannot open HKCU:\Environment'; exit 1 }

$kind = if ($key.GetValueNames() -contains 'Path') { $key.GetValueKind('Path') } else { [Microsoft.Win32.RegistryValueKind]::String }
$cur = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
$parts = @($cur -split ';' | Where-Object { $_ -ne '' })

if ($parts -contains $Dir) {
    Write-Host "[ok] PATH already contains $Dir"
    $key.Close()
    exit 0
}

$new = ($parts + $Dir) -join ';'
$key.SetValue('Path', $new, $kind)
$key.Close()

# Broadcast WM_SETTINGCHANGE so new terminals pick up the change immediately.
$sig = @'
[DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
Add-Type -MemberDefinition $sig -Name NativeMethods -Namespace Win32
$r = [UIntPtr]::Zero
[Win32.NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$r) | Out-Null
Write-Host "[ok] user PATH += $Dir (effective in new terminals)"
