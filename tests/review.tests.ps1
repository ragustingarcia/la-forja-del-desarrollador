# Regresiones de la revision integral. Sin logins, red ni instaladores reales.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$raw=[IO.File]::ReadAllText((Join-Path $root 'forja-del-desarrollador.bat'))
$errors=$null;$tokens=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($raw,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
foreach($f in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)){. ([scriptblock]::Create($f.Extent.Text))}
$passed=0
function Assert {param([bool]$Condition,[string]$Message) if(-not $Condition){throw "FALLO: $Message"};$script:passed++;Write-Host "PASS $Message"}
function Get-ForjaConnectionCommand {param($Name) if($script:missing){return $null};return [pscustomobject]@{Executable='C:\fixture\node.exe';Arguments=@('C:\fixture\cli.js')}}
function Invoke-ForjaPackageProcess {param($Executable,$ArgumentList,$Label,$TimeoutSeconds,[switch]$NonInteractive)
    $script:commands+=,@($ArgumentList);$script:timeout=$TimeoutSeconds;$script:nonInteractive=[bool]$NonInteractive
    return $script:result
}
function Start-Process {throw 'PROHIBIDO abrir browser o procesos reales'}
$script:commands=@();$script:missing=$false
$script:result=[pscustomobject]@{ExitCode=1;TimedOut=$false;Stdout='{"loggedIn":true,"linked":false,"error":{"code":"NOT_LINKED"}}';Output=@('warning: project missing')}
$session=Get-ForjaServiceSession netlify
Assert ($session.State -eq 'connected' -and $session.Reason -match 'carpeta no esta vinculada') 'Netlify cuenta valida sin proyecto no pide repetir login'
Assert ($script:timeout -eq 30 -and $script:nonInteractive -and $script:commands[-1] -contains '--json') 'Netlify consulta JSON con timeout y stdin cerrado'
foreach($fixture in @(
    @{Exit=1;Json='{"loggedIn":false,"error":{"code":"NOT_LOGGED_IN"}}'},
    @{Exit=0;Json='{"loggedIn":"false"}'},
    @{Exit=2;Json='{"loggedIn":true,"error":{"code":"NOT_LINKED"}}'},
    @{Exit=1;Json='{"loggedIn":true,"error":{"code":"NETWORK_ERROR"}}'},
    @{Exit=0;Json='SENSITIVE_SENTINEL invalid json'}
)){
    $script:result=[pscustomobject]@{ExitCode=$fixture.Exit;TimedOut=$false;Stdout=$fixture.Json;Output=@()}
    $session=Get-ForjaServiceSession netlify
    Assert ($session.State -eq 'pending' -and $session.Reason -notmatch 'SENSITIVE_SENTINEL') 'Netlify ambiguo o fallido no confirma cuenta ni filtra salida'
}
$script:result=[pscustomobject]@{ExitCode=0;TimedOut=$false;Stdout='[]';Output=@()}
Assert ((Get-ForjaServiceSession supabase).State -eq 'connected') 'Supabase autentica aunque no haya proyectos'
$script:result.Stdout='{"error":"SENSITIVE_SENTINEL"}'
Assert ((Get-ForjaServiceSession supabase).State -eq 'pending') 'Supabase no acepta objeto de error como lista'
$script:result.Stdout='"27.1.2"'
Assert ((Get-ForjaServiceSession docker).State -eq 'connected') 'Docker valida motor con version JSON'
$script:result.Stdout='null'
Assert ((Get-ForjaServiceSession docker).State -eq 'pending') 'Docker salida vacia no equivale a motor disponible'
foreach($name in @('gh','netlify','supabase','snyk','docker')){
    $script:result=[pscustomobject]@{ExitCode=-2;TimedOut=$true;Output=@('PRIVATE_DEVICE_CODE')}
    $session=Get-ForjaServiceSession $name
    Assert ($session.State -eq 'timeout' -and $session.Reason -notmatch 'PRIVATE_DEVICE_CODE') "$name timeout preserva pendiente sin divulgar datos"
    $script:missing=$true;$count=$script:commands.Count
    Assert ((Get-ForjaServiceSession $name).State -eq 'missing' -and $script:commands.Count -eq $count) "$name ausente no lanza procesos"
    $script:missing=$false
}
Assert (@($script:commands | Where-Object {$_ -contains 'login' -or $_ -contains 'logout' -or $_ -contains '--show-token'}).Count -eq 0) 'consultas no autentican ni leen tokens'
$savedResolver=${function:Get-ForjaToolPath}
function Get-ForjaToolPath {param($Name) if($Name -eq 'claude' -and $script:hasClaude){return 'C:\fixture\native\claude.exe'};return $null}
function Invoke-ForjaTool {param($Name) if($Name -ne 'claude' -or $args[0] -ne '--version'){throw 'No debe depender de npm cuando Claude existe'};$global:LASTEXITCODE=$script:runtimeCode;return '2.1.312'}
function Invoke-ForjaCatalogNpm {param($Tool) $script:installs++;return 'ok'}
$script:hasClaude=$true;$script:runtimeCode=0;$script:installs=0
Assert ((Invoke-ForjaClaudeInstall) -eq 'aldia' -and $script:installs -eq 0) 'Claude nativo operativo sin npm no instala duplicado'
$script:runtimeCode=1
Assert ((Invoke-ForjaClaudeInstall) -eq 'pendiente' -and $script:installs -eq 0) 'Claude roto se conserva y no se oculta con otra instalacion'
$script:hasClaude=$false
Assert ((Invoke-ForjaClaudeInstall) -eq 'ok' -and $script:installs -eq 1) 'Claude ausente usa instalador verificado'
Set-Item Function:Get-ForjaToolPath $savedResolver
function Test-Path {param($LiteralPath,$PathType) return ($LiteralPath -like '*\.local\bin\claude.exe')}
function Get-Command {throw 'No debe depender de PATH para encontrar Claude nativo'}
Assert ((Get-ForjaToolPath claude) -eq (Join-Path $env:USERPROFILE '.local\bin\claude.exe')) 'resolver encuentra Claude fuera del PATH antes de npm'
function Invoke-ForjaTool {param($Name)
    if($args[0] -eq 'list'){$global:LASTEXITCODE=0;return ('snyk@'+$script:localVersion)}
    if($args[0] -eq 'view'){$global:LASTEXITCODE=0;return '1.2.0'}
    throw 'PROHIBIDO degradar version o cambiar canal'
}
foreach($version in @('2.0.0','2.0.0-beta.1','unknown')){
    $script:localVersion=$version
    Assert ((Invoke-NpmUpdate snyk Snyk) -eq 'pendiente') "npm conserva canal o version local $version"
}
function Get-Command {param($Name,$ErrorAction) return [pscustomobject]@{Source='C:\fixture\winget.exe'}}
function Get-WingetPackageInfo {param($Id) return [pscustomobject]@{State=$script:inventoryState;Detail='FIXTURE_QUERY_FAILURE'}}
function Invoke-ForjaWingetOperation {param($ArgumentList,$Label) $script:wingetInstalls++;$global:LASTEXITCODE=0}
$script:inventoryState='error';$script:wingetInstalls=0
Assert (-not (Install-Winget Git.Git Git) -and $script:wingetInstalls -eq 0) 'error de inventario nunca se trata como ausencia para instalar'
$script:inventoryState='absent'
Assert (-not (Install-Winget Git.Git Git) -and $script:wingetInstalls -eq 1) 'instalador exit cero sin registro no informa exito'
function Invoke-ForjaTool {param($Name) $global:LASTEXITCODE=$script:npmCode;return $script:npmOutput}
foreach($fixture in @(
    @{Code=1;Output='(empty)';Failed=$false},
    @{Code=1;Output='npm error EACCES';Failed=$true},
    @{Code=0;Output='';Failed=$true},
    @{Code=5;Output='(empty)';Failed=$true}
)){
    $script:npmCode=$fixture.Code;$script:npmOutput=$fixture.Output
    $present=Test-NpmPkg snyk
    Assert (-not $present -and $script:ForjaNpmQueryFailed -eq $fixture.Failed) ('npm distingue ausencia de fallo: '+$fixture.Output)
}
Assert ($raw -notmatch 'Invoke-ForjaTool (netlify|supabase|snyk) (login|auth)\s|^\s*gh auth login\s*$') 'setup no ejecuta logins dentro del instalador'
Write-Host "RESULTADO REVISION: $passed PASS / 0 FAIL"
$global:LASTEXITCODE=0
