Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$out = 'D:\weasel-build\tst\typed.txt'
[IO.File]::WriteAllText($out, '', (New-Object Text.UTF8Encoding($false)))
$form = New-Object Windows.Forms.Form
$form.Text = 'IME TEST PAD'
$form.ClientSize = New-Object Drawing.Size(900, 380)
$form.StartPosition = 'Manual'
$form.Location = New-Object Drawing.Point(60, 40)
$tb = New-Object Windows.Forms.TextBox
$tb.Multiline = $true
$tb.Dock = 'Fill'
$tb.Font = New-Object Drawing.Font('Consolas', 16)
$tb.ScrollBars = 'Vertical'
$tb.Add_TextChanged({
  [IO.File]::WriteAllText($out, $tb.Text, (New-Object Text.UTF8Encoding($false)))
})
$form.Controls.Add($tb)
$form.Add_Shown({ $tb.Focus() })
[void]$form.Show()
[Windows.Forms.Application]::Run($form)
