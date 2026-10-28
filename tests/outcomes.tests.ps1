$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$raw=[IO.File]::ReadAllText((Join-Path $root 'forja-del-desarrollador.bat'))
$errors=$null;$tokens=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($raw,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors | Out-String)}
foreach($f in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)){. ([scriptblock]::Create($f.Extent.Text))}
$passed=0
function Assert {param([bool]$Condition,[string]$Message) if(-not $Condition){throw "FALLO: $Message"};$script:passed++;Write-Host "PASS $Message"}
function Get-ForjaToolPath {param($Name) return 'C:\fixture\npm.cmd'}
function Test-NpmPkg {param($Package) return $false}
function Get-ForjaStackCommand {param($Name) return $null}
function Get-ForjaStoreApp {param($Tool) return [pscustomobject]@{State=$script:storeState;Version='26.1.2'}}
function Get-ForjaAlternatePackage {param($Tool)
    switch($Tool.Id){'rust'{return 'rustup: C:\fixture\rustup.exe'};'jdk17'{return 'Scoop temurin17-jdk 17.0.1'};'jdk21'{return 'Scoop temurin21-jdk 21.0.1'}}
    return $null
}
function Get-WingetPackageInfo {param($Id)
    if($Id -in @('Google.AndroidStudio','CondaForge.Miniforge3')){return [pscustomobject]@{State='installed';Version='1.0.0';Available='2.0.0'}}
    return [pscustomobject]@{State='absent';Version=$null;Available=$null}
}
function Invoke-ForjaWingetOperation {param($ArgumentList,$Label) $script:providerCalls++;$global:LASTEXITCODE=-1978334956;return 'Publisher upgrade required'}
function Invoke-ForjaTool {throw 'PROHIBIDO ejecutar npm u otra CLI real en estas pruebas'}
function Save-ForjaToolArchive {throw 'PROHIBIDO descargar paquetes en estas pruebas'}
function Invoke-ForjaPythonLibraries {throw 'PROHIBIDO modificar entornos Python en estas pruebas'}
function Ask-SN {param($Prompt) return $false}
$savedLocal=$env:LOCALAPPDATA
# No se crea la carpeta; solo se comprueba ausencia bajo una identidad temporal unica.
$env:LOCALAPPDATA=Join-Path ([IO.Path]::GetTempPath()) ('forja-outcomes-'+[guid]::NewGuid().ToString('N'))
$script:ForjaResults=@();$script:storeState='installed';$script:providerCalls=0
try {
    foreach($id in @('codex-cli','agy-cli','cursor-cli','gemini-cli','neon-cli','resend-cli','render-cli','cloudflared','dotnet','python-web-vision')){
        $tool=Get-ForjaSelection -Id $id
        $result=Invoke-ForjaExplainedStep $tool {Invoke-ForjaStackTool $tool -Update} -Update
        Assert ($result.State -eq 'saltado' -and $result.Kind -eq 'absent' -and $result.Reason.Length -gt 20) "$id ausente informa motivo sin instalar"
        Assert ($result.Next -match $tool.Code) "$id ofrece su codigo correcto para continuar"
    }
    $tool=Get-ForjaSelection -Id 'codex-app'
    $result=Invoke-ForjaExplainedStep $tool {Invoke-ForjaStackTool $tool -Update} -Update
    Assert ($result.Kind -eq 'delegated' -and $result.Reason -match '26.1.2' -and $result.Label -eq 'GESTIONADO POR STORE') 'app instalada se distingue de una app ausente'
    Assert ($result.State -eq 'saltado' -and $result.Next -match 'Microsoft Store' -and $result.Reason -match 'no comprobo') 'Store no se presenta como version mas nueva verificada'
    $tool=Get-ForjaSelection -Id 'wrangler'
    $result=Invoke-ForjaExplainedStep $tool {Invoke-ForjaStackTool $tool -Update} -Update
    Assert ($result.Kind -eq 'project' -and $result.Next -match 'T28' -and $result.Next -match 'package.json') 'Wrangler explica proyecto requerido y como elegirlo'
    foreach($id in @('rust','jdk17','jdk21')){
        $tool=Get-ForjaSelection -Id $id
        $result=Invoke-ForjaExplainedStep $tool {Invoke-ForjaStackTool $tool -Update} -Update
        Assert ($result.State -eq 'pendiente' -and $result.Kind -eq 'external' -and $result.Reason -match 'otro gestor') "$id instalado se explica como gestor externo"
        $expected='scoop update';if($id -eq 'rust'){$expected='rustup update'}
        Assert ($result.Next -match $expected) "$id indica su gestor sin ejecutarlo"
    }
    foreach($id in @('android','miniforge')){
        $tool=Get-ForjaSelection -Id $id
        $result=Invoke-ForjaExplainedStep $tool {Invoke-ForjaStackTool $tool -Update} -Update
        Assert ($result.State -eq 'pendiente' -and $result.Kind -eq 'unsupported' -and $result.Reason -match '0x8A150114' -and $result.Reason -match '1.0.0 -> 2.0.0') "$id conserva codigo versiones y restriccion del proveedor"
        $expected='Conda';if($id -eq 'android'){$expected='Android Studio'}
        Assert ($result.Next -match $expected) "$id ofrece accion especifica del proveedor"
    }
    Assert ($script:providerCalls -eq 2) 'actualizacion no admitida se consulta una vez por herramienta sin reintentos'
    $tool=Get-ForjaSelection -Id 'neon-cli'
    $result=Invoke-ForjaExplainedStep $tool {return 'aldia'} -Update
    Assert ($result.Kind -eq '' -and $result.Reason -notmatch '0x8A150114|Conda|Android Studio') 'el motivo de la herramienta anterior no contamina otra'
    $result=Invoke-ForjaExplainedStep $tool {throw 'FIXTURE_PROVIDER_FAILURE'} -Update
    Assert ($result.State -eq 'error' -and $result.Reason -match 'FIXTURE_PROVIDER_FAILURE') 'excepcion preserva causa concreta en el resultado'
    $result=Invoke-ForjaExplainedStep $tool {return @('ok','unconfirmed')} -Update
    Assert ($result.State -eq 'error' -and $result.Reason -match 'unico') 'salida ambigua nunca se anuncia como exito'
    $result=Invoke-ForjaExplainedStep $tool {Write-Warn 'FIXTURE_QUERY_ERROR';return 'error'} -Update
    Assert ($result.Reason -match 'FIXTURE_QUERY_ERROR') 'error sin detalle estructurado conserva el aviso del paso'
    $result=Invoke-ForjaExplainedStep $tool {return 'error'} -Update
    Assert ($result.Reason -notmatch 'FIXTURE_QUERY_ERROR') 'avisos de otro paso tampoco se heredan'
    $script:ForjaResults=@();$script:updOK=0;$script:updAlDia=0;$script:updSaltado=0;$script:updError=0;$script:updPendiente=0;$script:updAvisos=0
    $results=@(Invoke-ForjaStackProfile -Update)
    Assert ($results.Count -eq 25 -and @($results | Where-Object {-not $_.Reason -or -not $_.Next -or -not $_.Code}).Count -eq 0) 'recorrido completo conserva motivo accion y codigo para cada herramienta'
    Assert (($script:updOK+$script:updAlDia+$script:updSaltado+$script:updError+$script:updPendiente) -eq 25) 'nuevas explicaciones no duplican contadores'
    $summary=@(Show-ForjaOutcomeSummary 6>&1 | ForEach-Object {$_.ToString()}) -join "`n"
    Assert ($summary -match 'Neon CLI' -and $summary -match 'T24' -and $summary -match 'Microsoft Store' -and $summary -match '0x8A150114' -and $summary -match 'rustup update') 'resumen final conserva causas y acciones de distintas herramientas'
    $lines=@($summary -split '\r?\n')
    Assert (@($lines | Where-Object {$_.Length -gt 80}).Count -eq 0) 'detalle final respeta el ancho de consola'
    $results=@(Invoke-ForjaStackProfile)
    Assert (@($results | Where-Object {$_.Kind -ne 'declined' -or $_.State -ne 'saltado'}).Count -eq 0) 'setup distingue herramientas no elegidas de instalaciones ausentes'
    Assert ($script:providerCalls -eq 4) 'explicar cancelaciones no ejecuta instaladores ni consultas nuevas al proveedor'
    Write-Host "RESULTADO EXPLICACIONES: $passed PASS / 0 FAIL"
    # El mock deja un fallo WinGet esperado. Solo tras pasar todas las aserciones,
    # cerrar la bateria con exito para el wrapper de GitHub Actions.
    $global:LASTEXITCODE=0
} finally {$env:LOCALAPPDATA=$savedLocal}
