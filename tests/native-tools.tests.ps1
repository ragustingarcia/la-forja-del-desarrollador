param([string]$ChildCase,[string]$FixtureRoot)
$ErrorActionPreference='Stop'
if ($ChildCase) {
    $product=$env:FORJA_NATIVE_PRODUCT
    $raw=[IO.File]::ReadAllText($product)
    $errors=$null; $tokens=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($raw,[ref]$tokens,[ref]$errors)
    foreach ($f in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in @('Get-ForjaToolPath','Invoke-ForjaTool','Remove-ForjaClaudeNpm','Write-OK','Write-Warn')},$true)) {
        . ([scriptblock]::Create($f.Extent.Text))
    }
    $env:PATH=$FixtureRoot+';'+(Join-Path $env:SystemRoot 'System32')
    [IO.File]::WriteAllText((Join-Path $FixtureRoot 'npm.ps1'), "throw 'UNEXPECTED_PS1_EXECUTION'")
    $batch="@echo off`r`necho FIXTURE_OUTPUT`r`nexit /b 0`r`n"
    if ($ChildCase -eq 'stderr-ok') { $batch="@echo off`r`necho FIXTURE_NOTICE 1>&2`r`necho FIXTURE_OUTPUT`r`nexit /b 0`r`n" }
    if ($ChildCase -eq 'failure') { $batch="@echo off`r`necho FIXTURE_INSTALL_FAILURE 1>&2`r`nexit /b 1603`r`n" }
    [IO.File]::WriteAllText((Join-Path $FixtureRoot 'npm.cmd'), $batch)
    if ($ChildCase -eq 'missing') { [IO.File]::Delete((Join-Path $FixtureRoot 'npm.cmd')) }
    if ((Get-ExecutionPolicy) -ne 'Restricted') { throw 'La fixture debe correr bajo Restricted' }
    if ($ChildCase -eq 'blocked-direct') {
        $blocked=$false
        try { npm --version | Out-Null } catch [Security.SecurityException] { $blocked=$true } catch [Management.Automation.PSSecurityException] { $blocked=$true }
        if (-not $blocked) { throw 'La llamada bare npm no reprodujo el bloqueo ps1' }
        Write-Host 'PASS native blocked-direct: npm.ps1 bloqueado bajo Restricted'
        exit 0
    }
    $resolved=Get-ForjaToolPath 'npm'
    if ($ChildCase -eq 'missing') {
        if ($resolved) { throw 'Se eligio un shim ps1 o una ruta ajena' }
        $result=@(Invoke-ForjaTool npm --version)
        if ($LASTEXITCODE -ne -1) { throw 'Comando ausente sin codigo de error' }
    } elseif ($ChildCase -eq 'failure') {
        $result=@(Remove-ForjaClaudeNpm)
        if ($result.Count -ne 1 -or $result[0] -ne 'error') { throw 'Limpieza fallida no retorna estado escalar error' }
        Write-Host 'CONTINUA_DESPUES_DE_LIMPIEZA'
    } else {
        if ($resolved -ne (Join-Path $FixtureRoot 'npm.cmd')) { throw 'No resolvio el .cmd de la fixture' }
        $result=@(Invoke-ForjaTool npm --version)
        if ($LASTEXITCODE -ne 0 -or ($result -join ' ') -notmatch 'FIXTURE_OUTPUT') { throw 'Fallo la invocacion cmd bajo Restricted' }
        if ($ChildCase -eq 'stderr-ok' -and ($result -join ' ') -notmatch 'FIXTURE_NOTICE') { throw 'Se perdio stderr' }
    }
    Write-Host "PASS native $ChildCase / Restricted / solo fixture cmd"
    exit 0
}

$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('forja-native-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($sandbox) | Out-Null
$passed=0
try {
    foreach ($case in @('blocked-direct','success','stderr-ok','failure','missing')) {
        $fixture=Join-Path $sandbox $case
        [IO.Directory]::CreateDirectory($fixture) | Out-Null
        $psi=New-Object Diagnostics.ProcessStartInfo
        $psi.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        # No cargar el archivo como script: el mismo arranque en memoria que el BAT.
        $psi.Arguments='-NoProfile -ExecutionPolicy Restricted -Command "& ([scriptblock]::Create([IO.File]::ReadAllText($env:FORJA_NATIVE_SCRIPT))) -ChildCase '+$case+' -FixtureRoot $env:FORJA_NATIVE_FIXTURE"'
        $psi.EnvironmentVariables['FORJA_NATIVE_SCRIPT']=$PSCommandPath
        $psi.EnvironmentVariables.Remove('PSModulePath')
        $psi.EnvironmentVariables['FORJA_NATIVE_FIXTURE']=$fixture
        $psi.EnvironmentVariables['FORJA_NATIVE_PRODUCT']=Join-Path (Split-Path $PSScriptRoot -Parent) 'forja-del-desarrollador.bat'
        $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
        $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
        $process=[Diagnostics.Process]::Start($psi)
        $outTask=$process.StandardOutput.ReadToEndAsync(); $errTask=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(15000)) { $process.Kill(); throw "Timeout native $case" }
        $stdout=$outTask.Result; $stderr=$errTask.Result
        if ($process.ExitCode -ne 0 -or $stderr) { throw "Native $case : $stdout`n$stderr" }
        if ($case -eq 'failure' -and $stdout -notmatch 'CONTINUA_DESPUES_DE_LIMPIEZA') { throw 'No continuo tras fallo nativo' }
        Write-Host $stdout.Trim()
        $passed++
    }
    Write-Host "RESULTADO NATIVO: $passed PASS / 0 FAIL"
} finally {
    $full=[IO.Path]::GetFullPath($sandbox)
    $parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if ([IO.Path]::GetDirectoryName($full) -ne $parent -or [IO.Path]::GetFileName($full) -notmatch '^forja-native-[0-9a-f]{32}$') { throw 'Raiz de fixture inesperada' }
    foreach ($folder in @(Get-ChildItem -LiteralPath $full -Directory)) {
        foreach ($file in @(Get-ChildItem -LiteralPath $folder.FullName -File)) { Remove-Item -LiteralPath $file.FullName }
        [IO.Directory]::Delete($folder.FullName)
    }
    [IO.Directory]::Delete($full)
}
