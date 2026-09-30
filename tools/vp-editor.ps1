param(
  [string]$State = 'D:\VibeCoding\输入法\_tmp-session\vp-editor-state.txt'
)
# Standalone IME test target: a plain multiline TextBox window owned by this process.
# A timer mirrors TextBox.Text into a file so the driver can read the document without
# clipboard races (other sessions in this workspace use Notepad concurrently).
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (Test-Path $State) { Remove-Item $State -Force -ErrorAction SilentlyContinue }

$form = New-Object System.Windows.Forms.Form
$form.Text = 'VP-EDITOR'
$form.StartPosition = 'Manual'
$form.Bounds = New-Object System.Drawing.Rectangle 60, 40, 1040, 460
$form.ShowInTaskbar = $true

$tb = New-Object System.Windows.Forms.TextBox
$tb.Multiline = $true
$tb.Dock = 'Fill'
$tb.AcceptsReturn = $true
$tb.AcceptsTab = $true
$tb.WordWrap = $false
$tb.ScrollBars = 'Both'
$tb.Font = New-Object System.Drawing.Font('Consolas', 14)
$form.Controls.Add($tb)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 250
$timer.Add_Tick({
  try { [System.IO.File]::WriteAllText($State, $tb.Text, (New-Object System.Text.UTF8Encoding $false)) } catch {}
})
$timer.Start()

$raised = $false

$form.Add_Shown({ $tb.Focus() })

[System.Windows.Forms.Application]::Run($form)
