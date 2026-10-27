$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$raw=[IO.File]::ReadAllText((Join-Path $root 'forja-del-desarrollador.bat'))
$errors=$null;$tokens=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($raw,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach($f in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)){. ([scriptblock]::Create($f.Extent.Text))}
function Get-Command { param($Name,$CommandType,$ErrorAction)
    if ($Name -eq 'python.exe' -and $script:case -ne 'no-python') { return [pscustomobject]@{Source='C:\fixture\base-python.exe'} }
    return $null
}
function Read-Host { param($Prompt) if ($script:case -eq 'decline') { return 'N' }; return 'S' }
function Invoke-ForjaPython { param([string]$Executable)
    $script:calls+=,[pscustomobject]@{Executable=$Executable;Arguments=@($args)}
    $global:LASTEXITCODE=0
    if ($args -contains '-c') {
        if ($script:case -eq 'import-failure') { $global:LASTEXITCODE=1; 'fixture DLL load failed' }
        return
    }
    if ($args -contains 'venv') {
        if ($Executable -ne 'C:\fixture\base-python.exe') { throw 'Base inesperada' }
        New-FixtureVenv
        return
    }
    if ($args -contains 'check') {
        if ($Executable -eq 'C:\fixture\base-python.exe' -and $script:case -eq 'shared-conflict') { $global:LASTEXITCODE=1; 'fixture requires pillow<11'; return }
        if ($Executable -ne 'C:\fixture\base-python.exe' -and $script:case -eq 'dependency-conflict') { $global:LASTEXITCODE=1; 'fixture dependency conflict'; return }
        'No broken requirements found.'; return
    }
    if ($args -contains 'list') {
        $version='1.0.0'
        if ($script:case -eq 'new-environment' -and $script:installed) { $version='2.0.0' }
        '[{"name":"fastapi","version":"'+$version+'"}]'; return
    }
    if ($args -contains 'install') {
        if ($Executable -eq 'C:\fixture\base-python.exe') { throw 'PROHIBIDO pip install global' }
        $script:installed=$true
        if ($script:case -eq 'install-failure') { $global:LASTEXITCODE=1; 'fixture install failure' }
        return
    }
    if ($args -contains 'show') { 'Name: fixture'; return }
    throw 'Invocacion Python inesperada'
}
function New-FixtureVenv {
    $relative='Forja\Python\venv';if($script:case -eq 'web-vision'){$relative='Forja\Python\web-vision'}
    $path=Join-Path $env:LOCALAPPDATA $relative
    [IO.Directory]::CreateDirectory((Join-Path $path 'Scripts')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $path 'Scripts\python.exe'),'inert fixture')
    $isolated='false';if ($script:case -eq 'system-site-packages') { $isolated='true' }
    [IO.File]::WriteAllText((Join-Path $path 'pyvenv.cfg'),"include-system-site-packages = $isolated`r`n")
}
$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('forja-python-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($sandbox) | Out-Null
$previous=$env:LOCALAPPDATA
$passed=0
try {
    foreach($case in @('healthy','shared-conflict','install-failure','dependency-conflict','import-failure','system-site-packages','new-environment','decline','incomplete','no-python','web-vision')) {
        $env:LOCALAPPDATA=Join-Path $sandbox $case
        $script:calls=@();$script:installed=$false
        if ($case -in @('healthy','shared-conflict','install-failure','dependency-conflict','import-failure','system-site-packages','web-vision')) { New-FixtureVenv }
        if ($case -eq 'incomplete') { [IO.Directory]::CreateDirectory((Join-Path $env:LOCALAPPDATA 'Forja\Python\venv')) | Out-Null }
        if ($case -eq 'shared-conflict') { $result=@(Invoke-ForjaPythonLibraries -Update -CheckShared) }
        elseif ($case -eq 'web-vision') { $result=@(Invoke-ForjaPythonLibraries -Update -Profile web-vision) }
        else { $result=@(Invoke-ForjaPythonLibraries -Update) }
        if ($result.Count -ne 1) { throw 'Python retorna salida adicional al estado' }
        $expected='aldia'
        if ($case -in @('install-failure','dependency-conflict','import-failure','system-site-packages','incomplete')) { $expected='error' }
        if ($case -in @('decline','no-python')) { $expected='saltado' }
        if ($case -eq 'new-environment') { $expected='ok' }
        if ($result[0].State -ne $expected) { throw "$case : $($result[0].State) esperado $expected" }
        if ($case -eq 'shared-conflict' -and -not $result[0].SharedConflict) { throw 'Se oculto el conflicto compartido' }
        if ($case -eq 'healthy' -and @($script:calls | Where-Object { $_.Executable -eq 'C:\fixture\base-python.exe' -and $_.Arguments -contains 'check' }).Count) { throw 'Se inspecciono Python compartido sin pedir diagnostico' }
        if (@($script:calls | Where-Object { $_.Executable -eq 'C:\fixture\base-python.exe' -and $_.Arguments -contains 'install' }).Count) { throw 'Instalacion global detectada' }
        if ($case -in @('system-site-packages','incomplete','decline','no-python') -and @($script:calls | Where-Object {$_.Arguments -contains 'install'}).Count) { throw 'Se instalo en entorno no validado' }
        if($case -eq 'web-vision'){
            $install=@($script:calls | Where-Object {$_.Arguments -contains 'install'})[0]
            if($install.Executable -notlike '*\web-vision\Scripts\python.exe' -or $install.Arguments -notcontains 'Flask' -or $install.Arguments -notcontains 'opencv-python' -or $install.Arguments -contains 'fastapi'){throw 'Perfil Flask/OpenCV fuera de su entorno separado'}
            if(-not @($script:calls | Where-Object {$_.Arguments -contains 'import flask, cv2, numpy'}).Count){throw 'Falta verificar imports del perfil vision'}
        }
        $passed++;Write-Host "PASS Python $case / $expected / sin pip install global"
    }
    Write-Host "RESULTADO PYTHON: $passed PASS / 0 FAIL"
} finally {
    $env:LOCALAPPDATA=$previous
    $full=[IO.Path]::GetFullPath($sandbox)
    $parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if ([IO.Path]::GetDirectoryName($full) -ne $parent -or [IO.Path]::GetFileName($full) -notmatch '^forja-python-[0-9a-f]{32}$') { throw 'Raiz de pruebas invalida' }
    $null=@(Get-ForjaTree $full)
    Remove-Item -LiteralPath $full -Recurse -Force
}
