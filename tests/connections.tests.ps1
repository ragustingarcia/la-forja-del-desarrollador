$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$raw=[IO.File]::ReadAllText((Join-Path $root 'forja-del-desarrollador.bat'))
$errors=$null;$tokens=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($raw,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors | Out-String)}
foreach($f in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)){. ([scriptblock]::Create($f.Extent.Text))}
$passed=0
function Assert {param([bool]$Condition,[string]$Message) if(-not $Condition){throw "FALLO: $Message"};$script:passed++;Write-Host "PASS $Message"}
$realRunner=${function:Invoke-ForjaPackageProcess}
$realProbe=${function:Get-ForjaVercelSession}
function Get-ForjaVercelProbeCommand {
    if($script:commandMissing){return $null}
    return [pscustomobject]@{Executable='C:\fixture\node.exe';Arguments=@('C:\fixture with spaces\vc.js')}
}
function Invoke-ForjaPackageProcess {param($Executable,$ArgumentList,$Label,$TimeoutSeconds,[switch]$NonInteractive)
    $script:probeArguments=$ArgumentList;$script:probeTimeout=$TimeoutSeconds;$script:probeNonInteractive=[bool]$NonInteractive
    return $script:fixtureResult
}
function Invoke-ForjaTool {throw 'PROHIBIDO iniciar login real en estas pruebas'}
function Start-Process {throw 'PROHIBIDO abrir navegador o terminales en estas pruebas'}
$script:commandMissing=$false
$script:fixtureResult=[pscustomobject]@{ExitCode=0;TimedOut=$false;Output=@('Vercel CLI 65.4.0','fixture-user')}
$session=Get-ForjaVercelSession
Assert ($session.State -eq 'connected' -and $session.User -eq 'fixture-user') 'sesion se confirma con usuario unico y exit cero'
Assert ($script:probeArguments -contains 'whoami' -and $script:probeArguments -contains '--non-interactive' -and $script:probeArguments -notcontains 'login') 'consulta nunca solicita login implicito'
Assert ($script:probeTimeout -eq 30 -and $script:probeNonInteractive) 'consulta tiene limite y stdin no interactivo'
Assert ($script:probeArguments[0] -eq 'C:\fixture with spaces\vc.js') 'entrada npm se pasa como argumento separado sin shell'
$script:fixtureResult=[pscustomobject]@{ExitCode=1;TimedOut=$false;Output=@('Login required','https://fixture.invalid/private-device-code')}
$session=Get-ForjaVercelSession
Assert ($session.State -eq 'pending' -and -not $session.User -and $session.Reason -match 'codigo 1') 'login incompleto queda pendiente sin usuario falso'
Assert ($session.Reason -notmatch 'private-device-code|fixture.invalid') 'explicacion no copia codigos de dispositivo de la salida'
$script:fixtureResult=[pscustomobject]@{ExitCode=-2;TimedOut=$true;Output=@()}
Assert ((Get-ForjaVercelSession).State -eq 'timeout') 'timeout se distingue de falta de login'
$script:fixtureResult=[pscustomobject]@{ExitCode=0;TimedOut=$false;Output=@('first-user','second-user')}
Assert ((Get-ForjaVercelSession).State -eq 'pending') 'salida ambigua no se marca conectada'
$script:fixtureResult=[pscustomobject]@{ExitCode=0;TimedOut=$false;Output=@('Vercel CLI 65.4.0')}
Assert ((Get-ForjaVercelSession).State -eq 'pending') 'banner de version no equivale a sesion'
$script:commandMissing=$true
Assert ((Get-ForjaVercelSession).State -eq 'missing') 'CLI ausente informa instalacion requerida sin procesos'
$script:commandMissing=$false
foreach($state in @('pending','timeout','missing')){
    $script:fixtureState=$state
    function Get-ForjaVercelSession {param($TimeoutSeconds) return [pscustomobject]@{State=$script:fixtureState;Reason='FIXTURE_NO_SESSION';User=$null}}
    $script:connectionState=$null
    $output=@(Show-ForjaVercelConnection 6>&1 | ForEach-Object {if($_ -is [Management.Automation.InformationRecord]){$_.ToString()}else{$script:connectionState=$_}}) -join "`n"
    Assert ($script:connectionState -eq 'PENDIENTE') "$state permite continuar el asistente sin cerrar Forja"
    if($state -eq 'missing'){Assert ($output -match 'T22') 'CLI ausente muestra codigo de instalacion'}
    else {Assert ($output -match 'vercel.cmd login' -and $output -match 'terminal nueva') "$state ofrece recuperacion en terminal separada"}
}
Set-Item -Path Function:Invoke-ForjaPackageProcess -Value $realRunner
Set-Item -Path Function:Get-ForjaVercelSession -Value $realProbe
$script:frames=@()
function Write-ForjaProgress {param($Label,$Bytes,$Total,$Frame,[switch]$Completed,[switch]$Failed) $script:frames+=@([pscustomobject]@{Completed=[bool]$Completed;Failed=[bool]$Failed})}
$shell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$savedCi=$env:CI
# Source literal para evitar expandir las variables en la consola de la prueba.
$source='[Console]::WriteLine("CI_VALUE="+$env:CI); $inputPipe=[Console]::OpenStandardInput(); [Console]::WriteLine("INPUT_BYTE="+$inputPipe.ReadByte()); exit 0'
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($source))
$result=Invoke-ForjaPackageProcess $shell @('-NoProfile','-EncodedCommand',$encoded) 'Fixture stdin' -TimeoutSeconds 5 -NonInteractive
# Comprobar EOF en el pipe real: Console.In puede devolver cadena vacia en algunos hosts PS5.
Assert ($result.ExitCode -eq 0 -and ($result.Output -join ' ') -match 'CI_VALUE=true' -and ($result.Output -join ' ') -match 'INPUT_BYTE=-1') ('proceso inerte recibe CI y stdin cerrado sin prompts; exit='+$result.ExitCode+'; salida='+($result.Output -join ' | '))
Assert ($env:CI -ceq $savedCi) 'CI no se persiste ni se cambia en el proceso padre'
$peer=$null
try {
    $sleep=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('Start-Sleep -Seconds 30'))
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=$shell;$psi.Arguments='-NoProfile -EncodedCommand '+$sleep
    $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
    $peer=[Diagnostics.Process]::Start($psi)
    $script:frames=@();$watch=[Diagnostics.Stopwatch]::StartNew()
    $result=Invoke-ForjaPackageProcess $shell @('-NoProfile','-EncodedCommand',$sleep) 'Fixture timeout' -TimeoutSeconds 1 -NonInteractive
    $watch.Stop()
    Assert ($result.TimedOut -and $result.ExitCode -eq -2 -and $watch.Elapsed.TotalSeconds -lt 10) 'consulta trabada retorna dentro de un plazo acotado'
    Assert (-not $peer.HasExited) 'timeout no termina otros procesos ni sesiones'
    Assert (@($script:frames | Where-Object Completed).Count -eq 0 -and @($script:frames | Where-Object Failed).Count -gt 0) 'timeout no muestra exito en la barra'
} finally {if($peer){if(-not $peer.HasExited){$peer.Kill();$null=$peer.WaitForExit(3000)};$peer.Dispose()}}
Assert ($raw -notmatch 'Invoke-ForjaTool vercel login|Invoke-ForjaTool vercel whoami') 'asistente no conserva comprobaciones Vercel que abren login implicito'
Write-Host "RESULTADO CONEXIONES: $passed PASS / 0 FAIL"
$global:LASTEXITCODE=0
