param(
    [Parameter(Mandatory = $true)]
    [string]$GodotPath,
    [string[]]$TestName = @()
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$enginePath = (Resolve-Path -LiteralPath $GodotPath).Path
$logDirectory = Join-Path $projectRoot '.godot/validation'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$savedAppData = $env:APPDATA
$savedLocalAppData = $env:LOCALAPPDATA
$failedTests = @()
$passedTests = 0
$skippedTests = 0
$renderedChecksSkipped = 0

try {
    $env:APPDATA = Join-Path $logDirectory 'appdata'
    $env:LOCALAPPDATA = Join-Path $logDirectory 'localappdata'
    $testScenes = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tests') -File -Recurse -Filter '*_test.tscn' |
        Sort-Object Name
    if ($testScenes.Count -eq 0) { throw 'No test scenes found.' }
    $duplicateNames = $testScenes | Group-Object BaseName | Where-Object Count -gt 1
    if ($duplicateNames) {
        throw ('Duplicate test names: ' + ($duplicateNames.Name -join ', '))
    }
    if ($TestName.Count -gt 0) {
        $unknown = @($TestName | Where-Object { $_ -notin $testScenes.BaseName })
        if ($unknown.Count -gt 0) { throw ('Unknown test names: ' + ($unknown -join ', ')) }
        $testScenes = @($testScenes | Where-Object { $_.BaseName -in $TestName })
    }


    foreach ($scene in $testScenes) {
        $scenePath = 'res://' + $scene.FullName.Substring($projectRoot.Length + 1).Replace('\', '/')
        $output = & $enginePath --headless --path $projectRoot $scenePath --max-fps 60 --quit-after 1800 --log-file (Join-Path $logDirectory ($scene.BaseName + '.log')) 2>&1 |
            ForEach-Object { $_.ToString() }
        $engineExitCode = $LASTEXITCODE
        $passed = $output -match '^(PASS:|[A-Za-z0-9_]+_test: PASS$)'
        $skipped = $output -match '^SKIP: rendered window required$'
        $renderedSkipped = $output -match '^SKIP RENDERED:'
        if ($engineExitCode -ne 0 -or ($output -match '^(SCRIPT ERROR|ERROR|WARNING):') -or
            ([bool]$passed -eq [bool]$skipped)) {
            $failedTests += $scene.BaseName
            Write-Host ('FAIL: ' + $scene.BaseName + ' (engine exit ' + $engineExitCode + ')')
            $output | ForEach-Object { Write-Host $_ }
        } elseif ($skipped) {
            $skippedTests++
            Write-Host ('SKIP: ' + $scene.BaseName + ' (rendered window required)')
        } else {
            $passedTests++
            if ($renderedSkipped) {
                $renderedChecksSkipped++
                Write-Host ('PASS: ' + $scene.BaseName + ' (rendered checks skipped)')
            } else {
                Write-Host ('PASS: ' + $scene.BaseName)
            }
        }
    }
} finally {
    $env:APPDATA = $savedAppData
    $env:LOCALAPPDATA = $savedLocalAppData
}

Write-Host (
    'Headless results: {0} passed ({1} with rendered checks skipped), {2} skipped, {3} failed.' -f
    $passedTests, $renderedChecksSkipped, $skippedTests, $failedTests.Count
)
if ($failedTests.Count -gt 0) {
    throw ('Failed checks: ' + ($failedTests -join ', '))
}
