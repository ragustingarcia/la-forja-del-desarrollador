$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$raw=[IO.File]::ReadAllText((Join-Path $root 'forja-del-desarrollador.bat'))
$errors=$null;$tokens=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($raw,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors | Out-String)}
foreach($f in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)){. ([scriptblock]::Create($f.Extent.Text))}
$passed=0
function Assert {param([bool]$Condition,[string]$Message) if(-not $Condition){throw "FALLO: $Message"};$script:passed++;Write-Host "PASS $Message"}
function Assert-Fails {param([scriptblock]$Action,[string]$Message) $failed=$false;try{& $Action}catch{$failed=$true};Assert $failed $Message}
$catalog=@(Get-ForjaStackCatalog)
$source=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $root 'catalog\stack-ia.json')))
Assert (($catalog | ConvertTo-Json -Depth 8 -Compress) -ceq ($source | ConvertTo-Json -Depth 8 -Compress)) 'catalogo embebido coincide con JSON distribuido'
Assert (@($catalog | Group-Object Id | Where-Object Count -gt 1).Count -eq 0) 'identidades unicas'
foreach($id in @('cursor','antigravity','antigravity-ide','gemini-app','grok-bot','codex-app','codex-cli','agy-cli','cursor-cli','neon-cli','resend-cli','render-cli','cloudflared','wrangler','python-web-vision')){Assert (@($catalog | Where-Object Id -eq $id).Count -eq 1) "stack contiene $id"}
Assert (@($catalog | Where-Object {$_.Name -match 'Steam|Chrome$|Driver|OneDrive|Office|Razer|VLC|Audacity'}).Count -eq 0) 'sin controladores ni programas cotidianos'
Assert (($catalog | Where-Object Id -eq 'codex-app').Package -eq '9PLM9XGG6VKS' -and ($catalog | Where-Object Id -eq 'codex-cli').Package -eq '@openai/codex') 'app Store y CLI Codex tienen identidades separadas'
Assert (($catalog | Where-Object Id -eq 'resend-cli').Package -eq 'resend-cli' -and ($catalog | Where-Object Id -eq 'neon-cli').Package -eq 'neon') 'paquetes oficiales Neon y Resend'
Assert (($catalog | Where-Object Id -eq 'wrangler').Method -eq 'project-npm') 'Wrangler local al proyecto'
Assert (($catalog | Where-Object Id -eq 'gemini-cli').Notice -match 'cuentas personales') 'Gemini CLI informa limitacion de cuentas'
Assert (@($catalog | Where-Object Method -eq 'archive' | Where-Object {$_.Sha256 -notmatch '^[0-9A-F]{64}$' -or $_.Uri -notmatch '^https://'}).Count -eq 0) 'descargas nativas tienen URI HTTPS y SHA-256 fijos'
$tool=($catalog | Where-Object Id -eq 'render-cli') | Select-Object *
$tool.Uri='https://example.invalid/forbidden.zip'
Assert-Fails {Save-ForjaToolArchive $tool 'C:\never-download.zip'} 'URL alterada se rechaza antes de descargar'

$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('forja-stack-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($sandbox) | Out-Null
$savedLocal=$env:LOCALAPPDATA
$env:LOCALAPPDATA=$sandbox
$script:ForjaWorkspaces=@{}
try {
    Add-Type -AssemblyName System.IO.Compression
    function New-ZipFixture {param([string]$Path,[string]$Case)
        $file=[IO.File]::Open($Path,[IO.FileMode]::Create,[IO.FileAccess]::ReadWrite)
        $zip=New-Object IO.Compression.ZipArchive($file,[IO.Compression.ZipArchiveMode]::Create,$true)
        try{
            $names=@('render.exe')
            if($Case -eq 'traversal'){$names=@('../escape.exe')}
            if($Case -eq 'absolute'){$names=@('/escape.exe')}
            if($Case -eq 'ads'){$names=@('render.exe:evil')}
            if($Case -eq 'duplicate'){$names=@('render.exe','RENDER.exe')}
            if($Case -eq 'reserved'){$names=@('folder. /render.exe')}
            if($Case -eq 'device'){$names=@('CON.txt')}
            foreach($name in $names){
                $entry=$zip.CreateEntry($name)
                if($Case -eq 'symlink'){$entry.ExternalAttributes=-1577058304}
                $writer=New-Object IO.StreamWriter($entry.Open());try{$writer.Write('INERT FIXTURE')}finally{$writer.Dispose()}
            }
        }finally{$zip.Dispose();$file.Dispose()}
    }
    function Get-ForjaStackCommand {param($Name) if($script:external){return 'C:\external\tool.exe'};return $null}
    function Save-ForjaToolArchive {param($Tool,$Destination) Copy-Item -LiteralPath $script:fixture -Destination $Destination}
    function Invoke-ForjaCommand {param($Path,$Arguments) $script:executions++;$global:LASTEXITCODE=0;if($script:badRuntime){return '0.0.0'};return 'render v2.33.0'}
    $script:external=$false
    foreach($case in @('success','traversal','absolute','ads','duplicate','reserved','device','symlink','hash-mismatch','runtime-failure')){
        $script:fixture=Join-Path $sandbox ($case+'.zip')
        New-ZipFixture $script:fixture $case
        $tool=($catalog | Where-Object Id -eq 'render-cli') | Select-Object *
        $tool.Id='fixture-'+$case
        $tool.Sha256=(Get-FileHash -LiteralPath $script:fixture -Algorithm SHA256).Hash
        if($case -eq 'hash-mismatch'){$tool.Sha256='A'*64}
        $script:executions=0;$script:badRuntime=($case -eq 'runtime-failure')
        $result=@(Invoke-ForjaArchiveTool $tool)
        $expected='error';if($case -eq 'success'){$expected='ok'}
        Assert ($result.Count -eq 1 -and $result[0] -eq $expected) "archivo $case devuelve estado $expected"
        if($case -notin @('success','runtime-failure')){Assert ($script:executions -eq 0) "$case no ejecuta contenido rechazado"}
        if($case -eq 'success'){
            $installed=Get-ForjaManagedRoot $tool
            Assert ((Invoke-ForjaArchiveTool $tool) -eq 'aldia') 'segunda pasada verifica version nativa'
            $cmd=Get-Content -LiteralPath (Join-Path $installed $tool.Launcher) -Raw
            Assert ($cmd -notmatch 'ExecutionPolicy|powershell|Invoke-Expression') 'launcher nativo sin cambios de politica'
            [IO.File]::WriteAllText((Join-Path $installed '.forja-tool.json'),'{}')
            Assert ((Invoke-ForjaArchiveTool $tool) -eq 'pendiente') 'comprobante alterado no se acepta ni se reemplaza'
        } else {Assert (-not (Test-Path -LiteralPath (Get-ForjaManagedRoot $tool))) "$case no publica instalacion parcial"}
        Assert ($script:ForjaWorkspaces.Count -eq 0) "$case limpia solo su temporal registrado"
    }
    $script:external=$true
    Assert ((Invoke-ForjaArchiveTool ($catalog | Where-Object Id -eq 'render-cli') -Update) -eq 'pendiente') 'instalacion nativa externa no se sobrescribe'
    $script:external=$false
    Assert ((Invoke-ForjaArchiveTool ($catalog | Where-Object Id -eq 'render-cli') -Update) -eq 'saltado') 'actualizar no instala archivo ausente'

    $script:wingetQueries=@();$script:wingetUpdates=@();$script:pythonError=$false
    function Get-WingetPackageInfo {param($Id)
        $script:wingetQueries+=$Id
        if($script:pythonError){return [pscustomobject]@{State='error'}}
        $state='absent';if($Id -in @('Python.Python.3.12','Python.Python.3.14')){$state='installed'}
        return [pscustomobject]@{State=$state}
    }
    function Invoke-WingetUpdate {param($Id,$Name) $script:wingetUpdates+=$Id;return 'aldia'}
    Assert ((Invoke-ForjaPythonUpdates) -eq 'aldia') 'Python actualiza todas las ramas detectadas'
    Assert ($script:wingetQueries.Count -eq 6 -and $script:wingetUpdates.Count -eq 2 -and $script:wingetUpdates -contains 'Python.Python.3.12' -and $script:wingetUpdates -contains 'Python.Python.3.14') 'no se detiene en la primera rama de Python'
    $script:pythonError=$true
    Assert ((Invoke-ForjaPythonUpdates) -eq 'error') 'consulta Python fallida no se informa como al dia'

    $script:allowMajor=$false;$script:majorInstalled=$false;$script:majorCalls=0;$script:confirmMajor=$true
    function Ask-SN {param($Prompt) return $script:allowMajor}
    function Get-WingetPackageInfo {param($Id)
        $state='absent'
        if($Id -eq 'Python.Python.3.12' -or ($Id -eq 'Python.Python.3.14' -and $script:majorInstalled)){$state='installed'}
        return [pscustomobject]@{State=$state}
    }
    function Install-Winget {param($Id,$Name) $script:majorCalls++;$script:majorInstalled=$script:confirmMajor;return $true}
    Assert ((Invoke-ForjaPythonUpdates -OfferNewBranch) -eq 'aldia' -and $script:majorCalls -eq 0) 'rechazar nueva rama Python no instala ni migra nada'
    $script:allowMajor=$true
    Assert ((Invoke-ForjaPythonUpdates -OfferNewBranch) -eq 'ok' -and $script:majorCalls -eq 1) 'nueva rama Python requiere aceptacion y registro confirmado'
    $script:majorInstalled=$false;$script:confirmMajor=$false
    Assert ((Invoke-ForjaPythonUpdates -OfferNewBranch) -eq 'pendiente') 'installer Python exit cero sin registro queda pendiente'
    $previousProfile=$env:USERPROFILE
    try{
        $env:USERPROFILE=Join-Path $sandbox 'profile'
        $scoop=Join-Path $env:USERPROFILE 'scoop\apps\temurin17-jdk\current'
        [IO.Directory]::CreateDirectory($scoop) | Out-Null
        [IO.File]::WriteAllText((Join-Path $scoop 'manifest.json'),'{"version":"17.0.20-8"}')
        $jdk=$catalog | Where-Object Id -eq 'jdk17'
        Assert ((Get-ForjaAlternatePackage $jdk) -eq 'Scoop temurin17-jdk 17.0.20-8') 'reconoce el JDK de Scoop sin ejecutar su bootstrap'
        $calls=$script:majorCalls
        Assert ((Invoke-ForjaStackTool $jdk) -eq 'aldia' -and $script:majorCalls -eq $calls) 'setup no duplica un JDK de Scoop'
        Assert ((Invoke-ForjaStackTool $jdk -Update) -eq 'pendiente' -and $script:majorCalls -eq $calls) 'update conserva el gestor original del JDK'
    }finally{$env:USERPROFILE=$previousProfile}

    $script:npmInstalled=$false;$script:npmVersion='1.2.3';$script:npmCalls=@();$script:runtimeOK=$true
    function Get-ForjaToolPath {param($Name) return 'C:\fixture\npm.cmd'}
    function Test-NpmPkg {param($Package) return $script:npmInstalled}
    function Test-NpmRuntime {param($Package,$Version) return $script:runtimeOK}
    function Invoke-ForjaTool {param($Name)
        $script:npmCalls+=,(@($Name)+$args)
        $global:LASTEXITCODE=0
        switch($args[0]){
            'view' {return $script:npmVersion}
            'install' {$script:npmInstalled=$true;return 'fixture install'}
            'list' {return 'resend-cli@1.2.3'}
            default {throw 'Comando npm inesperado'}
        }
    }
    $resend=$catalog | Where-Object Id -eq 'resend-cli'
    Assert ((Invoke-ForjaCatalogNpm $resend -Update) -eq 'saltado') 'update npm no instala una CLI ausente'
    Assert ((Invoke-ForjaCatalogNpm $resend) -eq 'ok') 'instalacion CLI npm valida metadata y runtime'
    Assert (@($script:npmCalls | Where-Object {($_ -join ' ') -eq 'npm install -g resend-cli@1.2.3'}).Count -eq 1) 'instala una version concreta del paquete oficial'
    $script:npmInstalled=$false;$script:npmVersion="1.2.3`nmalicious"
    $count=$script:npmCalls.Count
    Assert ((Invoke-ForjaCatalogNpm $resend) -eq 'error') 'version npm malformada se rechaza'
    Assert (@($script:npmCalls | Select-Object -Skip $count | Where-Object {$_ -contains 'install'}).Count -eq 0) 'version invalida no llega al instalador'
    $script:npmVersion='1.2.3';$script:runtimeOK=$false
    Assert ((Invoke-ForjaCatalogNpm $resend) -eq 'error') 'npm exit cero con CLI rota no informa exito'

    function Read-Host {param($Prompt) return $script:answer}
    function Test-ForjaWranglerPlatform {return $true}
    $script:answer=''
    Assert ((Invoke-ForjaWranglerProject) -eq 'pendiente') 'Wrangler cancelado no modifica proyectos'
    $script:answer='relative-project'
    Assert ((Invoke-ForjaWranglerProject) -eq 'error') 'Wrangler rechaza ruta relativa'
    $project=Join-Path $sandbox 'project';[IO.Directory]::CreateDirectory($project) | Out-Null
    $script:answer=$project
    Assert ((Invoke-ForjaWranglerProject) -eq 'error') 'Wrangler requiere package.json existente'
    [IO.File]::WriteAllText((Join-Path $project 'package.json'),'{"name":"fixture"}')
    function Ask-SN {param($Prompt) return $false}
    $count=$script:npmCalls.Count
    Assert ((Invoke-ForjaWranglerProject) -eq 'pendiente') 'Wrangler requiere confirmacion del proyecto concreto'
    Assert ($script:npmCalls.Count -eq $count) 'sin aprobacion no invoca npm sobre el proyecto'

    function Ask-SN {param($Prompt) return $true}
    $script:npmVersion='3.8.0';$script:npmCalls=@()
    function Invoke-ForjaTool {param($Name)
        $script:npmCalls+=,(@($Name)+$args);$global:LASTEXITCODE=0
        if($args[0] -eq 'view'){return '3.8.0'}
        if($args[0] -eq 'install'){
            $index=[array]::IndexOf($args,'--prefix');if($index -lt 0){throw 'Falta --prefix'}
            $target=$args[$index+1]
            $modules=Join-Path $target 'node_modules\wrangler';$bin=Join-Path $target 'node_modules\.bin'
            [IO.Directory]::CreateDirectory($modules) | Out-Null;[IO.Directory]::CreateDirectory($bin) | Out-Null
            [IO.File]::WriteAllText((Join-Path $modules 'package.json'),'{"version":"3.8.0"}')
            [IO.File]::WriteAllText((Join-Path $bin 'wrangler.cmd'),'INERT FIXTURE')
            return 'fixture install'
        }
        throw 'npm inesperado'
    }
    function Invoke-ForjaCommand {param($Path,$Arguments) $global:LASTEXITCODE=0;return 'wrangler 3.8.0'}
    Assert ((Invoke-ForjaWranglerProject) -eq 'ok') 'Wrangler confirmado verifica paquete y ejecutable del proyecto'
    $install=@($script:npmCalls | Where-Object {$_ -contains 'install'})[0]
    Assert ($install -contains $project -and $install -contains '--save-dev' -and $install -notcontains '-g') 'Wrangler nunca usa instalacion global ni otro directorio'
    function Test-ForjaWranglerPlatform {return $false}
    $count=$script:npmCalls.Count
    Assert ((Invoke-ForjaWranglerProject) -eq 'pendiente' -and $script:npmCalls.Count -eq $count) 'Wrangler no instala en Windows fuera del soporte declarado'

    $script:storeState='error';$script:storeCalls=0;$script:storeQueries=0
    function Get-ForjaStoreApp {param($Tool) $script:storeQueries++;return [pscustomobject]@{State=$script:storeState;Version='1.2.3'}}
    function winget {$script:storeCalls++;$script:storeArgs=$args;$script:storeState='installed';$global:LASTEXITCODE=0}
    $storeTool=$catalog | Where-Object Id -eq 'codex-app'
    Assert ((Invoke-ForjaStackTool $storeTool) -eq 'pendiente' -and $script:storeCalls -eq 0) 'fallo consulta Store no dispara instalacion'
    $script:storeState='absent'
    Assert ((Invoke-ForjaStackTool $storeTool) -eq 'ok' -and $script:storeCalls -eq 1) 'app Codex confirma registro despues de Store'
    Assert ($script:storeArgs -contains 'msstore' -and $script:storeArgs -contains '9PLM9XGG6VKS') 'app Codex usa solo el ID Store oficial'
    Assert ((Invoke-ForjaStackTool $storeTool -Update) -eq 'saltado' -and $script:storeCalls -eq 1) 'actualizaciones Store se informan como delegadas sin falso al dia'

    $script:updOK=0;$script:updAlDia=0;$script:updSaltado=0;$script:updError=0;$script:updPendiente=0;$script:updAvisos=0
    function Invoke-ForjaStackTool {param($Tool,[switch]$Update) if($Tool.Id -eq 'cursor'){throw 'fixture failure'};return 'aldia'}
    $results=@(Invoke-ForjaStackProfile -Update)
    Assert ($results.Count -eq @($catalog | Where-Object {-not $_.Core}).Count) 'el recorrido ampliado conserva un resultado por herramienta'
    Assert ($results[0].State -eq 'error' -and $results[-1].State -eq 'aldia' -and $script:updError -eq 1) 'fallo de un agente no interrumpe ni pierde el resumen'
    Assert ($raw -notmatch 'npm install -g supabase|irm .*\| iex|curl .*\| bash') 'sin fallback global Supabase ni bootstrap remoto ejecutado'
    Write-Host "RESULTADO STACK: $passed PASS / 0 FAIL"
} finally {
    $env:LOCALAPPDATA=$savedLocal
    $full=[IO.Path]::GetFullPath($sandbox)
    $parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if([IO.Path]::GetDirectoryName($full) -ne $parent -or [IO.Path]::GetFileName($full) -notmatch '^forja-stack-[0-9a-f]{32}$'){throw 'Raiz de pruebas invalida'}
    $null=@(Get-ForjaTree $full)
    Remove-Item -LiteralPath $full -Recurse -Force
}
