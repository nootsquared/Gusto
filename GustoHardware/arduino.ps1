[CmdletBinding()]
param(
  [ValidateSet('Setup','List','Compile','Upload','Monitor','Test')]
  [string]$Action = 'List',
  [string]$Port = 'COM8',
  [ValidateSet('SerialSmokeTest','SensorTenSecondTest','nano_climate_sender')]
  [string]$SketchName = 'SerialSmokeTest'
)
$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot '.tools\stable\arduino-cli.exe'
$config = Join-Path $PSScriptRoot 'arduino-cli.yaml'
$sketch = Join-Path $PSScriptRoot $SketchName
$build = Join-Path $PSScriptRoot 'build'
$fqbn = 'arduino:mbed_nano:nano33ble'
function Invoke-Arduino {
  & $cli --config-file $config @args
  if ($LASTEXITCODE -ne 0) { throw "Arduino CLI failed (exit $LASTEXITCODE)." }
}
if ($Action -eq 'Setup') {
  if (!(Test-Path $cli)) {
    New-Item -ItemType Directory -Force -Path (Split-Path $cli) | Out-Null
    $archive = Join-Path $PSScriptRoot '.tools\stable.zip'
    Invoke-WebRequest 'https://downloads.arduino.cc/arduino-cli/arduino-cli_1.3.1_Windows_64bit.zip' -OutFile $archive
    Expand-Archive $archive (Split-Path $cli) -Force
  }
  if (!(Test-Path $config)) {
    $runtime = Join-Path $env:LOCALAPPDATA 'MHacksArduino'
    @"
directories:
  data: $runtime\data
  downloads: $runtime\downloads
  user: $runtime\sketchbook
"@ | Set-Content $config
  }
  Invoke-Arduino version
  Invoke-Arduino core update-index
  Invoke-Arduino core install arduino:mbed_nano
  Invoke-Arduino lib install Arduino_HTS221 Arduino_HS300x Arduino_APDS9960 ArduinoBLE
  Invoke-Arduino core list
  Invoke-Arduino board list
  return
}
if (!(Test-Path $cli) -or !(Test-Path $config)) { throw 'Run .\arduino.ps1 Setup first.' }
switch ($Action) {
  'List' { Invoke-Arduino board list }
  'Compile' { Invoke-Arduino compile --fqbn $fqbn --build-path $build $sketch }
  'Upload' {
    Invoke-Arduino compile --fqbn $fqbn --build-path $build $sketch
    Invoke-Arduino upload --fqbn $fqbn --port $Port --input-dir $build $sketch
  }
  'Monitor' { Invoke-Arduino monitor --port $Port --config baudrate=115200 }
  'Test' {
    $serial = [System.IO.Ports.SerialPort]::new($Port, 115200)
    $serial.NewLine = "`n"
    $serial.ReadTimeout = 5000
    $serial.WriteTimeout = 5000
    $serial.DtrEnable = $true
    $serial.RtsEnable = $true
    try {
      $serial.Open()
      Start-Sleep -Seconds 2
      $serial.DiscardInBuffer()
      foreach ($command in @('PING','INFO','ECHO hello from MHacks','UPTIME')) {
        $serial.WriteLine($command)
        $reply = $serial.ReadLine().Trim()
        Write-Host "$command -> $reply"
        $valid = switch ($command) {
          'PING' { $reply -eq 'PONG' }
          'INFO' { $reply -eq 'BOARD=Nano 33 BLE; TEST=SerialSmokeTest; BAUD=115200' }
          'ECHO hello from MHacks' { $reply -eq 'ECHO: hello from MHacks' }
          'UPTIME' { $reply -match '^UPTIME_MS=\d+$' }
        }
        if (!$valid) { throw "Unexpected response to $command. Ensure Upload succeeded and close any other serial monitor. The board may still be running its previous sketch." }
      }
      Write-Host 'PASS: all four serial checks succeeded.'
    } finally {
      if ($serial.IsOpen) { $serial.Close() }
      $serial.Dispose()
    }
  }
}
