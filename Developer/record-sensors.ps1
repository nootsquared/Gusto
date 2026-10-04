param([string]$Port = 'COM8', [string]$OutputDirectory = (Join-Path $PSScriptRoot 'recordings'))
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$serial = [System.IO.Ports.SerialPort]::new($Port,115200)
$serial.NewLine = "`n"
$serial.ReadTimeout = 5000
$serial.WriteTimeout = 5000
$serial.DtrEnable = $true
$serial.RtsEnable = $true
$lines = [System.Collections.Generic.List[string]]::new()
$csv = [System.Collections.Generic.List[string]]::new()
try {
  $serial.Open()
  Start-Sleep -Seconds 3
  $serial.DiscardInBuffer()
  $serial.WriteLine('START')
  $timer = [System.Diagnostics.Stopwatch]::StartNew()
  $done = $false
  while ($timer.Elapsed.TotalSeconds -lt 20) {
    $line = $serial.ReadLine().Trim()
    $lines.Add($line)
    if ($line -match '^\d+,') {
      $fields = $line.Split(',')
      $culture = [System.Globalization.CultureInfo]::InvariantCulture
      $fahrenheit = [double]::Parse($fields[1], $culture)
      $celsius = [double]::Parse($fields[2], $culture)
      $degree = [char]0x00B0
      Write-Host ("{0} ms | Temperature: {1:F2} {2}F ({3:F2} {2}C) | Humidity: {4}% RH | Light: {5} raw counts" -f $fields[0], $fahrenheit, $degree, $celsius, $fields[3], $fields[4])
    } else { Write-Host $line }
    if ($line.StartsWith('elapsed_ms,') -or $line -match '^\d+,') { $csv.Add($line) }
    if ($line -eq 'DONE') { $done = $true; break }
  }
  if (!$done) { throw 'Recording did not finish.' }
  if ($csv.Count -ne 22) { throw "Expected 21 samples plus header; received $($csv.Count) lines." }
} finally {
  if ($serial.IsOpen) { $serial.Close() }
  $serial.Dispose()
  $lines | Set-Content (Join-Path $OutputDirectory 'sensor-10s-log.txt')
  $csv | Set-Content (Join-Path $OutputDirectory 'sensor-10s.csv')
}
