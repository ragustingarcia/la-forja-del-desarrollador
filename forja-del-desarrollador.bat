<# : batch portion
@echo off
setlocal DisableDelayedExpansion
rem Windows PowerShell debe reconstruir sus rutas de modulos, sin heredar las de pwsh.
set "PSModulePath="
set "FORJA_SCRIPT_PATH=%~f0"
rem Ruta por entorno: nunca interpolar el nombre del BAT dentro de codigo PowerShell.
rem El payload se lee en memoria; no hay VBS, PS1 temporal ni elevacion global.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -Command "try { Set-Location -LiteralPath $env:SystemRoot; & ([scriptblock]::Create([IO.File]::ReadAllText($env:FORJA_SCRIPT_PATH, [Text.Encoding]::UTF8))) } catch { Write-Host 'La Forja se detuvo. Revisa el archivo y las politicas del equipo.' -ForegroundColor Red; exit 1 }"
set "FORJA_EXIT_CODE=%ERRORLEVEL%"
echo.
echo   Presiona cualquier tecla para cerrar...
pause >nul
exit /b %FORJA_EXIT_CODE%
: end batch / begin PowerShell #>

# ============================================================
#  FORJA DEL DESARROLLADOR
#  Stack para crear con agentes de IA en Windows
#  by Rodolfo Agustin Garcia  |  ragustingarcia.com
#  https://github.com/ragustingarcia/la-forja-del-desarrollador
# ============================================================

$VERSION = "v6.2.0"
# Ni npm, ni skills, ni conexiones deben heredar privilegios de administrador.
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Abri la Forja con doble clic, desde una terminal SIN elevar.' -ForegroundColor Yellow
    exit 1
}
# Evitar resolucion de herramientas/configuracion desde el directorio descargado.
Set-Location -LiteralPath (Join-Path $env:SystemRoot 'System32')
$script:ForjaWorkspaces = @{}
$script:ForjaWingetInventory = $null
$ForjaSkillsRevision = '2bd31daa7d7334cebbe561d2fbe43bd1fa07b9ce'
$AnthropicSkillsRevision = 'dbd4588f9e1033efb41dad4bef2f7947c8993d44'
$Host.UI.RawUI.WindowTitle = "Forja del Desarrollador $VERSION"

function Write-OK      { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Err     { param($msg) Write-Host "  [X]  $msg" -ForegroundColor Red }
function Write-Warn    { param($msg) Write-Host "  [!]  $msg" -ForegroundColor Yellow }
function Write-Info    { param($msg) Write-Host "  $msg" -ForegroundColor Cyan }
function Write-Section { param($msg) Write-Host $msg -ForegroundColor Yellow }
function Write-Dim     { param($msg) Write-Host "  $msg" -ForegroundColor DarkGray }

function Write-Titulo { param($num, $total, $nombre, $desc)
    Write-Host ""
    Write-Section "============================================================"
    Write-Section "  [$num/$total] $nombre"
    Write-Dim     "  $desc"
    Write-Section "============================================================"
    Write-Host ""
}

function Test-PythonReal {
    try { $o = (python --version 2>&1) | Out-String; if ($LASTEXITCODE -eq 0 -and $o -match "Python \d+\.\d+\.\d+") { return $o.Trim() } } catch {}
    return $null
}
function Test-PipReal {
    try { $o = (python -m pip --version 2>&1) | Out-String; if ($LASTEXITCODE -eq 0 -and $o -match "pip \d+") { return $true } } catch {}
    return $false
}
function Test-FastapiInstalled {
    try { $null = python -m pip show fastapi uvicorn python-multipart pdfplumber requests 2>&1; if ($LASTEXITCODE -eq 0) { return $true } } catch {}
    return $false
}
function Test-NpmPkg { param($pkg)
    try { $o = (Invoke-ForjaTool npm list -g $pkg --depth=0 2>&1) | Out-String; if ($LASTEXITCODE -eq 0 -and $o -match ([regex]::Escape($pkg) + "@")) { return $true } } catch {}
    return $false
}
function Format-ForjaProgress {param([string]$Label,[long]$Bytes=0,[long]$Total=-1,[int]$Frame=0,[switch]$Completed,[switch]$Failed)
    $name=$Label;if($name.Length -gt 24){$name=$name.Substring(0,21)+'...'}
    $cells=20
    if($Failed){return ('  '+$name+' ['+('!'*$cells)+'] Interrumpido')}
    if($Total -gt 0){
        $percent=[int][Math]::Floor(([double]$Bytes/$Total)*100);$percent=[Math]::Max(0,[Math]::Min(100,$percent))
        if(-not $Completed){$percent=[Math]::Min(99,$percent)}
        $filled=[int][Math]::Floor($percent*$cells/100)
        return ('  {0} [{1}{2}] {3,3}% {4:0.0}/{5:0.0} MB' -f $name,('#'*$filled),('-'*($cells-$filled)),$percent,($Bytes/1MB),($Total/1MB))
    }
    if($Completed){return ('  '+$name+' ['+('#'*$cells)+'] Etapa finalizada')}
    $position=$Frame % ($cells-3)
    $bar=('-'*$position)+'###'+('-'*($cells-3-$position))
    $detail='en curso';if($Bytes -gt 0){$detail=('{0:0.0} MB; total no informado' -f ($Bytes/1MB))}
    return ('  '+$name+' ['+$bar+'] '+$detail)
}
function Write-ForjaProgress {param([string]$Label,[long]$Bytes=0,[long]$Total=-1,[int]$Frame=0,[switch]$Completed,[switch]$Failed)
    $line=Format-ForjaProgress @PSBoundParameters
    if([Console]::IsOutputRedirected){if($Frame -eq 0 -or $Completed -or $Failed){Write-Host $line};return}
    $width=(Get-ForjaConsoleSize).Width
    if($line.Length -ge $width){$line=$line.Substring(0,$width-1)}
    Write-Host ("`r"+$line.PadRight($width-1)) -NoNewline -ForegroundColor Cyan
    if($Completed -or $Failed){Write-Host ''}
}
function Copy-ForjaDownloadStream {param([IO.Stream]$Source,[string]$Destination,[long]$Total=-1,[string]$Label='Descargando')
    Assert-NoReparsePath $Destination
    $file=$null;$bytes=[long]0;$frame=0;$watch=[Diagnostics.Stopwatch]::StartNew();$last=[long]-1000
    try {
        $file=[IO.File]::Open($Destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $buffer=New-Object byte[] 65536
        Write-ForjaProgress -Label $Label -Total $Total -Frame 0
        while($true){
            $cancel=New-Object Threading.CancellationTokenSource
            try {$cancel.CancelAfter(120000);$read=$Source.ReadAsync($buffer,0,$buffer.Length,$cancel.Token).GetAwaiter().GetResult()}
            finally {$cancel.Dispose()}
            if($read -eq 0){break}
            $bytes+=$read
            if($bytes -gt 2147483648 -or ($Total -gt 0 -and $bytes -gt $Total)){throw 'La descarga supera el tamano esperado.'}
            $file.Write($buffer,0,$read)
            if(($watch.ElapsedMilliseconds-$last) -ge 200){$frame++;Write-ForjaProgress -Label $Label -Bytes $bytes -Total $Total -Frame $frame;$last=$watch.ElapsedMilliseconds}
        }
        if($bytes -eq 0 -or ($Total -gt 0 -and $bytes -ne $Total)){throw 'La descarga esta vacia o incompleta.'}
        $file.Flush()
        Write-ForjaProgress -Label $Label -Bytes $bytes -Total $Total -Frame ($frame+1) -Completed
    } catch {Write-ForjaProgress -Label $Label -Bytes $bytes -Total $Total -Frame ($frame+1) -Failed;throw}
    finally {if($file){$file.Dispose()};$watch.Stop()}
}
function Save-ForjaDownload {param([string]$Uri,[string]$Destination,[string]$Label='Descargando',[switch]$NoRedirect)
    Add-Type -AssemblyName System.Net.Http
    $handler=New-Object Net.Http.HttpClientHandler;$handler.AllowAutoRedirect=$false;$handler.UseDefaultCredentials=$false
    $client=New-Object Net.Http.HttpClient($handler);$client.Timeout=[TimeSpan]::FromSeconds(120)
    $response=$null;$stream=$null
    try {
        $current=[uri]$Uri
        for($redirect=0;$redirect -le 5;$redirect++){
            if($current.Scheme -ne 'https' -or $current.UserInfo){throw 'La descarga requiere HTTPS sin credenciales en la URL.'}
            $response=$client.GetAsync($current,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
            $status=[int]$response.StatusCode
            if($status -ge 300 -and $status -lt 400){
                if($NoRedirect -or $redirect -eq 5 -or -not $response.Headers.Location){throw 'Redireccion de descarga no permitida.'}
                $current=New-Object uri($current,$response.Headers.Location);$response.Dispose();$response=$null;continue
            }
            $null=$response.EnsureSuccessStatusCode();break
        }
        $total=[long]-1;if($null -ne $response.Content.Headers.ContentLength){$total=[long]$response.Content.Headers.ContentLength}
        if($total -gt 2147483648){throw 'Archivo demasiado grande.'}
        $stream=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        Copy-ForjaDownloadStream $stream $Destination $total $Label
    } finally {if($stream){$stream.Dispose()};if($response){$response.Dispose()};$client.Dispose();$handler.Dispose()}
}
function ConvertTo-ForjaNativeArgument {param([AllowEmptyString()][string]$Value)
    if($Value -and $Value -notmatch '[\s"]'){return $Value}
    return ('"'+(($Value -replace '(\\*)"','$1$1\"') -replace '(\\+)$','$1$1')+'"')
}
function Invoke-ForjaPackageProcess {param([string]$Executable,[string[]]$ArgumentList,[string]$Label='Instalando')
    $process=$null;$frame=0
    try {
        # npm se ejecuta con Node directamente: no hay cmd /c ni interpolacion de rutas.
        if([IO.Path]::GetFileName($Executable) -ieq 'npm.cmd'){
            $npmScript=Join-Path (Split-Path $Executable -Parent) 'node_modules\npm\bin\npm-cli.js'
            $node=Join-Path (Split-Path $Executable -Parent) 'node.exe'
            if(-not (Test-Path -LiteralPath $node -PathType Leaf)){$command=Get-Command node.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1;$node=$command.Source}
            if(-not (Test-Path -LiteralPath $npmScript -PathType Leaf)){throw 'No se encontro npm-cli.js junto a npm.cmd.'}
            $Executable=$node;$ArgumentList=@($npmScript)+$ArgumentList
        }
        if(-not [IO.Path]::IsPathRooted($Executable) -or [IO.Path]::GetExtension($Executable) -ine '.exe'){throw 'Ejecutable nativo absoluto requerido.'}
        $psi=New-Object Diagnostics.ProcessStartInfo
        $psi.FileName=$Executable;$psi.Arguments=(@($ArgumentList | ForEach-Object {ConvertTo-ForjaNativeArgument $_}) -join ' ')
        $psi.WorkingDirectory=[Environment]::SystemDirectory
        $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
        $process=New-Object Diagnostics.Process;$process.StartInfo=$psi
        Write-ForjaProgress -Label $Label -Frame 0
        $null=$process.Start()
        $readers=@(
            [pscustomobject]@{Reader=$process.StandardOutput;Pending=$process.StandardOutput.ReadLineAsync();Closed=$false},
            [pscustomobject]@{Reader=$process.StandardError;Pending=$process.StandardError.ReadLineAsync();Closed=$false}
        )
        $captured=New-Object 'System.Collections.Generic.List[string]'
        $afterExit=$null;$phase=$Label
        do {
            foreach($reader in $readers){
                $batch=0
                while(-not $reader.Closed -and $reader.Pending.IsCompleted -and $batch -lt 1000){
                    try {$line=$reader.Pending.GetAwaiter().GetResult()}
                    catch {$reader.Closed=$true;break}
                    if($null -eq $line){$reader.Closed=$true;break}
                    $captured.Add($line);$batch++
                    if($line -match '(?i)Downloading|Descargando'){$phase='Descargando '+$Label}
                    elseif($line -match '(?i)Starting package install|Iniciando.*instal|Installing|Instalando'){$phase='Instalando '+$Label}
                    $reader.Pending=$reader.Reader.ReadLineAsync()
                }
            }
            if($process.HasExited){
                if(-not $afterExit){$afterExit=[Diagnostics.Stopwatch]::StartNew()}
                if(@($readers | Where-Object {-not $_.Closed}).Count -eq 0 -or $afterExit.ElapsedMilliseconds -ge 5000){break}
                [Threading.Thread]::Sleep(50)
            } else {$null=$process.WaitForExit(150)}
            $frame++;Write-ForjaProgress -Label $phase -Frame $frame
        } while($true)
        # Un proceso que el proveedor deja abierto no debe retener la consola de Forja.
        # Se cierran nuestros lectores; no se terminan procesos del usuario ni instaladores.
        foreach($reader in $readers){
            if(-not $reader.Closed){$reader.Reader.Dispose();if($reader.Pending.IsCompleted){try{$null=$reader.Pending.GetAwaiter().GetResult()}catch{}}}
        }
        $text=($captured -join "`n") -replace '\x1b\[[0-?]*[ -/]*[@-~]',''
        $lines=@($text -split '[\r\n]+' | ForEach-Object {($_ -replace '[\x00-\x08\x0b\x0c\x0e-\x1f]','').TrimEnd()} | Where-Object {$_ -and $_.Trim() -notmatch '^[|/\\ -]+$'})
        $code=$process.ExitCode
        Write-ForjaProgress -Label $Label -Frame ($frame+1) -Completed:($code -eq 0) -Failed:($code -ne 0)
        return [pscustomobject]@{ExitCode=$code;Output=$lines}
    } catch {Write-ForjaProgress -Label $Label -Frame ($frame+1) -Failed;Write-Warn $_.Exception.Message;return [pscustomobject]@{ExitCode=-1;Output=@()}}
    finally {if($process){$process.Dispose()}}
}
function Invoke-ForjaWingetOperation {param([string[]]$ArgumentList,[string]$Label)
    $command=Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if(-not $command){$global:LASTEXITCODE=-1;return}
    $result=Invoke-ForjaPackageProcess $command.Source $ArgumentList $Label
    $global:LASTEXITCODE=$result.ExitCode
    foreach($line in $result.Output){Write-Output $line}
}

function Invoke-ForjaGitTransfer {param([string[]]$ArgumentList)
    $command=Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if(-not $command){$global:LASTEXITCODE=-1;return}
    $result=Invoke-ForjaPackageProcess $command.Source $ArgumentList 'Descargando skills'
    $global:LASTEXITCODE=$result.ExitCode
    foreach($line in $result.Output){Write-Output $line}
}
function Get-ForjaToolPath { param(
    [ValidateSet('npm','pnpm','claude','netlify','vercel','supabase','snyk','codex','gemini','neon','resend')][string]$Name
)
    # Para paquetes npm, elegir el shim de ese gestor antes que otra copia de Scoop.
    if ($Name -in @('supabase','codex','gemini','neon','resend')) {
        $npmShim=Join-Path $env:APPDATA ('npm\'+$Name+'.cmd')
        if(Test-Path -LiteralPath $npmShim -PathType Leaf){return $npmShim}
    }
    if ($Name -eq 'supabase') {
        $managed=Get-ForjaStackCatalog | Where-Object Id -eq 'supabase-native'
        $launcher=Join-Path (Get-ForjaManagedRoot $managed) $managed.Launcher
        if(Test-Path -LiteralPath $launcher -PathType Leaf){return $launcher}
    }
    # Especificar extension evita que PowerShell seleccione el shim .ps1 bloqueado.
    foreach ($extension in @('.exe','.cmd')) {
        $command = Get-Command ($Name + $extension) -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { return $command.Source }
    }
    return $null
}
function Invoke-ForjaTool { param([string]$Name)
    $toolArguments = $args
    $path = Get-ForjaToolPath $Name
    if (-not $path) {
        Write-Warn "$Name no tiene un ejecutable .exe/.cmd disponible. Reinicia la terminal."
        $global:LASTEXITCODE = -1
        return
    }
    # Un aviso de stderr no es una excepcion PowerShell ni demuestra fallo de instalacion.
    $ErrorActionPreference = 'Continue'
    if($Name -eq 'npm' -and $toolArguments.Count -gt 0 -and $toolArguments[0] -eq 'install'){
        $result=Invoke-ForjaPackageProcess $path $toolArguments 'Paquetes npm'
        $global:LASTEXITCODE=$result.ExitCode
        foreach($line in $result.Output){Write-Output $line}
        return
    }
    try {
        & $path @toolArguments 2>&1 | ForEach-Object { $_.ToString() }
        $code = $LASTEXITCODE
    } catch {
        Write-Warn "$Name no pudo ejecutarse ($($_.Exception.GetType().Name)). Se continua con los otros pasos."
        $code = -1
    }
    $global:LASTEXITCODE = $code
}
function Get-WingetPackageInfo { param([string]$Id)
    $info = [pscustomobject]@{ State='error'; Version=$null; Available=$null; ExitCode=-1; Detail='' }
    try {
        # El inventario instalado no se filtra por fuente: ese filtro puede ocultar
        # PowerShell ya instalado. La instalacion/upgrade SI restringe la fuente.
        $output = (winget list --id $Id --exact --accept-source-agreements --disable-interactivity 2>&1) | Out-String
        $info.ExitCode = $LASTEXITCODE
    } catch { $info.Detail='No se pudo ejecutar winget list.'; return $info }
    $filteredAbsent = ($info.ExitCode -eq -1978335212)
    if ($filteredAbsent) {
        # Algunos paquetes (PowerShell incluido) aparecen en la tabla general pero
        # no en el filtro --id --exact. Verificar su ID visible en un inventario real.
        if ($null -eq $script:ForjaWingetInventory) {
            try {
                $inventory = winget list --accept-source-agreements --disable-interactivity 2>&1 | Out-String
                $inventoryCode = $LASTEXITCODE
                $script:ForjaWingetInventory = [pscustomobject]@{ Output=$inventory; ExitCode=$inventoryCode }
            } catch { $info.Detail='No se pudo consultar el inventario general de WinGet.'; return $info }
        }
        $output = $script:ForjaWingetInventory.Output
        $info.ExitCode = $script:ForjaWingetInventory.ExitCode
        if ($info.ExitCode -eq -1978335212) { $info.State='absent'; return $info }
    }
    if ($info.ExitCode -ne 0) { $info.Detail="winget list devolvio codigo $($info.ExitCode)."; return $info }
    $output = [regex]::Replace($output, '\x1b\[[0-9;?]*[ -/]*[@-~]', '')
    # Tabla normal: Nombre (variable), ID exacto, version instalada y opcionalmente
    # version disponible/fuente. No depende del idioma de los titulos o mensajes.
    $rows = @([regex]::Matches($output, '(?m)^\s*(?:[^\r\n]*?\s+)?' + [regex]::Escape($Id) + '\s+(?<version>\S+)(?<tail>[^\r\n]*)\r?$'))
    if ($rows.Count -eq 0 -and $filteredAbsent) { $info.State='absent'; return $info }
    if ($rows.Count -ne 1) { $info.Detail='El inventario no contiene una unica fila reconocible para ese ID.'; return $info }
    $info.Version = $rows[0].Groups['version'].Value
    $tail = $rows[0].Groups['tail'].Value.Trim()
    if ($tail) {
        $columns = @($tail -split '\s+')
        if ($columns.Count -eq 2 -and $columns[1] -eq 'winget') { $info.Available=$columns[0] }
        elseif ($columns.Count -ne 1 -or $columns[0] -ne 'winget') {
            $info.Detail='La fila tiene una fuente o formato que requiere revision manual.'; return $info
        }
    }
    $info.State='installed'
    return $info
}
function Test-WingetPkg { param($id)
    return ((Get-WingetPackageInfo $id).State -eq 'installed')
}
function Install-Winget { param($id, $nombre)
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Info "[INSTALANDO] $nombre via winget..."
        Write-Host ""
        Invoke-ForjaWingetOperation @('install','--id',$id,'--exact','--source','winget','--accept-package-agreements','--accept-source-agreements') $nombre 2>&1 | ForEach-Object { Write-Host "  $_" }
        return ($LASTEXITCODE -eq 0)
    }
    return $false
}
function Install-Npm { param($pkg, $nombre)
    Write-Info "[INSTALANDO] $nombre via npm..."
    Write-Dim "vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv"
    Invoke-ForjaTool npm install -g $pkg --loglevel verbose 2>&1 | ForEach-Object { Write-Host "  $_" }
    Write-Dim "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
    return ($LASTEXITCODE -eq 0 -and (Test-NpmPkg $pkg))
}
function Ask-SN { param($pregunta)
    $r = Read-Host "  $pregunta (S/N)"
    return ($r.Trim() -match "^(?i:s|si|sí)$")
}
function Write-Separador { Write-Dim "------------------------------------------------------------" }


# Unicamente funciones; los tests las extraen por AST sin ejecutar el instalador.
function Assert-NoReparsePath { param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathRooted($Path)) { throw 'Ruta absoluta requerida.' }
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        # Get-Item detecta tambien enlaces cuyo destino no existe (Test-Path puede dar false).
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($item) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'No se permiten enlaces ni junctions en esta ruta.' }
        }
        $parent = [IO.Path]::GetDirectoryName($current)
        if ($parent -eq $current) { break }
        $current = $parent
    }
}
function Get-ForjaTree { param([string]$Root)
    Assert-NoReparsePath $Root
    $pending = New-Object 'System.Collections.Generic.Queue[string]'
    $pending.Enqueue([IO.Path]::GetFullPath($Root))
    while ($pending.Count -gt 0) {
        foreach ($item in @(Get-ChildItem -LiteralPath $pending.Dequeue() -Force -ErrorAction Stop)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Arbol con enlace o junction rechazado.' }
            $item
            if ($item.PSIsContainer) { $pending.Enqueue($item.FullName) }
        }
    }
}
function New-ForjaWorkspace { param([switch]$Installer)
    if ($Installer) {
        if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) { throw 'USERPROFILE no disponible.' }
        # Documentos evita la redireccion de AppData al ejecutar un MSI elevado.
        $base = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE 'Documents\Forja\Staging'))
    } else {
        if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { throw 'LOCALAPPDATA no disponible.' }
        $base = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Forja\Staging'))
    }
    Assert-NoReparsePath $base
    [IO.Directory]::CreateDirectory($base) | Out-Null
    $path = Join-Path $base ([guid]::NewGuid().ToString('N'))
    if (Test-Path -LiteralPath $path) { throw 'Colision de espacio temporal.' }
    [IO.Directory]::CreateDirectory($path) | Out-Null
    $script:ForjaWorkspaces[$path] = $base
    return $path
}
function Remove-ForjaWorkspace { param([string]$Path)
    if (-not $script:ForjaWorkspaces.ContainsKey($Path)) { throw 'No es un temporal creado por esta ejecucion.' }
    $full = [IO.Path]::GetFullPath($Path)
    $base = $script:ForjaWorkspaces[$Path]
    if ([IO.Path]::GetDirectoryName($full) -ne $base -or [IO.Path]::GetFileName($full) -notmatch '^[0-9a-f]{32}$') {
        throw 'Temporal fuera de la raiz esperada.'
    }
    # Validar el arbol entero ANTES del borrado; no seguir enlaces durante validacion.
    $null = @(Get-ForjaTree $full)
    Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop
    $script:ForjaWorkspaces.Remove($Path)
}
function Get-ReviewedSkills { param(
    [ValidateSet('https://github.com/ragustingarcia/la-forja-del-desarrollador.git', 'https://github.com/anthropics/skills.git')][string]$Repository,
    [ValidatePattern('^[0-9a-f]{40}$')][string]$Revision,
    [string]$Workspace
)
    if (-not $script:ForjaWorkspaces.ContainsKey($Workspace)) { throw 'Espacio de descarga desconocido.' }
    Assert-NoReparsePath $Workspace
    $repoPath = Join-Path $Workspace 'repo'
    if (Test-Path -LiteralPath $repoPath) { throw 'La descarga debe empezar en una ruta vacia.' }
    # Sin checkout de una rama cambiante, hooks o submodulos del repositorio remoto.
    & git -c core.hooksPath=NUL init --quiet -- $repoPath 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo iniciar la descarga.' }
    Invoke-ForjaGitTransfer @('-C',$repoPath,'-c','core.hooksPath=NUL','-c','protocol.file.allow=never','fetch','--progress','--depth=1','--no-tags','--',$Repository,$Revision) 2>&1 | ForEach-Object {Write-Host "  $_"}
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo descargar la revision fijada.' }
    & git -C $repoPath -c core.hooksPath=NUL -c core.symlinks=true checkout --quiet --detach $Revision 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo extraer la revision fijada.' }
    $head = (& git -C $repoPath rev-parse HEAD 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $head -cne $Revision) { throw 'La revision descargada no coincide.' }
    return $repoPath
}
function Install-ReviewedSkill { param([string]$Source, [string]$DestinationRoot, [string]$Name, [string]$Adapter)
    if ($Name -notmatch '^[a-z0-9][a-z0-9-]{0,63}$') { throw 'Nombre de skill invalido.' }
    if ($Adapter -and ($Adapter.Length -gt 100 -or $Adapter -match '[\r\n\x00-\x1f]')) { throw 'Nombre de adaptador invalido.' }
    $Source = [IO.Path]::GetFullPath($Source).TrimEnd('\')
    $DestinationRoot = [IO.Path]::GetFullPath($DestinationRoot).TrimEnd('\')
    Assert-NoReparsePath $Source
    Assert-NoReparsePath $DestinationRoot
    if (-not (Test-Path -LiteralPath (Join-Path $Source 'SKILL.md') -PathType Leaf)) { throw 'Falta SKILL.md.' }
    $tree = @(Get-ForjaTree $Source) # validar todo antes de copiar cualquier archivo
    $destination = Join-Path $DestinationRoot $Name
    if (Test-Path -LiteralPath $destination) { Write-Dim "$Name ya existe. Saltada."; return $false }
    # Construir fuera de ~/.claude/skills y publicar solo al terminar.
    $workspace = New-ForjaWorkspace
    $stage = Join-Path $workspace $Name
    try {
      [IO.Directory]::CreateDirectory($stage) | Out-Null
      foreach ($item in $tree) {
        $relative = $item.FullName.Substring($Source.TrimEnd('\').Length).TrimStart('\')
        $target = [IO.Path]::GetFullPath((Join-Path $stage $relative))
        if (-not $target.StartsWith($stage + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Archivo fuera de la skill.' }
        Assert-NoReparsePath $target
        if ($item.PSIsContainer) { [IO.Directory]::CreateDirectory($target) | Out-Null }
        else {
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
            [IO.File]::Copy($item.FullName, $target, $false)
        }
      }
      if ($Adapter) {
        # Evitar multiples lineas en el credito agregado.
        Add-Content -LiteralPath (Join-Path $stage 'SKILL.md') -Value "`n---`n`n> Adaptada para: $Adapter" -Encoding UTF8 -ErrorAction Stop
      }
      Assert-NoReparsePath $DestinationRoot
      [IO.Directory]::CreateDirectory($DestinationRoot) | Out-Null
      [IO.Directory]::Move($stage, $destination) # falla si ya existe; no mezcla ni pisa
    } finally {
      Remove-ForjaWorkspace $workspace
    }
    return $true
}
function Get-WingetUpdateState { param([string]$Id)
    $info = Get-WingetPackageInfo $Id
    if ($info.State -eq 'absent') { return 'missing' }
    if ($info.State -ne 'installed') { return 'error' }
    if ($info.Available) { return 'update' }
    return 'aldia'
}
function Remove-ForjaClaudeNpm {
    try {
        Invoke-ForjaTool npm uninstall -g '@anthropic-ai/claude-code' 2>&1 | ForEach-Object { Write-Host "  $_" }
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Claude Code/npm: desinstalacion fallida (codigo $LASTEXITCODE). Se continua."
            return 'error'
        }
        Write-OK 'Desinstalador npm completado. Se conserva la instalacion nativa.'
        return 'ok'
    } catch {
        Write-Warn "Claude Code/npm: no se pudo iniciar la desinstalacion ($($_.Exception.GetType().Name)). Se continua."
        return 'error'
    }
}
function Test-SnykAuth {
    # No consultar config get api: devuelve el secreto y no contempla OAuth.
    $null = Invoke-ForjaTool snyk whoami --experimental 2>&1
    return ($LASTEXITCODE -eq 0)
}


function Test-NpmRuntime { param([string]$Package,[string]$Version)
    $commands=@{ 'netlify-cli'='netlify'; 'vercel'='vercel'; 'snyk'='snyk'; 'supabase'='supabase'; '@anthropic-ai/claude-code'='claude'; 'pnpm'='pnpm'; '@openai/codex'='codex'; '@google/gemini-cli'='gemini'; 'neon'='neon'; 'resend-cli'='resend' }
    if (-not $commands.ContainsKey($Package)) { return $true }
    $output=Invoke-ForjaTool $commands[$Package] --version 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { return $false }
    return ($output -match ('(?<![0-9.])'+[regex]::Escape($Version)+'(?![0-9.])'))
}
function Test-MongoshBusy {
    return (@(Get-Process -Name mongosh -ErrorAction SilentlyContinue).Count -gt 0)
}
function Get-MongoshPreviousFailure { param([string]$Version)
    try {
        $root=Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir'
        Assert-NoReparsePath $root
        if (-not (Test-Path -LiteralPath $root)) { return $null }
        $prefix="MongoDB.Shell.$Version-"
        $log=Get-ChildItem -LiteralPath $root -Filter 'MongoDB.Shell*.log' -File -ErrorAction Stop |
            Where-Object { $_.Name.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($log) {
            Assert-NoReparsePath $log.FullName
            if ((Get-Content -LiteralPath $log.FullName -Raw -ErrorAction Stop) -match '(?i)Error 1304') { return $log.FullName }
        }
    } catch { Write-Dim 'No se pudo consultar el ultimo log de mongosh.' }
    return $null
}

function Get-MongoshRepairPackage { param([string]$Version)
    # Version y huella verificadas contra el manifiesto oficial de WinGet.
    # Una version futura requiere una nueva revision del catalogo de reparacion.
    if ($Version -ne '2.14.0') { return $null }
    return [pscustomobject]@{
        Version='2.14.0'
        Uri='https://downloads.mongodb.com/compass/mongosh-2.14.0-x64.msi'
        Sha256='0C433D1C06D0A8377997DA39775C537B0C9A4AD639DCDEA7EDF8B594872516C1'
    }
}
function Test-ForjaRepairAccount {
    # WindowsIdentity.Groups omite grupos deny-only en algunos tokens UAC.
    # whoami conserva esos SID; no depende del nombre traducido del grupo.
    try {
        $whoami=Join-Path ([Environment]::SystemDirectory) 'whoami.exe'
        $groups=& $whoami /groups /fo csv /nh 2>$null | Out-String
        if ($LASTEXITCODE -ne 0) { return $false }
        return (Test-ForjaAdminGroupList $groups)
    } catch { return $false }
}
function Test-ForjaAdminGroupList { param([string]$Csv)
    $rows=$Csv | ConvertFrom-Csv -Header Name,Type,Sid,Attributes -ErrorAction Stop
    return (@($rows | Where-Object { $_.Sid -eq 'S-1-5-32-544' }).Count -gt 0)
}
function Save-ForjaRepairPackage { param([string]$Uri,[string]$Destination)
    if ($Uri -ne 'https://downloads.mongodb.com/compass/mongosh-2.14.0-x64.msi') { throw 'Origen de reparacion no permitido.' }
    Save-ForjaDownload $Uri $Destination 'MongoDB Shell' -NoRedirect
}
function Test-MongoshRuntime { param([string]$Version)
    $command=Get-Command mongosh.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { return $false }
    $output=& $command.Source --norc --version 2>&1 | Out-String
    return ($LASTEXITCODE -eq 0 -and $output.Trim() -eq $Version)
}
function Invoke-MongoshRepair { param([string]$Version)
    $package=Get-MongoshRepairPackage $Version
    if (-not $package) { Write-Warn 'Esta version no tiene un MSI de reparacion revisado. Se deja pendiente.'; return 'pendiente' }
    if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
        Write-Warn 'El MSI revisado es para Windows x64. Se deja pendiente.'; return 'pendiente'
    }
    if (-not (Test-ForjaRepairAccount)) { Write-Warn 'La reparacion requiere UAC de la misma cuenta administradora. Se deja pendiente.'; return 'pendiente' }
    if (Test-MongoshBusy) { Write-Warn 'Cerra mongosh antes de reparar.'; return 'pendiente' }
    $workspace=$null; $stream=$null; $verified=$false; $trusted=$false
    try {
        $workspace=New-ForjaWorkspace -Installer
        $msi=Join-Path $workspace 'mongosh-2.14.0-x64.msi'
        $log=Join-Path $workspace 'repair.log'
        Write-Info 'Descargando el MSI oficial de MongoDB Shell para verificarlo...'
        Save-ForjaRepairPackage $package.Uri $msi
        Assert-NoReparsePath $msi
        # Mantener el archivo bloqueado contra escritura/reemplazo desde el hash
        # hasta que termine Windows Installer, inclusive durante el dialogo UAC.
        $stream=[IO.File]::Open($msi,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $hash=(Get-FileHash -InputStream $stream -Algorithm SHA256 -ErrorAction Stop).Hash
        if ($hash -cne $package.Sha256) { throw 'La huella SHA-256 no coincide. No se ejecuta el MSI.' }
        $signature=Get-AuthenticodeSignature -LiteralPath $msi -ErrorAction Stop
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(?i)\bMongoDB\b') {
            throw 'No se pudo validar la firma de MongoDB. No se ejecuta el MSI.'
        }
        $trusted=$true
        $installer=Join-Path ([Environment]::SystemDirectory) 'msiexec.exe'
        Write-Info "MSI $Version verificado. UAC eleva solo Windows Installer; la Forja sigue sin elevar."
        $arguments=@('/i',('"'+$msi+'"'),'/passive','/norestart','/L*v',('"'+$log+'"'))
        $process=Start-Process -FilePath $installer -ArgumentList $arguments -Verb RunAs -Wait -PassThru -ErrorAction Stop
        if ($process.ExitCode -eq 3010) { Write-Warn 'MSI completado; requiere reiniciar y verificar. No se reinicia automaticamente.'; return 'pendiente' }
        if ($process.ExitCode -ne 0) { Write-Warn "La reparacion MSI fallo con codigo $($process.ExitCode). Log: $log"; return 'error' }
        $script:ForjaWingetInventory=$null
        $after=Get-WingetPackageInfo 'MongoDB.Shell'
        if ($after.State -ne 'installed' -or $after.Version -ne $Version) {
            Write-Warn "MSI completado pero falta confirmar la version $Version en WinGet. Log: $log"; return 'pendiente'
        }
        Write-Info 'Verificando mongosh sin cargar scripts de inicio ni conectar a una base...'
        if (-not (Test-MongoshRuntime $Version)) { Write-Warn 'La version de mongosh no se pudo confirmar en esta terminal. Se deja pendiente.'; return 'pendiente' }
        $verified=$true
        Write-OK "mongosh reparado y version instalada confirmada: $Version."
        return 'ok'
    } catch [ComponentModel.Win32Exception] {
        if ($_.Exception.NativeErrorCode -eq 1223) { Write-Warn 'Reparacion cancelada en UAC. Se deja pendiente.'; return 'pendiente' }
        Write-Warn 'No se pudo iniciar Windows Installer. La reparacion queda pendiente.'; return 'pendiente'
    } catch { Write-Warn "Reparacion de mongosh: $($_.Exception.Message)"; return 'error' }
    finally {
        if ($stream) { $stream.Dispose() }
        if ($workspace) {
            if ($verified -or -not $trusted) {
                try { Remove-ForjaWorkspace $workspace } catch { Write-Dim "Temporal retenido: $workspace" }
            } else { Write-Dim "Archivos de diagnostico conservados: $workspace" }
        }
    }
}

function Get-InstallerFailureDetail { param([string]$Output)
    $detail=''
    if ($Output -match '(?i)exit code:\s*(\d+)') { $detail="Instalador: codigo $($Matches[1])." }
    # Leer exclusivamente logs MSI de WinGet bajo su directorio oficial.
    if ($Output -match '(?im)Installer log is available at:\s*([^\r\n]+\.log)\s*$') {
        $log=$Matches[1].Trim()
        $base=Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir'
        try {
            $full=[IO.Path]::GetFullPath($log)
            if ($full.StartsWith([IO.Path]::GetFullPath($base)+'\',[StringComparison]::OrdinalIgnoreCase)) {
                Assert-NoReparsePath $full
                if (Test-Path -LiteralPath $full -PathType Leaf) {
                    $text=Get-Content -LiteralPath $full -Raw -ErrorAction Stop
                    if ($text -match '(?i)Error 1304') { $detail+=' MSI 1304: no se pudo escribir un archivo de la instalacion. Cerra mongosh y revisa el instalador; no se cambian permisos automaticamente.' }
                    $detail+=" Log: $full"
                }
            }
        } catch { $detail+=' No se pudo leer el log MSI.' }
    }
    return $detail.Trim()
}
function Invoke-ForjaPython { param([string]$Executable)
    $pythonArguments=$args
    $ErrorActionPreference='Continue'
    if($pythonArguments.Count -ge 3 -and $pythonArguments[0] -eq '-m' -and $pythonArguments[1] -eq 'pip' -and $pythonArguments[2] -eq 'install'){
        $result=Invoke-ForjaPackageProcess $Executable $pythonArguments 'Librerias Python'
        $global:LASTEXITCODE=$result.ExitCode
        foreach($line in $result.Output){Write-Output $line}
        return
    }
    try { & $Executable @pythonArguments 2>&1 | ForEach-Object { $_.ToString() }; $code=$LASTEXITCODE }
    catch { Write-Warn "No se pudo ejecutar Python ($($_.Exception.GetType().Name))."; $code=-1 }
    $global:LASTEXITCODE=$code
}
function Invoke-ForjaPythonLibraries { param([switch]$Update,[switch]$CheckShared,[ValidateSet('base','web-vision')][string]$Profile='base')
    $result=[pscustomobject]@{ State='error'; SharedConflict=$false; Environment=$null }
    $base=Get-Command python.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $base) { Write-Warn 'Python no disponible.'; $result.State='saltado'; return $result }
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { Write-Warn 'LOCALAPPDATA no disponible.'; return $result }
    $venvName='venv';if($Profile -eq 'web-vision'){$venvName='web-vision'}
    $expectedVenv=Join-Path $env:LOCALAPPDATA ('Forja\Python\'+$venvName)
    if ($CheckShared -or ($Profile -eq 'base' -and -not (Test-Path -LiteralPath $expectedVenv))) {
        $shared=Invoke-ForjaPython $base.Source -m pip check 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            $result.SharedConflict=$true
            Write-Warn 'El Python compartido tiene dependencias incompatibles o no pudo verificarse. La Forja no lo modifica.'
            $shared.Trim() -split '\r?\n' | Select-Object -First 8 | ForEach-Object { Write-Dim $_ }
        }
    }
    try {
        if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { throw 'LOCALAPPDATA no disponible' }
        $venv=$expectedVenv
        $result.Environment=$venv
        Assert-NoReparsePath $venv
        $python=Join-Path $venv 'Scripts\python.exe'
        $config=Join-Path $venv 'pyvenv.cfg'
        if (-not (Test-Path -LiteralPath $venv)) {
            Write-Info "Las librerias se instalan en un entorno aislado: $venv"
            if (-not (Ask-SN 'Crear el entorno Python de la Forja sin modificar el compartido?')) { $result.State='saltado'; return $result }
            Invoke-ForjaPython $base.Source -m venv $venv 2>&1 | ForEach-Object { Write-Host "  $_" }
            if ($LASTEXITCODE -ne 0) { throw 'No se pudo crear el entorno' }
        }
        Assert-NoReparsePath $python
        if (-not (Test-Path -LiteralPath $python -PathType Leaf) -or -not (Test-Path -LiteralPath $config -PathType Leaf)) { throw 'El entorno esta incompleto; no se reemplaza automaticamente' }
        $configuration=Get-Content -LiteralPath $config -Raw -ErrorAction Stop
        if ($configuration -notmatch '(?im)^include-system-site-packages\s*=\s*false\s*$') { throw 'El entorno no esta aislado del Python compartido' }
        $before=Invoke-ForjaPython $python -m pip list --format=json --disable-pip-version-check 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo inventariar el entorno' }
        $null=$before | ConvertFrom-Json -ErrorAction Stop
        $installArguments=@('-m','pip','install','--disable-pip-version-check')
        if ($Update) { $installArguments+='--upgrade' }
        $packages=@('fastapi','uvicorn[standard]','python-multipart','pdfplumber','requests')
        $packageNames=@('fastapi','uvicorn','python-multipart','pdfplumber','requests')
        $imports='import fastapi, uvicorn, multipart, pdfplumber, requests'
        if($Profile -eq 'web-vision'){$packages=@('Flask','opencv-python','numpy');$packageNames=@('Flask','opencv-python','numpy');$imports='import flask, cv2, numpy'}
        $installArguments+=$packages
        Invoke-ForjaPython $python @installArguments 2>&1 | ForEach-Object { Write-Host "  $_" }
        if ($LASTEXITCODE -ne 0) { throw 'pip no pudo instalar las librerias' }
        $check=Invoke-ForjaPython $python -m pip check 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { Write-Warn $check.Trim(); throw 'Las dependencias del entorno no son compatibles' }
        $null=Invoke-ForjaPython $python -m pip show @packageNames 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'Faltan librerias requeridas' }
        $after=Invoke-ForjaPython $python -m pip list --format=json --disable-pip-version-check 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo verificar la version instalada' }
        $null=$after | ConvertFrom-Json -ErrorAction Stop
        $imports=Invoke-ForjaPython $python -c $imports 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { Write-Warn $imports.Trim(); throw 'Las librerias no se pueden cargar en ese interprete' }
        $result.State='ok'
        if ($before.Trim() -eq $after.Trim()) { $result.State='aldia' }
        Write-OK "Librerias Python verificadas en el entorno de la Forja: $python"
        Write-Dim "Para usarlas, ejecuta ese Python directamente; no hace falta activar scripts de PowerShell."
    } catch { Write-Warn "Librerias Python: $($_.Exception.Message)."; $result.State='error' }
    return $result
}

function Invoke-WingetUpdate { param($id, $nombre)
    $info = Get-WingetPackageInfo $id
    if ($info.State -eq 'absent') { Write-Dim "$nombre no figura en el inventario de WinGet. Saltado."; return 'saltado' }
    if ($info.State -ne 'installed') { Write-Warn "${nombre}: $($info.Detail)"; return 'error' }
    if (-not $info.Available) { Write-OK "$nombre ya esta al dia (instalada: $($info.Version))."; return 'aldia' }
    Write-Info "$nombre : instalada $($info.Version) -> disponible $($info.Available)"
    if ($id -eq 'MongoDB.Shell' -and (Test-MongoshBusy)) {
        Write-Warn 'mongosh esta abierto. Cerra sus sesiones y volve a actualizarlo; no se cierran procesos automaticamente.'
        return 'pendiente'
    }
    if ($id -eq 'MongoDB.Shell') {
        $previousFailure=Get-MongoshPreviousFailure $info.Available
        if ($previousFailure) {
            Write-Warn "El ultimo intento de esta version fallo con MSI 1304 al escribir archivos. Log: $previousFailure"
            Write-Info 'La reparacion usa solo el MSI oficial con SHA-256 y firma verificados. Puede pedir UAC para ese paquete.'
            if (Ask-SN 'Reparar mongosh con Windows Installer y permisos para este paso?') { return (Invoke-MongoshRepair $info.Available) }
            return 'pendiente'
        }
    }
    $installerOutput=New-Object 'System.Collections.Generic.List[string]'
    try {
        Invoke-ForjaWingetOperation @('upgrade','--id',$id,'--exact','--source','winget','--accept-package-agreements','--accept-source-agreements') $nombre 2>&1 | ForEach-Object { $installerOutput.Add($_.ToString()); Write-Host "  $_" }
        $codigo = $LASTEXITCODE
    } catch { Write-Warn "${nombre}: no se pudo iniciar la actualizacion."; return 'error' }
    if ($codigo -eq -1978335189) { Write-OK "$nombre sin actualizacion aplicable (instalada: $($info.Version))."; return 'aldia' }
    if ($codigo -eq 0) {
        $script:ForjaWingetInventory = $null
        $after = Get-WingetPackageInfo $id
        if ($after.State -eq 'installed' -and $after.Version -eq $info.Available) {
            Write-OK "$nombre actualizado. Version instalada: $($after.Version)."; return 'ok'
        }
        Write-Warn "$nombre : el instalador termino, pero no se pudo confirmar la version esperada. Volve a verificar."
        return 'error'
    }
    if($codigo -eq -1978334956){
        if($id -eq 'Google.AndroidStudio'){Write-Warn 'Android Studio requiere su actualizador: abri Help > Check for Updates.'}
        elseif($id -eq 'CondaForge.Miniforge3'){Write-Warn 'Miniforge requiere su gestor original. Revisa Conda en su terminal; no se migran tus entornos.'}
        else {Write-Warn 'Este programa requiere el actualizador de su proveedor.'}
        Write-Info 'Se deja pendiente; no se repite el instalador ni se cambia el gestor.'
        return 'pendiente'
    }
    $detail=Get-InstallerFailureDetail ($installerOutput -join "`n")
    Write-Warn "${nombre}: fallo WinGet $codigo. $detail"
    if ($id -eq 'MongoDB.Shell' -and $detail -match 'MSI 1304') {
        if (Ask-SN 'Intentar reparacion con el MSI oficial verificado y UAC solo para este paquete?') { return (Invoke-MongoshRepair $info.Available) }
        return 'pendiente'
    }
    return 'error'
}

# Actualiza un paquete npm global solo si la version instalada
# difiere de la ultima publicada (evita reinstalaciones de minutos)
function Invoke-NpmUpdate { param($pkg, $nombre)
    $vLocal = $null
    $lista = (Invoke-ForjaTool npm list -g $pkg --depth=0 2>&1) | Out-String
    if ($LASTEXITCODE -ne 0) { Write-Warn "${nombre}: fallo la consulta local de npm."; return 'error' }
    if ($lista -match ([regex]::Escape($pkg) + "@(\S+)")) { $vLocal = $Matches[1] }
    $vUltima = ((Invoke-ForjaTool npm view $pkg version 2>&1) | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $vUltima -notmatch '^\d+\.\d+\.\d+([+-][0-9A-Za-z.-]+)?$') {
        Write-Warn "${nombre}: no se pudo consultar una version valida del registro."; return 'error'
    }
    if ($vLocal -and $vUltima -and $vLocal -eq $vUltima) {
        if (-not (Test-NpmRuntime $pkg $vLocal)) { Write-Warn "${nombre}: la version figura instalada pero el comando no responde correctamente."; return 'error' }
        Write-OK "$nombre ya esta al dia ($vLocal)."
        return "aldia"
    }
    Write-Dim "vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv"
    $npmOutput=New-Object 'System.Collections.Generic.List[string]'
    Invoke-ForjaTool npm install -g "$pkg@$vUltima" 2>&1 | ForEach-Object { $npmOutput.Add($_.ToString()); Write-Host "  $_" }
    $codigo = $LASTEXITCODE
    Write-Dim "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
    if ($codigo -eq 0) {
        $after = (Invoke-ForjaTool npm list -g $pkg --depth=0 2>&1) | Out-String
        if ($LASTEXITCODE -eq 0 -and $after -match ([regex]::Escape($pkg) + '@(\S+)') -and $Matches[1] -eq $vUltima) {
            if (-not (Test-NpmRuntime $pkg $vUltima)) { Write-Warn "${nombre}: paquete actualizado pero la CLI no responde con esa version."; return 'error' }
            Write-OK "$nombre actualizado y comando verificado. Version instalada: $vUltima."
            if (($npmOutput -join "`n") -match '(?im)^npm warn') {
                Write-Warn 'npm emitio avisos del proveedor. La CLI responde; revisa esos avisos. No se cambia la politica de scripts.'
                return 'ok-aviso'
            }
            return 'ok'
        }
        Write-Warn "${nombre}: npm termino pero no se confirmo la version esperada."; return 'error'
    }
    Write-Warn "${nombre}: error al actualizar."
    return "error"
}
function Add-UpdResultado { param($r)
    switch ($r) {
        "ok"    { $script:updOK++ }
        "aldia" { $script:updAlDia++ }
        "error" { $script:updError++ }
        "saltado" { $script:updSaltado++ }
        "pendiente" { $script:updPendiente++ }
        "ok-aviso" { $script:updOK++; $script:updAvisos++ }
        "aviso" { $script:updAvisos++ }
    }
}


function Get-ForjaStackCatalog {
    $json=@'
[
  {
    "Id": "cursor",
    "Group": "Editores y agentes",
    "Name": "Cursor",
    "Method": "winget",
    "Package": "Anysphere.Cursor",
    "Command": "cursor",
    "Docs": "https://cursor.com/downloads",
    "Description": "Editor de codigo con IA para escribir, entender y corregir proyectos."
  },
  {
    "Id": "antigravity",
    "Group": "Editores y agentes",
    "Name": "Antigravity App",
    "Method": "winget",
    "Package": "Google.Antigravity",
    "Command": "antigravity",
    "Docs": "https://antigravity.google/download",
    "Description": "Aplicacion para organizar y supervisar tareas de agentes de IA."
  },
  {
    "Id": "antigravity-ide",
    "Group": "Editores y agentes",
    "Name": "Antigravity IDE",
    "Method": "winget",
    "Package": "Google.AntigravityIDE",
    "Command": "antigravity-ide",
    "Docs": "https://antigravity.google/download",
    "Description": "Editor de codigo de Google con agentes de IA integrados."
  },
  {
    "Id": "gemini-app",
    "Group": "Editores y agentes",
    "Name": "Gemini Desktop",
    "Method": "winget",
    "Package": "Google.GeminiDesktop",
    "Command": "",
    "Docs": "https://gemini.google/",
    "Description": "Aplicacion de Gemini para conversar con la IA y trabajar con archivos."
  },
  {
    "Id": "grok-bot",
    "Group": "Editores y agentes",
    "Name": "Grok Bot",
    "Method": "winget",
    "Package": "xAI.GrokBot",
    "Command": "",
    "Docs": "https://docs.x.ai/grok-bot/get-started",
    "Description": "Asistente que realiza tareas usando aplicaciones y servicios conectados."
  },
  {
    "Id": "codex-app",
    "Group": "Editores y agentes",
    "Name": "App ChatGPT / Codex",
    "Method": "store",
    "Package": "9PLM9XGG6VKS",
    "Appx": "OpenAI.Codex",
    "Command": "",
    "Docs": "https://learn.chatgpt.com/docs/app/windows",
    "Description": "Interfaz visual de ChatGPT/Codex para trabajar con agentes y proyectos."
  },
  {
    "Id": "codex-cli",
    "Group": "CLI de agentes",
    "Name": "Codex CLI",
    "Method": "npm",
    "Package": "@openai/codex",
    "Command": "codex",
    "Docs": "https://learn.chatgpt.com/docs/codex/cli",
    "Description": "Agente de OpenAI para escribir y revisar codigo desde una terminal."
  },
  {
    "Id": "agy-cli",
    "Group": "CLI de agentes",
    "Name": "Antigravity CLI (agy)",
    "Method": "winget",
    "Package": "Google.AntigravityCLI",
    "Command": "agy",
    "Docs": "https://antigravity.google/docs/getting-started",
    "Description": "Agente de Google para programar y ejecutar tareas desde la terminal."
  },
  {
    "Id": "cursor-cli",
    "Group": "CLI de agentes",
    "Name": "Cursor Agent CLI (Windows x64)",
    "Method": "archive",
    "Command": "agent",
    "Version": "2026.10.22-27dcf5f",
    "Uri": "https://downloads.cursor.com/lab/2026.10.22-27dcf5f/windows/x64/agent-cli-package.zip",
    "Sha256": "864A8F6A22F8C5EBEDEF8E0CEBA529EAE9A59B3D7F6FCCB75E43E0F5EFC3C147",
    "Executable": "dist-package/node.exe",
    "Script": "dist-package/index.js",
    "Launcher": "forja-agent.cmd",
    "Docs": "https://prod.cursor.com/docs/cli/installation",
    "Description": "Agente de Cursor para trabajar en un proyecto desde la terminal."
  },
  {
    "Id": "gemini-cli",
    "Group": "Gemini CLI (compatibilidad)",
    "Name": "Gemini CLI (cuentas compatibles)",
    "Method": "npm",
    "Package": "@google/gemini-cli",
    "Command": "gemini",
    "Notice": "Google retiro el acceso de cuentas personales a Gemini CLI. Preferi agy; revisa tu tipo de cuenta antes de instalar Gemini CLI.",
    "Docs": "https://developers.google.com/gemini-code-assist/docs/deprecations/code-assist-individuals",
    "Description": "Cliente de Gemini en terminal para cuentas compatibles; revisar su disponibilidad."
  },
  {
    "Id": "neon-cli",
    "Group": "Servicios cloud",
    "Name": "Neon CLI",
    "Method": "npm",
    "Package": "neon",
    "Command": "neon",
    "Docs": "https://neon.com/docs/cli/install",
    "Description": "Administra tus bases PostgreSQL alojadas en Neon."
  },
  {
    "Id": "resend-cli",
    "Group": "Servicios cloud",
    "Name": "Resend CLI",
    "Method": "npm",
    "Package": "resend-cli",
    "Command": "resend",
    "Docs": "https://resend.com/docs/cli",
    "Description": "Administra el servicio de correo de Resend desde la terminal."
  },
  {
    "Id": "render-cli",
    "Group": "Servicios cloud",
    "Name": "Render CLI (Windows x64)",
    "Method": "archive",
    "Command": "render",
    "Version": "2.33.0",
    "Uri": "https://github.com/render-oss/cli/releases/download/v2.33.0/cli_2.33.0_windows_amd64.zip",
    "Sha256": "7A16D74C9F18AC9A1383D9A3A43C3C07B4374DBDDB183F49A05810C130B5CA16",
    "Executable": "render.exe",
    "Script": "",
    "Launcher": "forja-render.cmd",
    "Docs": "https://render.com/docs/cli",
    "Description": "Administra aplicaciones y servicios alojados en Render."
  },
  {
    "Id": "cloudflared",
    "Group": "Servicios cloud",
    "Name": "Cloudflare Tunnel CLI",
    "Method": "winget",
    "Package": "Cloudflare.cloudflared",
    "Command": "cloudflared",
    "Docs": "https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/",
    "Description": "Conecta un servicio de tu PC con Cloudflare mediante un tunel."
  },
  {
    "Id": "wrangler",
    "Group": "Servicios cloud",
    "Name": "Cloudflare Wrangler (por proyecto)",
    "Method": "project-npm",
    "Package": "wrangler",
    "Command": "wrangler",
    "Docs": "https://developers.cloudflare.com/workers/wrangler/install-and-update/",
    "Description": "Desarrolla y publica Workers o Pages de Cloudflare desde un proyecto."
  },
  {
    "Id": "postgresql",
    "Group": "Bases de datos locales",
    "Name": "PostgreSQL 17 (servidor y cliente)",
    "Method": "winget",
    "Package": "PostgreSQL.PostgreSQL.17",
    "Command": "psql",
    "Docs": "https://www.postgresql.org/download/windows/",
    "Description": "Servidor de base de datos para guardar y consultar informacion estructurada."
  },
  {
    "Id": "rust",
    "Group": "Compilacion y escritorio",
    "Name": "Rust / Cargo (rustup)",
    "Method": "winget",
    "Package": "Rustlang.Rustup",
    "Command": "rustup",
    "Notice": "WinGet gestiona rustup. Los toolchains se actualizan por separado con rustup update, segun cada proyecto.",
    "Docs": "https://www.rust-lang.org/tools/install",
    "Description": "Instala y administra las herramientas para compilar programas Rust."
  },
  {
    "Id": "buildtools",
    "Group": "Compilacion y escritorio",
    "Name": "Visual Studio Build Tools 2022",
    "Method": "winget",
    "Package": "Microsoft.VisualStudio.2022.BuildTools",
    "Command": "",
    "Notice": "El instalador permite elegir workloads. Revisa C++ y Windows SDK para Tauri o extensiones nativas; no se marcan como instalados solo por tener Build Tools.",
    "Docs": "https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022",
    "Description": "Compiladores de Windows que necesitan algunas apps y librerias nativas."
  },
  {
    "Id": "dotnet",
    "Group": "Compilacion y escritorio",
    "Name": ".NET SDK 10",
    "Method": "winget",
    "Package": "Microsoft.DotNet.SDK.10",
    "Command": "dotnet",
    "Docs": "https://dotnet.microsoft.com/download",
    "Description": "Herramientas para crear y compilar aplicaciones de la plataforma .NET."
  },
  {
    "Id": "inno",
    "Group": "Compilacion y escritorio",
    "Name": "Inno Setup",
    "Method": "winget",
    "Package": "JRSoftware.InnoSetup",
    "Command": "ISCC",
    "Docs": "https://jrsoftware.org/isinfo.php",
    "Description": "Crea instaladores de Windows para distribuir tus propias aplicaciones."
  },
  {
    "Id": "android",
    "Group": "Android y Java",
    "Name": "Android Studio",
    "Method": "winget",
    "Package": "Google.AndroidStudio",
    "Command": "",
    "Notice": "SDK, emuladores y plataformas Android se eligen despues desde SDK Manager.",
    "Docs": "https://developer.android.com/studio",
    "Description": "Entorno para crear, probar y compilar aplicaciones Android."
  },
  {
    "Id": "jdk17",
    "Group": "Android y Java",
    "Name": "Temurin JDK 17",
    "Method": "winget",
    "Package": "EclipseAdoptium.Temurin.17.JDK",
    "Command": "java",
    "Docs": "https://adoptium.net/installation/",
    "Scoop": "temurin17-jdk",
    "Description": "Herramientas Java 17 que usan determinados proyectos y versiones de Gradle."
  },
  {
    "Id": "jdk21",
    "Group": "Android y Java",
    "Name": "Temurin JDK 21",
    "Method": "winget",
    "Package": "EclipseAdoptium.Temurin.21.JDK",
    "Command": "java",
    "Notice": "JDK 17 y 21 pueden convivir. JAVA_HOME y el JDK de Gradle se eligen por proyecto.",
    "Docs": "https://adoptium.net/installation/",
    "Scoop": "temurin21-jdk",
    "Description": "Herramientas Java 21 para los proyectos que necesitan esa version."
  },
  {
    "Id": "miniforge",
    "Group": "Python cientifico",
    "Name": "Miniforge3",
    "Method": "winget",
    "Package": "CondaForge.Miniforge3",
    "Command": "conda",
    "Notice": "Forja gestiona el instalador de Miniforge, no modifica ni migra sus entornos Conda.",
    "Docs": "https://github.com/conda-forge/miniforge",
    "Description": "Organiza entornos Python y paquetes cientificos con Conda."
  },
  {
    "Id": "python-web-vision",
    "Group": "Python cientifico",
    "Name": "Flask + OpenCV + NumPy (venv aislado)",
    "Method": "python-venv",
    "Command": "",
    "Docs": "https://docs.python.org/3/library/venv.html",
    "Description": "Entorno separado para crear APIs Flask y procesar imagenes con OpenCV."
  },
  {
    "Id": "supabase-native",
    "Group": "Base",
    "Core": true,
    "Name": "Supabase CLI (Windows x64)",
    "Method": "archive",
    "Command": "supabase",
    "Version": "2.122.0",
    "Uri": "https://github.com/supabase/cli/releases/download/v2.122.0/supabase_2.122.0_windows_amd64.zip",
    "Sha256": "60031FD5BF050FC12A0C6AEF68997600D143870F944BF13109C7765DCA329AF8",
    "Executable": "supabase.exe",
    "Script": "",
    "Launcher": "forja-supabase.cmd",
    "Docs": "https://supabase.com/docs/guides/local-development/cli/getting-started",
    "Description": "Cliente para trabajar con bases, autenticacion y funciones de Supabase."
  }
]
'@
    $entries=ConvertFrom-Json -InputObject $json
    foreach($entry in $entries){Write-Output $entry}
}
function Invoke-ForjaCommand { param([string]$Path,[string[]]$Arguments)
    $ErrorActionPreference='Continue'
    try { & $Path @Arguments 2>&1 | ForEach-Object { $_.ToString() }; $code=$LASTEXITCODE }
    catch { Write-Warn "No se pudo ejecutar $Path ($($_.Exception.GetType().Name))."; $code=-1 }
    $global:LASTEXITCODE=$code
}
function Get-ForjaStackCommand { param([string]$Name)
    if ($Name -notmatch '^[a-zA-Z0-9-]+$') { return $null }
    foreach($extension in @('.exe','.cmd')) {
        $command=Get-Command ($Name+$extension) -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { return $command.Source }
    }
    foreach($relative in @(".local\bin\$Name.exe",".local\bin\$Name.cmd")) {
        $path=Join-Path $env:USERPROFILE $relative
        if(Test-Path -LiteralPath $path -PathType Leaf){return $path}
    }
    if($Name -eq 'agent'){
        $path=Join-Path $env:LOCALAPPDATA 'cursor-agent\agent.cmd'
        if(Test-Path -LiteralPath $path -PathType Leaf){return $path}
    }
    return $null
}
function Get-ForjaManagedRoot { param($Tool)
    if ($Tool.Id -notmatch '^[a-z0-9-]+$' -or $Tool.Version -notmatch '^[0-9][0-9.a-z-]+$') { throw 'Identidad de herramienta invalida.' }
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { throw 'LOCALAPPDATA no disponible.' }
    $root=Join-Path $env:LOCALAPPDATA ("Forja\Tools\"+$Tool.Id+'\'+$Tool.Version)
    Assert-NoReparsePath $root
    return $root
}
function Save-ForjaToolArchive { param($Tool,[string]$Destination)
    $approved=@(Get-ForjaStackCatalog | Where-Object { $_.Method -eq 'archive' -and $_.Id -eq $Tool.Id -and $_.Uri -ceq $Tool.Uri -and $_.Sha256 -ceq $Tool.Sha256 })
    if ($approved.Count -ne 1) { throw 'Paquete fuera del catalogo revisado.' }
    Save-ForjaDownload $Tool.Uri $Destination $Tool.Name
}
function Expand-ForjaToolArchive { param([IO.Stream]$Stream,[string]$Destination)
    Add-Type -AssemblyName System.IO.Compression
    $zip=New-Object IO.Compression.ZipArchive($Stream,[IO.Compression.ZipArchiveMode]::Read,$true)
    try {
        $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $total=[long]0
        if ($zip.Entries.Count -gt 5000) { throw 'Demasiadas entradas ZIP.' }
        # Validar TODAS las entradas antes de crear archivos o ejecutar el paquete.
        foreach($entry in $zip.Entries){
            $name=$entry.FullName.Replace('\','/')
            $parts=$name.TrimEnd('/') -split '/'
            if (-not $name -or $name.StartsWith('/') -or $parts -contains '..' -or $parts -contains '.' -or $parts -contains '' -or $name -match '[:*?"<>|\x00-\x1f]' -or @($parts | Where-Object {$_ -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$'}).Count -or @($parts | Where-Object {$_ -match '[. ]$'}).Count) { throw 'Ruta ZIP insegura.' }
            if (-not $seen.Add($name.TrimEnd('/'))) { throw 'Ruta ZIP duplicada.' }
            $attributes=[uint32]([int64]$entry.ExternalAttributes -band 0xffffffffL)
            if (($attributes -band 0x400) -ne 0 -or (($attributes -shr 16) -band 0xf000) -eq 0xa000) { throw 'Enlace ZIP rechazado.' }
            $total+=$entry.Length
            if ($total -gt 1073741824) { throw 'ZIP supera el limite de expansion.' }
        }
        foreach($entry in $zip.Entries){
            $path=Join-Path $Destination ($entry.FullName.Replace('/','\'))
            $full=[IO.Path]::GetFullPath($path)
            if (-not $full.StartsWith([IO.Path]::GetFullPath($Destination).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Escape de destino ZIP.' }
            Assert-NoReparsePath $full
            if($entry.FullName.EndsWith('/')){[IO.Directory]::CreateDirectory($full) | Out-Null;continue}
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($full)) | Out-Null
            $entryStream=$entry.Open();$output=[IO.File]::Open($full,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try {$entryStream.CopyTo($output)} finally {$entryStream.Dispose();$output.Dispose()}
        }
    } finally {$zip.Dispose()}
}
function Test-ForjaManagedRuntime { param($Tool,[string]$Root)
    $exe=Join-Path $Root $Tool.Executable
    $arguments=@('--version')
    if($Tool.Script){$arguments=@((Join-Path $Root $Tool.Script),'--version')}
    Assert-NoReparsePath $exe
    if(-not (Test-Path -LiteralPath $exe -PathType Leaf)){return $false}
    if($Tool.Script){Assert-NoReparsePath $arguments[0];if(-not (Test-Path -LiteralPath $arguments[0] -PathType Leaf)){return $false}}
    $version=Invoke-ForjaCommand $exe $arguments | Out-String
    return ($LASTEXITCODE -eq 0 -and $version -match ('(?<![a-zA-Z0-9.])v?'+[regex]::Escape($Tool.Version)+'(?![a-zA-Z0-9.-])'))
}
function Invoke-ForjaArchiveTool { param($Tool,[switch]$Update)
    if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { Write-Warn 'Este paquete revisado es Windows x64.'; return 'pendiente' }
    $workspace=$null;$stream=$null
    try {
        $root=Get-ForjaManagedRoot $Tool
        if(Test-Path -LiteralPath $root){
            $receipt=Join-Path $root '.forja-tool.json'
            if (-not (Test-Path -LiteralPath $receipt -PathType Leaf)) { Write-Warn 'Directorio existente sin comprobante; no se reemplaza.';return 'pendiente' }
            Assert-NoReparsePath $receipt
            $record=Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json -ErrorAction Stop
            if ($record.Id -cne $Tool.Id -or $record.Version -cne $Tool.Version -or $record.Sha256 -cne $Tool.Sha256) { Write-Warn 'Comprobante distinto del catalogo revisado.';return 'pendiente' }
            if(-not (Test-ForjaManagedRuntime $Tool $root)){return 'error'}
            Write-OK "$($Tool.Name): version revisada $($Tool.Version)."
            Write-Dim ('Comando: '+(Join-Path $root $Tool.Launcher))
            return 'aldia'
        }
        $external=Get-ForjaStackCommand $Tool.Command
        if($external){Write-Warn "$($Tool.Name) instalado por otro medio: $external. Revisar con el actualizador del proveedor.";return 'pendiente'}
        $parent=Split-Path $root -Parent
        if($Update -and -not (Test-Path -LiteralPath $parent)){return 'saltado'}
        if($Update){
            $old=@(Get-ChildItem -LiteralPath $parent -Directory -ErrorAction Stop | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName '.forja-tool.json') -PathType Leaf })
            if(-not $old.Count){return 'saltado'}
        }
        $workspace=New-ForjaWorkspace
        $archive=Join-Path $workspace 'tool.zip';$stage=Join-Path $workspace 'payload'
        Save-ForjaToolArchive $Tool $archive
        Assert-NoReparsePath $archive
        $stream=[IO.File]::Open($archive,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        if((Get-FileHash -InputStream $stream -Algorithm SHA256).Hash -cne $Tool.Sha256){throw 'SHA-256 del paquete no coincide.'}
        $stream.Position=0
        Expand-ForjaToolArchive $stream $stage
        if(-not (Test-ForjaManagedRuntime $Tool $stage)){throw 'El paquete no confirma su version; no se publica.'}
        # Shim propio: no usa el bootstrap del proveedor ni modifica politicas.
        $relative=$Tool.Executable.Replace('/','\')
        $launch='@echo off'+"`r`n"+'setlocal DisableDelayedExpansion'+"`r`n"+'"%~dp0'+$relative+'"'
        if($Tool.Script){$launch+=' "%~dp0'+$Tool.Script.Replace('/','\')+'"'}
        $launch+=' %*'+"`r`n"+'exit /b %ERRORLEVEL%'+"`r`n"
        [IO.File]::WriteAllText((Join-Path $stage $Tool.Launcher),$launch,(New-Object Text.UTF8Encoding($false)))
        @{Id=$Tool.Id;Version=$Tool.Version;Sha256=$Tool.Sha256} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stage '.forja-tool.json') -Encoding UTF8
        Assert-NoReparsePath $root
        [IO.Directory]::CreateDirectory($parent) | Out-Null
        [IO.Directory]::Move($stage,$root)
        Write-OK "$($Tool.Name) $($Tool.Version): instalado y verificado."
        Write-Info ('Ejecuta: '+(Join-Path $root $Tool.Launcher))
        return 'ok'
    } catch {Write-Warn "$($Tool.Name): $($_.Exception.Message)";return 'error'}
    finally {if($stream){$stream.Dispose()};if($workspace){try{Remove-ForjaWorkspace $workspace}catch{Write-Dim "Temporal retenido: $workspace"}}}
}
function Invoke-ForjaCatalogNpm { param($Tool,[switch]$Update)
    if(-not (Get-ForjaToolPath npm)){Write-Warn 'npm no disponible.';return 'pendiente'}
    if(Test-NpmPkg $Tool.Package){return (Invoke-NpmUpdate $Tool.Package $Tool.Name)}
    if(Get-ForjaStackCommand $Tool.Command){Write-Warn "$($Tool.Name) usa otro instalador. No se agrega una segunda copia.";return 'pendiente'}
    if($Update){return 'saltado'}
    $version=((Invoke-ForjaTool npm view $Tool.Package version | Out-String).Trim())
    if($LASTEXITCODE -ne 0 -or $version -notmatch '^\d+\.\d+\.\d+([+-][0-9A-Za-z.-]+)?$'){return 'error'}
    Invoke-ForjaTool npm install -g ($Tool.Package+'@'+$version) 2>&1 | ForEach-Object {Write-Host "  $_"}
    if($LASTEXITCODE -ne 0){return 'error'}
    $after=Invoke-ForjaTool npm list -g $Tool.Package --depth=0 | Out-String
    if($LASTEXITCODE -ne 0 -or $after -notmatch ([regex]::Escape($Tool.Package)+'@'+[regex]::Escape($version)+'(?![0-9A-Za-z.+-])')){return 'error'}
    if(-not (Test-NpmRuntime $Tool.Package $version)){return 'error'}
    Write-OK "$($Tool.Name) $version instalada y verificada."
    return 'ok'
}
function Test-ForjaWranglerPlatform {
    return ([Environment]::OSVersion.Platform -eq 'Win32NT' -and [Environment]::OSVersion.Version.Build -ge 22000)
}
function Invoke-ForjaWranglerProject {
    if(-not (Test-ForjaWranglerPlatform)){Write-Warn 'Wrangler requiere Windows 11 o un entorno compatible del proveedor.';return 'pendiente'}
    $path=Read-Host '  Ruta absoluta del proyecto Cloudflare (ENTER = pendiente)'
    if([string]::IsNullOrWhiteSpace($path)){return 'pendiente'}
    try {
        if(-not [IO.Path]::IsPathRooted($path)){throw 'La ruta debe ser absoluta.'}
        $path=[IO.Path]::GetFullPath($path)
        Assert-NoReparsePath $path
        $manifest=Join-Path $path 'package.json'
        Assert-NoReparsePath $manifest
        if(-not (Test-Path -LiteralPath $manifest -PathType Leaf)){throw 'Falta package.json del proyecto.'}
        $null=Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json -ErrorAction Stop
        foreach($relative in @('package-lock.json','npm-shrinkwrap.json','node_modules','node_modules\wrangler','node_modules\.bin')){
            Assert-NoReparsePath (Join-Path $path $relative)
        }
        Write-Info "Proyecto: $path. npm modificara package.json, lockfile y node_modules."
        if(-not (Ask-SN 'Instalar/actualizar Wrangler como dependencia de desarrollo aqui?')){return 'pendiente'}
        $version=(Invoke-ForjaTool npm view wrangler version | Out-String).Trim()
        if($LASTEXITCODE -ne 0 -or $version -notmatch '^\d+\.\d+\.\d+$'){return 'error'}
        Invoke-ForjaTool npm install --prefix $path --save-dev ("wrangler@"+$version) 2>&1 | ForEach-Object {Write-Host "  $_"}
        if($LASTEXITCODE -ne 0){return 'error'}
        $package=Join-Path $path 'node_modules\wrangler\package.json'
        $command=Join-Path $path 'node_modules\.bin\wrangler.cmd'
        Assert-NoReparsePath $package;Assert-NoReparsePath $command
        if(-not (Test-Path -LiteralPath $package -PathType Leaf) -or -not (Test-Path -LiteralPath $command -PathType Leaf)){return 'error'}
        $installed=Get-Content -LiteralPath $package -Raw | ConvertFrom-Json
        if($installed.version -ne $version){return 'error'}
        $runtime=Invoke-ForjaCommand $command @('--version') | Out-String
        if($LASTEXITCODE -ne 0 -or $runtime -notmatch ('(?<![0-9.])'+[regex]::Escape($version)+'(?![0-9.])')){return 'error'}
        Write-OK "Wrangler $version verificado en $path."
        return 'ok'
    } catch {Write-Warn $_.Exception.Message;return 'error'}
}
function Get-ForjaStoreApp { param($Tool)
    try {
        $apps=@(Get-AppxPackage -Name $Tool.Appx -ErrorAction Stop)
        if($apps.Count){return [pscustomobject]@{State='installed';Version=$apps[0].Version.ToString()}}
        return [pscustomobject]@{State='absent';Version=$null}
    } catch {return [pscustomobject]@{State='error';Version=$null}}
}
function Get-ForjaAlternatePackage { param($Tool)
    if($Tool.Scoop -and $Tool.Scoop -match '^[a-z0-9-]+$'){
        $manifest=Join-Path $env:USERPROFILE ('scoop\apps\'+$Tool.Scoop+'\current\manifest.json')
        if(Test-Path -LiteralPath $manifest -PathType Leaf){
            $package=Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json -ErrorAction Stop
            return ('Scoop '+$Tool.Scoop+' '+$package.version)
        }
    }
    if($Tool.Id -eq 'rust'){
        $path=Get-ForjaStackCommand 'rustup'
        if($path){return ('rustup: '+$path)}
    }
    return $null
}
function Invoke-ForjaStackTool { param($Tool,[switch]$Update)
    if($Tool.Notice){Write-Warn $Tool.Notice}
    switch($Tool.Method){
        'winget' {
            $before=Get-WingetPackageInfo $Tool.Package
            if($before.State -eq 'absent'){
                $alternate=Get-ForjaAlternatePackage $Tool
                if($alternate){
                    Write-Info ('Presente por otro gestor: '+$alternate)
                    if($Update){Write-Warn 'Actualiza con su gestor original; no se agrega otra instalacion.';return 'pendiente'}
                    return 'aldia'
                }
            }
            if($Update){return (Invoke-WingetUpdate $Tool.Package $Tool.Name)}
            if($before.State -eq 'installed'){Write-OK ("Ya instalada: "+$before.Version);return 'aldia'}
            if($before.State -ne 'absent'){return 'error'}
            if(-not (Install-Winget $Tool.Package $Tool.Name)){return 'error'}
            $script:ForjaWingetInventory=$null
            $after=Get-WingetPackageInfo $Tool.Package
            if($after.State -eq 'installed'){return 'ok'}
            Write-Warn 'El instalador termino; falta confirmar el registro de la herramienta.'
            return 'pendiente'
        }
        'npm' {return (Invoke-ForjaCatalogNpm $Tool -Update:$Update)}
        'archive' {return (Invoke-ForjaArchiveTool $Tool -Update:$Update)}
        'store' {
            $before=Get-ForjaStoreApp $Tool
            if($before.State -eq 'error'){Write-Warn 'No se pudo consultar Microsoft Store.';return 'pendiente'}
            if($Update){
                if($before.State -eq 'absent'){return 'saltado'}
                Write-Info "$($Tool.Name) $($before.Version). Actualizaciones gestionadas por Microsoft Store."
                return 'saltado'
            }
            if($before.State -eq 'installed'){Write-OK "$($Tool.Name) presente: $($before.Version).";return 'aldia'}
            # ID Store tomado de la documentacion oficial, separado del ID CLI OpenAI.Codex.
            Invoke-ForjaWingetOperation @('install','--id',$Tool.Package,'--exact','--source','msstore','--disable-interactivity') $Tool.Name 2>&1 | ForEach-Object {Write-Host "  $_"}
            $code=$LASTEXITCODE;$after=Get-ForjaStoreApp $Tool
            if($code -eq 0 -and $after.State -eq 'installed'){return 'ok'}
            Write-Warn "Revisa la instalacion en Microsoft Store: $($Tool.Docs)";return 'pendiente'
        }
        'python-venv' {
            $path=Join-Path $env:LOCALAPPDATA 'Forja\Python\web-vision'
            if($Update -and -not (Test-Path -LiteralPath $path)){return 'saltado'}
            $result=Invoke-ForjaPythonLibraries -Update:$Update -Profile 'web-vision'
            return $result.State
        }
        'project-npm' {
            if($Update){Write-Dim 'Wrangler: dependencias por proyecto; para elegir uno usa modo 1 y selecciona Wrangler.';return 'saltado'}
            return (Invoke-ForjaWranglerProject)
        }
        default {Write-Warn 'Metodo de instalacion no reconocido.';return 'error'}
    }
}
function Invoke-ForjaStackProfile { param([switch]$Update)
    $results=@()
    foreach($tool in @(Get-ForjaStackCatalog | Where-Object {-not $_.Core})){
        Write-Info ("["+$tool.Group+"] "+$tool.Name)
        if(-not $Update -and -not (Ask-SN ("Incluir "+$tool.Name+'?'))){$state='saltado'}
        else {
            try {$state=Invoke-ForjaStackTool $tool -Update:$Update}
            catch {Write-Warn "$($tool.Name): fallo del paso ($($_.Exception.GetType().Name)).";$state='error'}
        }
        if($state -notin @('ok','ok-aviso','aldia','saltado','pendiente','error')){$state='error'}
        $results+=[pscustomobject]@{Id=$tool.Id;Name=$tool.Name;State=$state}
        if($Update){Add-UpdResultado $state}
        Write-Host "  Resultado: $state"
    }
    return $results
}
function Invoke-ForjaPythonUpdates { param([switch]$OfferNewBranch)
    $states=@()
    foreach($branch in @('3.15','3.14','3.13','3.12','3.11','3.10')){
        $id='Python.Python.'+$branch
        $info=Get-WingetPackageInfo $id
        if($info.State -eq 'installed'){$states+=Invoke-WingetUpdate $id ('Python '+$branch)}
        elseif($info.State -ne 'absent'){$states+='error';Write-Warn "No se pudo consultar Python $branch."}
    }
    if(-not $states.Count){Write-Dim 'No hay ramas Python administradas por WinGet. No se modifican Conda ni venvs.';return 'saltado'}
    if($OfferNewBranch){
        $target=Get-WingetPackageInfo 'Python.Python.3.14'
        if($target.State -eq 'absent'){
            Write-Info 'Python 3.14 es la rama de instalacion revisada de Forja. Puede convivir con tu Python actual.'
            if(Ask-SN 'Agregar Python 3.14 en paralelo, sin eliminar versiones ni migrar venvs/Conda?'){
                if(Install-Winget 'Python.Python.3.14' 'Python 3.14'){
                    $script:ForjaWingetInventory=$null
                    $confirmed=Get-WingetPackageInfo 'Python.Python.3.14'
                    if($confirmed.State -eq 'installed'){$states+='ok'}else{$states+='pendiente'}
                } else {$states+='error'}
            }
        }
    }
    foreach($state in @('error','pendiente','ok-aviso','ok','aldia','saltado')){if($states -contains $state){return $state}}
    return 'error'
}
function Invoke-ForjaSupabaseUpdate {
    $info=Get-WingetPackageInfo 'Supabase.CLI'
    if($info.State -eq 'installed'){return (Invoke-WingetUpdate 'Supabase.CLI' 'Supabase CLI')}
    if($info.State -ne 'absent'){return 'error'}
    if(Test-NpmPkg 'supabase'){return (Invoke-NpmUpdate 'supabase' 'Supabase CLI')}
    $tool=Get-ForjaStackCatalog | Where-Object Id -eq 'supabase-native'
    return (Invoke-ForjaArchiveTool $tool -Update)
}
function Show-ForjaProjectStack {
    Write-Section 'STACK POR PROYECTO'
    Write-Info 'React, TypeScript, Vite y Tailwind pertenecen a cada proyecto: usa su package.json y lockfile.'
    Write-Info 'Para empezar: npm create vite@latest mi-app -- --template react-ts (ejecutar manualmente donde elijas).'
    Write-Info 'Tailwind: agrega tailwindcss y @tailwindcss/vite en ese proyecto y configura el plugin de Vite.'
    Write-Info 'PWA y extensiones Chrome se construyen desde el proyecto; no requieren instalar extensiones de terceros.'
    Write-Info 'Flask/OpenCV: python -m venv .venv; luego .venv\Scripts\python.exe -m pip install Flask opencv-python.'
    Write-Info 'PostGIS se habilita en una base PostgreSQL elegida; no se ejecutan cambios SQL desde Forja.'
    Write-Info 'Supabase Edge Functions, Neon y Cloudflare necesitan el proyecto y sus permisos, ademas de la CLI.'
    Write-Info 'Autenticaciones manuales: codex login | agent login | agy | neon auth | resend login | render login.'
    Write-Info 'Cloudflare: .\node_modules\.bin\wrangler.cmd login (desde el proyecto con Wrangler instalado).'
    Write-Warn 'No se capturan tokens, no se crean recursos, no se envian emails ni se ejecutan deploys.'
    Write-Info 'Cada agente conserva sus skills, reglas y MCP: no se sobreescriben ni se copian configuraciones entre agentes.'
    Write-Info 'Grok Bot no tiene una CLI independiente verificada aqui. No se instala un paquete grok de terceros.'
}

function Get-ForjaConsoleSize {
    $width=80;$height=30
    try {
        if($Host.UI.RawUI.WindowSize.Width -ge 40){$width=[int]$Host.UI.RawUI.WindowSize.Width}
        if($Host.UI.RawUI.WindowSize.Height -ge 12){$height=[int]$Host.UI.RawUI.WindowSize.Height}
    } catch {}
    return [pscustomobject]@{Width=[Math]::Min(80,$width);Height=$height}
}
function Format-ForjaMenuLine { param([string]$Text,[int]$Width=80,[string]$Prefix='', [string]$Continuation='')
    $line=$Prefix
    foreach($word in @($Text -split '\s+' | Where-Object {$_})){
        $spacer='';if($line.Length -gt $Prefix.Length -or ($line -ne $Prefix -and $line.Length -gt $Continuation.Length)){$spacer=' '}
        if(($line.Length+$spacer.Length+$word.Length) -gt $Width -and $line.Trim()){
            Write-Output $line.TrimEnd();$line=$Continuation;$spacer=''
        }
        # Los nombres largos se cortan solo si no caben en una linea por si solos.
        $remaining=$word
        while($remaining.Length -gt ($Width-$line.Length-$spacer.Length)){
            $available=$Width-$line.Length-$spacer.Length
            if($available -le 0){Write-Output $line.TrimEnd();$line=$Continuation;$spacer='';continue}
            $line+=$spacer+$remaining.Substring(0,$available)
            Write-Output $line;$remaining=$remaining.Substring($available);$line=$Continuation;$spacer=''
        }
        $line+=$spacer+$remaining
    }
    if($line.Trim()){Write-Output $line.TrimEnd()}
}
function Get-ForjaBaseCatalog {
    $json=@'
[
  {
    "Id": "winget",
    "Group": "Infraestructura",
    "Name": "WinGet",
    "Method": "bootstrap-winget",
    "Description": "Busca, instala y actualiza programas de Windows.",
    "Package": "",
    "Command": ""
  },
  {
    "Id": "powershell",
    "Group": "Infraestructura",
    "Name": "PowerShell 7",
    "Method": "winget",
    "Description": "Terminal moderna para ejecutar comandos y automatizar tareas.",
    "Package": "Microsoft.PowerShell",
    "Command": "pwsh"
  },
  {
    "Id": "wsl",
    "Group": "Infraestructura",
    "Name": "WSL",
    "Method": "wsl-runtime",
    "Description": "Permite usar Linux dentro de Windows; tambien lo usa Docker.",
    "Package": "",
    "Command": "wsl"
  },
  {
    "Id": "git",
    "Group": "Infraestructura",
    "Name": "Git",
    "Method": "winget",
    "Description": "Guarda el historial del codigo y permite colaborar con otras personas.",
    "Package": "Git.Git",
    "Command": "git"
  },
  {
    "Id": "node",
    "Group": "Lenguajes",
    "Name": "Node.js LTS + npm",
    "Method": "winget",
    "Description": "Ejecuta JavaScript y administra las dependencias de tus proyectos web.",
    "Package": "OpenJS.NodeJS.LTS",
    "Command": "node"
  },
  {
    "Id": "pnpm",
    "Group": "Lenguajes",
    "Name": "pnpm",
    "Method": "winget",
    "Description": "Instala paquetes JavaScript ahorrando espacio y compartiendo descargas.",
    "Package": "pnpm.pnpm",
    "Command": "pnpm"
  },
  {
    "Id": "python",
    "Group": "Lenguajes",
    "Name": "Python",
    "Method": "python-runtime",
    "Description": "Lenguaje para APIs, automatizacion, datos e inteligencia artificial.",
    "Package": "",
    "Command": ""
  },
  {
    "Id": "python-base",
    "Group": "Python cientifico",
    "Name": "Librerias Python base",
    "Method": "python-libraries",
    "Description": "Entorno aislado con herramientas para APIs, PDF y conexiones web.",
    "Package": "",
    "Command": ""
  },
  {
    "Id": "vscode",
    "Group": "Editores y agentes",
    "Name": "VS Code",
    "Method": "winget",
    "Description": "Editor para abrir proyectos, programar y usar extensiones.",
    "Package": "Microsoft.VisualStudioCode",
    "Command": "code"
  },
  {
    "Id": "claude-code",
    "Group": "CLI de agentes",
    "Name": "Claude Code CLI",
    "Method": "claude-runtime",
    "Description": "Agente de Anthropic para programar y revisar proyectos desde una terminal.",
    "Package": "",
    "Command": ""
  },
  {
    "Id": "claude-app",
    "Group": "Editores y agentes",
    "Name": "Claude App",
    "Method": "winget",
    "Description": "Aplicacion de Claude para conversar, trabajar con archivos y usar sus agentes.",
    "Package": "Anthropic.Claude",
    "Command": ""
  },
  {
    "Id": "github",
    "Group": "Utilidades",
    "Name": "GitHub CLI",
    "Method": "winget",
    "Description": "Trabaja con repositorios y propuestas de cambios de GitHub desde la terminal.",
    "Package": "GitHub.cli",
    "Command": "gh"
  },
  {
    "Id": "docker",
    "Group": "Bases de datos locales",
    "Name": "Docker Desktop",
    "Method": "winget",
    "Description": "Ejecuta aplicaciones y bases de datos en contenedores separados.",
    "Package": "Docker.DockerDesktop",
    "Command": "docker"
  },
  {
    "Id": "mongosh",
    "Group": "Bases de datos locales",
    "Name": "MongoDB Shell (mongosh)",
    "Method": "winget",
    "Description": "Cliente para consultar una base MongoDB; no instala el servidor.",
    "Package": "MongoDB.Shell",
    "Command": "mongosh"
  },
  {
    "Id": "ollama",
    "Group": "Utilidades",
    "Name": "Ollama",
    "Method": "winget",
    "Description": "Descarga y ejecuta modelos de IA localmente en tu computadora.",
    "Package": "Ollama.Ollama",
    "Command": "ollama"
  },
  {
    "Id": "ffmpeg",
    "Group": "Utilidades",
    "Name": "FFmpeg",
    "Method": "winget",
    "Description": "Convierte, recorta y procesa audio y video desde comandos.",
    "Package": "Gyan.FFmpeg",
    "Command": "ffmpeg"
  },
  {
    "Id": "netlify",
    "Group": "Servicios cloud",
    "Name": "Netlify CLI",
    "Method": "npm",
    "Description": "Prueba y administra sitios web publicados en Netlify.",
    "Package": "netlify-cli",
    "Command": "netlify"
  },
  {
    "Id": "vercel",
    "Group": "Servicios cloud",
    "Name": "Vercel CLI",
    "Method": "npm",
    "Description": "Prueba y administra aplicaciones web publicadas en Vercel.",
    "Package": "vercel",
    "Command": "vercel"
  },
  {
    "Id": "supabase",
    "Group": "Servicios cloud",
    "Name": "Supabase CLI",
    "Method": "supabase",
    "Description": "Trabaja con la base, los usuarios, archivos y funciones de Supabase.",
    "Package": "",
    "Command": ""
  },
  {
    "Id": "snyk",
    "Group": "Utilidades",
    "Name": "Snyk CLI",
    "Method": "npm",
    "Description": "Analiza dependencias y busca vulnerabilidades conocidas.",
    "Package": "snyk",
    "Command": "snyk"
  },
  {
    "Id": "skills",
    "Group": "Integracion",
    "Name": "Skills opcionales de Claude",
    "Method": "skills",
    "Description": "Agrega recetas para que Claude pueda realizar tareas especializadas.",
    "Package": "",
    "Command": ""
  },
  {
    "Id": "connections",
    "Group": "Integracion",
    "Name": "Guia de conexiones",
    "Method": "guidance",
    "Description": "Explica como iniciar sesion en los servicios sin copiar claves en Forja.",
    "Package": "",
    "Command": ""
  },
  {
    "Id": "frontend-guide",
    "Group": "Por proyecto",
    "Name": "React / TypeScript / Vite / Tailwind",
    "Method": "guidance",
    "Description": "Guia para preparar una interfaz web, PWA o extension de Chrome.",
    "Package": "",
    "Command": ""
  },
  {
    "Id": "postgis-guide",
    "Group": "Por proyecto",
    "Name": "PostGIS",
    "Method": "guidance",
    "Description": "Guia para agregar funciones de mapas y ubicaciones a PostgreSQL.",
    "Package": "",
    "Command": ""
  }
]
'@
    $entries=ConvertFrom-Json -InputObject $json
    foreach($entry in $entries){Write-Output $entry}
}
function Get-ForjaToolCatalog {
    $all=@(Get-ForjaBaseCatalog)+@(Get-ForjaStackCatalog | Where-Object {-not $_.Core})
    $order=@('Infraestructura','Lenguajes','Editores y agentes','CLI de agentes','Gemini CLI (compatibilidad)','Servicios cloud','Bases de datos locales','Python cientifico','Compilacion y escritorio','Android y Java','Utilidades','Integracion','Por proyecto')
    $number=0
    foreach($group in $order){
        foreach($tool in @($all | Where-Object Group -eq $group)){
            $number++
            $entry=$tool | Select-Object *
            $entry | Add-Member -NotePropertyName Code -NotePropertyValue ('T{0:00}' -f $number)
            Write-Output $entry
        }
    }
}
function Get-ForjaToolCard {param($Tool,[int]$Width=80)
    $title='['+$Tool.Code+'] '+$Tool.Name
    Format-ForjaMenuLine $title $Width '  ' '        '
    Format-ForjaMenuLine $Tool.Description $Width '        ' '        '
}
function Show-ForjaMainMenu {param([int]$Width=0)
    if($Width -le 0){$Width=(Get-ForjaConsoleSize).Width}
    $Width=[Math]::Max(40,[Math]::Min(80,$Width));$rule='='*($Width-2)
    Write-Section $rule
    Write-Section ("  FORJA DEL DESARROLLADOR "+$VERSION)
    foreach($line in @(Format-ForjaMenuLine 'Stack para crear con agentes de IA' $Width '  ' '  ')){Write-Host $line}
    foreach($line in @(Format-ForjaMenuLine 'Rodo Agustin Garcia | ragustingarcia.com' $Width '  ' '  ')){Write-Host $line -ForegroundColor DarkGray}
    Write-Section $rule
    Write-Host ''
    foreach($line in @(Format-ForjaMenuLine 'Escribi T01, T02... para instalar o actualizar SOLO esa herramienta.' $Width '  ' '  ')){Write-Host $line -ForegroundColor Cyan}
    foreach($line in @(Format-ForjaMenuLine 'Al final estan los modos para preparar todo, actualizar o diagnosticar.' $Width '  ' '  ')){Write-Host $line -ForegroundColor DarkGray}
    $lastGroup=''
    foreach($tool in @(Get-ForjaToolCatalog)){
        if($tool.Group -ne $lastGroup){Write-Host '';Write-Section ('  --- '+$tool.Group.ToUpperInvariant()+' ---');Write-Host ''; $lastGroup=$tool.Group}
        foreach($line in @(Get-ForjaToolCard $tool $Width)){Write-Host $line}
        Write-Host ''
    }
    Write-Section $rule
    Write-Section '  MODOS DE EJECUCION'
    Write-Host ''
    foreach($line in @('[1] Preparar stack completo - base + opciones a elegir','[2] Actualizar lo instalado','[3] Diagnostico - consultar rutas y presencia','[4] Guias de proyectos y conexiones','[5] Ver este catalogo por paginas','[0] Salir (tambien ENTER)')){
        foreach($row in @(Format-ForjaMenuLine $line $Width '  ' '      ')){Write-Host $row}
        Write-Host ''
    }
    foreach($line in @(Format-ForjaMenuLine 'Tambien podes escribir el codigo T de cualquier herramienta.' $Width '  ' '  ')){Write-Host $line -ForegroundColor DarkGray}
}
function Show-ForjaFullCatalog {
    $size=Get-ForjaConsoleSize;$pageSize=[Math]::Max(7,$size.Height-5)
    $rows=@();$lastGroup=''
    foreach($tool in @(Get-ForjaToolCatalog)){
        $block=@()
        if($lastGroup -ne $tool.Group){$block+=@('';$tool.Group.ToUpperInvariant();'');$lastGroup=$tool.Group}
        $block+=@(Get-ForjaToolCard $tool $size.Width);$block+=''
        $used=$rows.Count % $pageSize
        if($used -gt 0 -and ($used+$block.Count) -gt $pageSize){$rows+=@('')*($pageSize-$used)}
        $rows+=$block
    }
    $pages=[int][Math]::Ceiling($rows.Count/[double]$pageSize)
    for($offset=0;$offset -lt $rows.Count;$offset+=$pageSize){
        Clear-Host;Write-Section ('CATALOGO COMPLETO | '+([int]($offset/$pageSize)+1)+' / '+$pages)
        $end=[Math]::Min($offset+$pageSize,$rows.Count)
        for($index=$offset;$index -lt $end;$index++){Write-Host $rows[$index]}
        if($end -lt $rows.Count){$answer=Read-Host 'ENTER: siguiente | 0: volver';if($answer -eq '0'){return}}
        else {$null=Read-Host 'ENTER: volver al menu'}
    }
}
function Invoke-ForjaWslInstall {
    try {
        $wslExe=Join-Path $env:SystemRoot 'System32\wsl.exe'
        $process=Start-Process -FilePath $wslExe -ArgumentList '--install','--no-distribution' -Verb RunAs -Wait -PassThru -ErrorAction Stop
        if($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010){Write-Warn 'WSL: reinicia y verifica wsl --status.';return 'pendiente'}
        return 'error'
    } catch {Write-Warn 'WSL no se instalo o se cancelo UAC.';return 'pendiente'}
}
function Invoke-ForjaSkillsTool {
    $skillsDest = Join-Path $env:USERPROFILE '.claude\skills'
    $skillsInstaladas = 0
    $skillsErrores = 0
    $skillsElegidas = 0
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Warn 'Git no disponible: reinicia la terminal para instalar skills.'
        $status['skills'] = 'PENDIENTE'
    } else {
        Write-Warn 'Las skills son instrucciones de terceros: revisalas antes de habilitarlas.'
        $packs = @(
            @{ Name='Forja'; Url='https://github.com/ragustingarcia/la-forja-del-desarrollador.git'; Revision=$ForjaSkillsRevision; Folder='skills\rodo'; Names=@('bat-installer-builder') },
            @{ Name='Anthropic'; Url='https://github.com/anthropics/skills.git'; Revision=$AnthropicSkillsRevision; Folder='skills'; Names=@('skill-creator','docx','pdf','xlsx','pptx') }
        )
        foreach ($pack in $packs) {
            Write-Info "$($pack.Name): revision $($pack.Revision)"
            if (-not (Ask-SN "Descargar e instalar el pack $($pack.Name)?")) { continue }
            $skillsElegidas++
            $workspace = $null
            try {
                $workspace = New-ForjaWorkspace
                $repo = Get-ReviewedSkills -Repository $pack.Url -Revision $pack.Revision -Workspace $workspace
                foreach ($name in $pack.Names) {
                    $source = Join-Path (Join-Path $repo $pack.Folder) $name
                    $adapter = $null
                    if ($pack.Name -eq 'Forja' -and (Ask-SN 'Agregar tu nombre como adaptador, conservando el credito?')) {
                        $adapter = Read-Host '  Tu nombre (una sola linea)'
                    }
                    if (Install-ReviewedSkill -Source $source -DestinationRoot $skillsDest -Name $name -Adapter $adapter) {
                        Write-OK "$name instalada."
                        $skillsInstaladas++
                    }
                }
            } catch {
                Write-Err "No se pudo completar el pack $($pack.Name). No se reemplazan skills existentes."
                $skillsErrores++
            } finally {
                if ($workspace) {
                    try { Remove-ForjaWorkspace $workspace }
                    catch { Write-Warn "Temporal retenido para revision: $workspace"; $skillsErrores++ }
                }
            }
        }
        if ($skillsErrores -gt 0) { $status['skills'] = 'ERROR' }
        elseif ($skillsElegidas -eq 0) { $status['skills'] = 'SALTADO' }
        else { $status['skills'] = "OK - $skillsInstaladas nuevas" }
    }
    switch -Regex ($status['skills']){'^OK'{return 'ok'};'^ERROR'{return 'error'};'^PENDIENTE'{return 'pendiente'};default{return 'saltado'}}
}
function Invoke-ForjaIndividualTool {param($Tool)
    # No ejecuta el recorrido completo ni instala otras selecciones.
    $env:PATH="$env:PATH;$env:ProgramFiles\nodejs;$env:APPDATA\npm;$env:USERPROFILE\.local\bin"
    try {
        switch($Tool.Method){
            'bootstrap-winget' {
                $command=Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
                if($command){$output=Invoke-ForjaCommand $command.Source @('--version') | Out-String;if($LASTEXITCODE -eq 0){Write-OK $output.Trim();return 'aldia'};return 'error'}
                Write-Info 'Instala o actualiza Instalador de aplicaciones desde Microsoft Store.'
                Start-Process 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1'
                return 'pendiente'
            }
            'python-runtime' {
                $installed=@()
                foreach($branch in @('3.15','3.14','3.13','3.12','3.11','3.10')){
                    $info=Get-WingetPackageInfo ('Python.Python.'+$branch)
                    if($info.State -eq 'installed'){$installed+=$branch}
                    elseif($info.State -ne 'absent'){return 'error'}
                }
                if($installed.Count){return (Invoke-ForjaPythonUpdates -OfferNewBranch)}
                if(-not (Install-Winget 'Python.Python.3.14' 'Python 3.14')){return 'error'}
                $script:ForjaWingetInventory=$null;$after=Get-WingetPackageInfo 'Python.Python.3.14'
                if($after.State -eq 'installed'){return 'ok'};return 'pendiente'
            }
            'python-libraries' {$result=Invoke-ForjaPythonLibraries -Update;return $result.State}
            'claude-runtime' {
                $command=Get-ForjaToolPath claude
                if(-not $command){$entry=[pscustomobject]@{Name='Claude Code CLI';Package='@anthropic-ai/claude-code';Command='claude'};return (Invoke-ForjaCatalogNpm $entry)}
                $before=Invoke-ForjaTool claude --version | Out-String;$beforeVersion=[regex]::Match($before,'\d+\.\d+\.\d+').Value
                if($LASTEXITCODE -ne 0 -or -not $beforeVersion){return 'error'}
                Invoke-ForjaTool claude update | ForEach-Object {Write-Host "  $_"};if($LASTEXITCODE -ne 0){return 'error'}
                $after=Invoke-ForjaTool claude --version | Out-String;$afterVersion=[regex]::Match($after,'\d+\.\d+\.\d+').Value
                if($LASTEXITCODE -ne 0 -or -not $afterVersion){return 'error'}
                if($afterVersion -eq $beforeVersion){return 'aldia'};return 'ok'
            }
            'wsl-runtime' {
                $wslExe=Join-Path $env:SystemRoot 'System32\wsl.exe'
                $null=Invoke-ForjaCommand $wslExe @('--status')
                if($LASTEXITCODE -eq 0){
                    $result=Invoke-ForjaPackageProcess $wslExe @('--update') 'Actualizando WSL'
                    $result.Output | ForEach-Object {Write-Host "  $_"}
                    if($result.ExitCode -eq 0){return 'aldia'};return 'error'
                }
                return (Invoke-ForjaWslInstall)
            }
            'skills' {return (Invoke-ForjaSkillsTool)}
            'guidance' {
                switch($Tool.Id){
                    'postgis-guide' {
                        Write-Section 'POSTGIS: DATOS DE MAPAS EN POSTGRESQL'
                        Write-Info 'Primero instala PostgreSQL. Agrega PostGIS compatible desde su instalador o Stack Builder.'
                        Write-Info 'Despues habilitalo en la base elegida con su administrador. Forja no ejecuta SQL ni modifica bases.'
                        Write-Info 'Guia: https://postgis.net/documentation/getting_started/install_windows/'
                    }
                    'frontend-guide' {
                        Write-Section 'FRONTEND: INTERFAZ WEB POR PROYECTO'
                        Write-Info 'React arma la interfaz; TypeScript ayuda a detectar errores; Vite ejecuta y compila el proyecto.'
                        Write-Info 'Tailwind da estilos. Las PWA agregan funciones de aplicacion; las extensiones amplian Chrome.'
                        Write-Info 'Para un proyecto nuevo: npm create vite@latest mi-app -- --template react-ts'
                        Write-Info 'Trabaja en esa carpeta y configura Tailwind segun su guia. Forja no crea ni modifica el proyecto.'
                    }
                    default {Show-ForjaProjectStack;Write-Info 'Otros accesos: gh auth login | netlify login | vercel login | supabase login | snyk auth'}
                }
                return 'guia'
            }
            'supabase' {
                if(Get-ForjaToolPath supabase){return (Invoke-ForjaSupabaseUpdate)}
                $entry=Get-ForjaStackCatalog | Where-Object Id -eq 'supabase-native'
                return (Invoke-ForjaArchiveTool $entry)
            }
            'winget' {
                $info=Get-WingetPackageInfo $Tool.Package
                if($info.State -eq 'installed'){return (Invoke-WingetUpdate $Tool.Package $Tool.Name)}
                if($info.State -eq 'absent' -and (Get-ForjaAlternatePackage $Tool)){return (Invoke-ForjaStackTool $Tool -Update)}
                return (Invoke-ForjaStackTool $Tool)
            }
            default {return (Invoke-ForjaStackTool $Tool)}
        }
    } catch {Write-Warn "$($Tool.Name): $($_.Exception.Message)";return 'error'}
}

$T = 22
$status = @{}
$necesitaReabrir = $false

# ============================================================
#  BIENVENIDA
# ============================================================
$individual=$null
do {
    Clear-Host
    Show-ForjaMainMenu
    $modoSel = ([string](Read-Host 'Opcion (0-5 o T01, T02...; ENTER = salir)')).Trim()
    if($modoSel -eq '5'){Show-ForjaFullCatalog}
    elseif($modoSel -match '^(?i:T)([0-9]{1,2})$'){
        $number=[int]$Matches[1]
        $individual=Get-ForjaToolCatalog | Where-Object Code -eq ('T{0:00}' -f $number) | Select-Object -First 1
        if(-not $individual){Write-Warn 'Ese codigo no existe. No se hicieron cambios.';$null=Read-Host 'ENTER para volver';$modoSel='menu'}
    }
} while($modoSel -in @('5','menu'))
if($individual){
    Write-Host '';Write-Section ('HERRAMIENTA INDIVIDUAL: '+$individual.Name)
    Write-Info $individual.Description
    $state='saltado'
    if($individual.Method -eq 'guidance'){$state=Invoke-ForjaIndividualTool $individual}
    elseif(Ask-SN ('Instalar o actualizar solamente '+$individual.Name+'?')){$state=Invoke-ForjaIndividualTool $individual}
    Write-Section ('Resultado: '+$state)
    $null=Read-Host 'ENTER para cerrar'
    if($state -in @('error','pendiente')){exit 1};exit 0
}
if($modoSel -eq '4'){Show-ForjaProjectStack;Read-Host '  ENTER para cerrar';exit 0}
if ($modoSel -eq '3') {
    foreach ($tool in @('winget','pwsh','wsl','git','node','npm','python','pip','claude','gh','docker','snyk')) {
        $command = Get-Command $tool -ErrorAction SilentlyContinue
        if ($command) { Write-Info "$tool : $($command.Source)" } else { Write-Dim "$tool : no encontrado" }
    }
    foreach($tool in @(Get-ForjaStackCatalog)){
        if($tool.Method -eq 'archive'){
            $root=Get-ForjaManagedRoot $tool
            Write-Info ($tool.Name+' | revisada '+$tool.Version+' | '+$root)
        } elseif($tool.Command){
            $path=Get-ForjaStackCommand $tool.Command
            Write-Info ($tool.Name+' : '+$(if($path){$path}else{'no encontrada en PATH'}))
        } elseif($tool.Method -eq 'store'){
            $app=Get-ForjaStoreApp $tool
            Write-Info ($tool.Name+' : '+$app.State+' '+$app.Version)
        } else {Write-Info ($tool.Name+' | ID '+$tool.Package)}
    }
    exit 0
}
if ($modoSel -notin @('1','2')) { Write-Dim 'Sin cambios.'; exit 0 }
Write-Warn 'Se instalaran o actualizaran paquetes de terceros. Revisa los avisos y permisos de cada proveedor.'
if (-not (Ask-SN 'Continuar con este modo?')) { exit 0 }

# ============================================================
#  MODO ACTUALIZACION
# ============================================================
if ($modoSel -eq "2") {
    Write-Host ""
    Write-Section "============================================================"
    Write-Section "  MODO ACTUALIZACION"
    Write-Dim     "  Solo se actualiza lo que ya esta instalado"
    Write-Section "============================================================"
    Write-Host ""

    $script:updOK = 0; $script:updAlDia = 0; $script:updSaltado = 0; $script:updError = 0; $script:updPendiente = 0; $script:updAvisos = 0
    $env:PATH = "$env:PATH;$env:ProgramFiles\nodejs;$env:APPDATA\npm;$env:USERPROFILE\.local\bin"

    # winget devuelve 0x8A15002B (-1978335189) cuando NO hay update aplicable;
    # es la senal confiable, independiente del idioma de Windows
    $WINGET_SIN_UPDATE = -1978335189

    # Pre-chequea si hay update; solo si lo hay corre winget upgrade
    # mostrando su barra de progreso nativa en vivo
    # El lanzador usa Windows PowerShell 5.1, por lo que pwsh no queda bloqueado.
    Write-Info 'PowerShell 7...'
    Add-UpdResultado (Invoke-WingetUpdate 'Microsoft.PowerShell' 'PowerShell 7')
    Write-Host ''

    # --- Herramientas winget ---
    $wingetTools = @(
        @("Git.Git",                    "Git"),
        @("OpenJS.NodeJS.LTS",          "Node.js LTS"),
        @("pnpm.pnpm",                  "pnpm"),
        @("Microsoft.VisualStudioCode", "VS Code"),
        @("Anthropic.Claude",           "Claude Desktop"),
        @("GitHub.cli",                 "GitHub CLI"),
        @("Docker.DockerDesktop",       "Docker Desktop"),
        @("MongoDB.Shell",              "mongosh"),
        @("Ollama.Ollama",              "Ollama"),
        @("Gyan.FFmpeg",                "FFmpeg")
    )
    foreach ($tool in $wingetTools) {
        $id = $tool[0]; $nombre = $tool[1]
        Write-Info "$nombre..."
        Add-UpdResultado (Invoke-WingetUpdate $id $nombre)
        Write-Host ""
    }

    # Actualizar cada rama instalada, sin migrar ni borrar entornos.
    Write-Info 'Python (todas las ramas WinGet instaladas)...'
    Add-UpdResultado (Invoke-ForjaPythonUpdates -OfferNewBranch)
    Write-Host ''

    Write-Info 'Supabase CLI...'
    Add-UpdResultado (Invoke-ForjaSupabaseUpdate)
    Write-Host ''

    # --- WSL ---
    Write-Info "WSL..."
    cmd /c "wsl --status >nul 2>&1"
    if ($LASTEXITCODE -eq 0) {
        Write-Dim "vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv"
        $wslUpdate=Invoke-ForjaPackageProcess (Join-Path $env:SystemRoot 'System32\wsl.exe') @('--update') 'Actualizando WSL'
        $wslUpdate.Output | ForEach-Object {Write-Host "  $_"}
        $codigo=$wslUpdate.ExitCode
        if ($codigo -ne 0) {
            # El CDN de Microsoft Store a veces devuelve 403 (Wsl/UpdatePackage/
            # 0x80190193); --web-download baja desde GitHub y lo esquiva
            Write-Warn "Fallo la descarga desde Microsoft Store. Reintentando desde GitHub..."
            $wslUpdate=Invoke-ForjaPackageProcess (Join-Path $env:SystemRoot 'System32\wsl.exe') @('--update','--web-download') 'Descargando WSL'
            $wslUpdate.Output | ForEach-Object {Write-Host "  $_"}
            $codigo=$wslUpdate.ExitCode
        }
        Write-Dim "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
        if ($codigo -eq 0) {
            # wsl --update devuelve 0 haya o no update: contarlo como "al dia"
            Write-OK "WSL al dia (se actualiza solo si hay version nueva)."
            $script:updAlDia++
        } else {
            Write-Warn "WSL: la actualizacion fallo por ambas vias. Reintenta mas tarde"
            Write-Warn "o corre manualmente: wsl --update --web-download"
            $script:updError++
        }
    } else {
        Write-Dim "WSL no esta instalado. Saltado."
        $script:updSaltado++
    }
    Write-Host ""

    # --- Claude Code CLI (updater propio: cubre instalacion nativa y npm) ---
    Write-Info "Claude Code CLI..."

    # Deteccion de doble instalacion (npm global + nativa). Tener las dos
    # confunde al PATH y al updater; Anthropic recomienda la nativa.
    $claudeNpm    = (Test-Path "$env:APPDATA\npm\claude*") -or (Test-Path "$env:APPDATA\npm\node_modules\@anthropic-ai\claude-code")
    $claudeNativo = Test-Path -LiteralPath "$env:USERPROFILE\.local\bin\claude.exe" -PathType Leaf
    if ($claudeNpm -and $claudeNativo) {
        Write-Warn "Se detectaron DOS instalaciones de Claude Code:"
        Write-Host "    - npm global  (AppData\Roaming\npm)" -ForegroundColor White
        Write-Host "    - nativa      (.local\share\claude)  <- recomendada por Anthropic" -ForegroundColor White
        Write-Host ""
        Write-Warn "IMPORTANTE: cerra TODAS las sesiones de Claude Code antes de limpiar"
        Write-Warn "(otras terminales, VS Code, la app de escritorio con sesiones activas)."
        Write-Host ""
        if (Ask-SN "Eliminar la instalacion npm y quedarte solo con la nativa?") {
            Write-Host ""
            Write-Info "Eliminando instalacion npm de Claude Code..."
            $cleanResult = Remove-ForjaClaudeNpm
            if ($cleanResult -eq 'error') { $script:updError++ }
            Write-Host ""
        } else {
            Write-Dim "Se mantienen las dos instalaciones."
            Write-Host ""
        }
    }

    if (Get-Command claude -ErrorAction SilentlyContinue) {
        $claudeBefore=$null
        $beforeOutput=Invoke-ForjaTool claude --version 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and $beforeOutput -match '\d+\.\d+\.\d+') { $claudeBefore=$Matches[0] }
        Write-Dim "vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv"
        Invoke-ForjaTool claude update
        $codigo = $LASTEXITCODE
        Write-Dim "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
        if ($codigo -eq 0) {
            $versionClaude = (Invoke-ForjaTool claude --version 2>&1) | Out-String
            if ($LASTEXITCODE -eq 0 -and $versionClaude -match '\d+\.\d+\.\d+') {
                $claudeAfter=$Matches[0]
                Write-OK "Claude Code CLI: version $($versionClaude.Trim())."
                if ($claudeBefore -eq $claudeAfter) { $script:updAlDia++ } else { $script:updOK++ }
            }
            else { Write-Warn 'Claude Code CLI: el updater termino, pero no se pudo verificar la version.'; $script:updError++ }
        } else { Write-Warn "Claude Code CLI: proba 'claude update' en una terminal nueva."; $script:updError++ }
    } else {
        Write-Dim "Claude Code CLI no esta instalado. Saltado."
        $script:updSaltado++
    }
    Write-Host ""

    # --- Paquetes npm globales ---
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        $npmTools = @(
            @("netlify-cli", "Netlify CLI"),
            @("vercel",      "Vercel CLI"),
            @("snyk",        "Snyk CLI")
        )
        foreach ($tool in $npmTools) {
            $pkg = $tool[0]; $nombre = $tool[1]
            Write-Info "$nombre..."
            if (Test-NpmPkg $pkg) {
                Add-UpdResultado (Invoke-NpmUpdate $pkg $nombre)
            } else {
                Write-Dim "$nombre no esta instalado. Saltado."
                $script:updSaltado++
            }
            Write-Host ""
        }
    } else {
        Write-Warn "npm no disponible: se saltean los paquetes npm."
        Write-Host ""
    }

    # --- Librerias Python: nunca modificar el interprete compartido ---
    Write-Info 'Librerias Python...'
    $pythonResult=Invoke-ForjaPythonLibraries -Update
    Add-UpdResultado $pythonResult.State
    if ($pythonResult.SharedConflict) { Add-UpdResultado 'aviso' }

    Write-Section 'AGENTES, CLI Y SERVICIOS DEL STACK'
    $null=Invoke-ForjaStackProfile -Update

    # --- Resumen ---
    Write-Host ""
    Write-Section "============================================================"
    Write-Section "  RESUMEN DE ACTUALIZACION"
    Write-Section "============================================================"
    Write-Host ""
    Write-Host "  Actualizados:    $script:updOK" -ForegroundColor Green
    Write-Host "  Ya al dia:       $script:updAlDia" -ForegroundColor Green
    Write-Host "  Saltados:        $script:updSaltado" -ForegroundColor DarkGray
    Write-Host "  Pendientes:      $script:updPendiente" -ForegroundColor Yellow
    Write-Host "  Con avisos:      $script:updAvisos" -ForegroundColor Yellow
    Write-Host "  Con errores:     $script:updError" -ForegroundColor Yellow

    if ($script:updError -gt 0) {
        Write-Host ""
        Write-Warn "Revisa el detalle de cada error mas arriba. Causas tipicas:"
        Write-Warn "un programa abierto (cerralo y reintenta) o una falla temporal"
        Write-Warn "de red o del servidor de descargas (reintenta mas tarde)."
    }
    Write-Host ""
    Write-Section "============================================================"
    Write-Host ""
    Write-Host "  La Forja del Desarrollador $VERSION" -ForegroundColor Yellow
    Write-Dim   "  by Rodolfo Agustin Garcia  |  ragustingarcia.com"
    Write-Host ""
    Write-Section "============================================================"
    Write-Host ""

    Read-Host "  Presiona ENTER para cerrar"

    if ($script:updError -gt 0 -or $script:updPendiente -gt 0) { exit 1 }; exit 0
}

# ============================================================
#  [1] WINGET
# ============================================================
Write-Titulo 1 $T "winget" "Gestor de paquetes de Windows"
Write-Host "  Instala programas desde la terminal."
Write-Host "  Ej: winget install Git.Git | winget search python"
Write-Host ""
Write-Info "Verificando..."
Write-Host ""

$wc = Get-Command winget -ErrorAction SilentlyContinue
if ($wc) {
    $wv = (winget --version 2>&1) | Out-String
    Write-OK "winget ya instalado ($($wv.Trim()))."
    $status["winget"] = "OK"
} else {
    Write-Warn "No encontrado. Abriendo Microsoft Store..."
    Start-Process "ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1"
    $status["winget"] = "MANUAL"
    Read-Host "  Instala 'Instalador de aplicaciones' y presiona ENTER para continuar"
}

# ============================================================
#  [2] POWERSHELL 7
# ============================================================
Write-Titulo 2 $T "PowerShell 7" "Terminal moderna"
Write-Host "  Terminal avanzada de Microsoft. La Forja arranca con Windows PowerShell 5.1."
Write-Host "  Ej: Ejecutar scripts, gestionar archivos, pipelines de datos"
Write-Host ""
Write-Info "Verificando..."
Write-Host ""

if (Get-Command pwsh -ErrorAction SilentlyContinue) {
    $pv = (pwsh --version 2>&1) | Out-String
    Write-OK "PowerShell 7 ($($pv.Trim()))."
    $status["pwsh"] = "OK"
} else {
    if (Install-Winget "Microsoft.PowerShell" "PowerShell 7") {
        Write-OK "Instalado."
        $status["pwsh"] = "OK"
    } else {
        Write-Err "Error instalando PowerShell 7."
        $status["pwsh"] = "ERROR"
    }
}

Write-Host ""
Write-Dim 'Para usar PowerShell 7 por defecto: Windows Terminal > Configuracion > Perfil predeterminado.'

# ============================================================
#  [3] WSL
# ============================================================
Write-Titulo 3 $T "WSL" "Windows Subsystem for Linux"
Write-Host "  Corre Linux dentro de Windows. Docker lo necesita."
Write-Host "  Ej: wsl --install | wsl --update"
Write-Host ""
Write-Info "Verificando..."
Write-Host ""

# wsl.exe emite UTF-16 con nulos intercalados: no parsear texto, usar exit code
$wslInstalled = $false
try {
    cmd /c "wsl --status >nul 2>&1"
    if ($LASTEXITCODE -eq 0) { $wslInstalled = $true }
} catch {}

if ($wslInstalled) {
    $status['wsl'] = 'OK'
    Write-OK 'WSL ya instalado. Las actualizaciones se hacen en el modo [2].'
} elseif (Ask-SN 'Instalar WSL? Solo este paso pedira permisos de administrador') {
    $state=Invoke-ForjaWslInstall
    if($state -eq 'pendiente'){$status['wsl']='PENDIENTE - REINICIAR Y VERIFICAR';$necesitaReabrir=$true}
    else {$status['wsl']='ERROR'}
} else { $status['wsl'] = 'SALTADO' }

# ============================================================
#  [4] GIT
# ============================================================
Write-Titulo 4 $T "Git" "Control de versiones"
Write-Host "  Registra cambios en tu codigo. Colabora con otros."
Write-Host "  Ej: git init | git push | git clone URL"
Write-Host ""
Write-Info "Verificando..."
Write-Host ""

if (Get-Command git -ErrorAction SilentlyContinue) {
    $gv = (git --version 2>&1) | Out-String
    Write-OK "Git ($($gv.Trim()))."
    $status["git"] = "OK"
} else {
    if (Install-Winget "Git.Git" "Git") {
        Write-OK "Instalado."
        $status["git"] = "OK"
        $necesitaReabrir = $true
    } else {
        Write-Err "Error instalando Git."
        $status["git"] = "ERROR"
    }
}

Write-Host ""
Write-Separador
Write-Info "Configuracion de identidad Git (necesaria para hacer commits)..."
Write-Host ""
if (Get-Command git -ErrorAction SilentlyContinue) {
    $gitName  = (git config --global user.name  2>&1) | Out-String
    $gitEmail = (git config --global user.email 2>&1) | Out-String
    if ($gitName.Trim() -and $gitEmail.Trim()) {
        Write-OK "Identidad ya configurada: $($gitName.Trim()) <$($gitEmail.Trim())>"
    } else {
        Write-Warn "Git no tiene nombre/email configurado. Sin esto los commits fallan."
        Write-Host ""
        $inputNombre = Read-Host "  Tu nombre completo (ej: Juan Perez)"
        $inputEmail  = Read-Host "  Tu email de GitHub"
        if ($inputNombre) { git config --global user.name  $inputNombre }
        if ($inputEmail)  { git config --global user.email $inputEmail  }
        git config --global core.autocrlf true
        git config --global init.defaultBranch main
        Write-OK "Identidad Git configurada."
    }
} else {
    Write-Warn "Git recien instalado: reinicia la terminal y corre el script"
    Write-Warn "de nuevo para configurar tu nombre y email."
}

# ============================================================
#  [5] NODE.JS LTS
# ============================================================
Write-Titulo 5 $T "Node.js LTS" "Motor de JavaScript"
Write-Host "  Ejecuta JavaScript fuera del navegador. Viene con npm."
Write-Host "  Ej: npm install react | npx create-next-app ."
Write-Host ""
Write-Info "Verificando..."
Write-Host ""

$env:PATH = "$env:PATH;$env:ProgramFiles\nodejs;$env:APPDATA\npm"
if (Get-Command node -ErrorAction SilentlyContinue) {
    $nv = (node --version 2>&1) | Out-String
    Write-OK "Node.js ($($nv.Trim()))."
    $status["node"] = "OK"
} else {
    if (Install-Winget "OpenJS.NodeJS.LTS" "Node.js LTS") {
        Write-OK "Instalado."
        $status["node"] = "OK - REABRIR"
        $necesitaReabrir = $true
    } else {
        Write-Err "Error instalando Node.js."
        $status["node"] = "ERROR"
    }
}

# ============================================================
#  [6] PNPM
# ============================================================
Write-Titulo 6 $T "pnpm" "Gestor de paquetes rapido"
Write-Host "  Alternativa a npm: mas rapido, usa menos disco."
Write-Host "  Ej: pnpm install | pnpm add vite | pnpm run dev"
Write-Host ""
Write-Info "Verificando..."
Write-Host ""

if (Get-Command pnpm -ErrorAction SilentlyContinue) {
    $pnpmv = (Invoke-ForjaTool pnpm --version 2>&1) | Out-String
    Write-OK "pnpm ($($pnpmv.Trim()))."
    $status["pnpm"] = "OK"
} else {
    if (Install-Winget "pnpm.pnpm" "pnpm") {
        Write-OK "Instalado."
        $status["pnpm"] = "OK - REABRIR"
        $necesitaReabrir = $true
    } else {
        $nm = Get-Command npm -ErrorAction SilentlyContinue
        if ($nm) {
            Write-Info "[INSTALANDO] pnpm via npm..."
            Invoke-ForjaTool npm install -g pnpm 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0 -and (Get-Command pnpm -ErrorAction SilentlyContinue)) { Write-OK "Instalado via npm."; $status["pnpm"] = "OK" }
            else { Write-Err "Error."; $status["pnpm"] = "ERROR" }
        } else {
            Write-Warn "npm no disponible. Instalar pnpm despues."
            $status["pnpm"] = "PENDIENTE"
            $necesitaReabrir = $true
        }
    }
}

# ============================================================
#  [7] PYTHON 3.13
# ============================================================
Write-Titulo 7 $T "Python (actualizable)" "Lenguaje para backend e IA"
Write-Host "  Popular para IA, automatizacion y web."
Write-Host "  Ej: python script.py | pip install fastapi"
Write-Host ""
Write-Info "Verificando..."
Write-Host ""

$pyPaths = @(
    "$env:LOCALAPPDATA\Programs\Python\Python314",
    "$env:LOCALAPPDATA\Programs\Python\Python314\Scripts",
    "$env:ProgramFiles\Python314",
    "$env:ProgramFiles\Python314\Scripts"
)
foreach ($p in $pyPaths) { if ((Test-Path $p) -and ($env:PATH -notlike "*$p*")) { $env:PATH = "$p;$env:PATH" } }

$pv = Test-PythonReal
if ($pv) {
    Write-OK "Python ($pv)."
    $status["python"] = "OK"
    Write-Info 'El modo 2 actualiza las ramas WinGet instaladas. Los venvs y Conda se conservan.'
    if($pv -notmatch 'Python 3\.14\.' -and (Ask-SN 'Agregar Python 3.14 en paralelo, sin eliminar tu version ni migrar proyectos?')) {
        if(-not (Install-Winget 'Python.Python.3.14' 'Python 3.14')){$status['python']='ERROR'}
    }
} else {
    if (Install-Winget "Python.Python.3.14" "Python 3.14") {
        Write-OK "Instalado."
        foreach ($p in $pyPaths) { if ((Test-Path $p) -and ($env:PATH -notlike "*$p*")) { $env:PATH = "$p;$env:PATH" } }
        if (Test-PythonReal) { $status["python"] = "OK" }
        else { $status["python"] = "OK - REABRIR"; $necesitaReabrir = $true }
    } else {
        Write-Err "Error instalando Python 3.14."
        $status["python"] = "ERROR"
    }
}

# ============================================================
#  [8] LIBRERIAS PYTHON
# ============================================================
Write-Titulo 8 $T "Librerias Python" "Backend, procesamiento y datos"
Write-Host "  fastapi | uvicorn | python-multipart | pdfplumber | requests"
Write-Host ""
Write-Info "Verificando..."
Write-Host ""

$pythonResult=Invoke-ForjaPythonLibraries
if ($pythonResult.State -in @('ok','aldia')) { $status['pylibs']='OK' }
elseif ($pythonResult.State -eq 'saltado') { $status['pylibs']='SALTADO' }
else { $status['pylibs']='ERROR' }
if ($pythonResult.SharedConflict) { Write-Warn 'El Python compartido requiere revision por separado. No se modifico.' }

# ============================================================
#  [9] VS CODE
# ============================================================
Write-Titulo 9 $T "Visual Studio Code" "Editor de codigo"
Write-Host "  Editor mas popular del mundo."
Write-Host "  Ej: code . (abre carpeta actual en VS Code)"
Write-Host ""
Write-Info "Verificando..."
Write-Host ""

if (Get-Command code -ErrorAction SilentlyContinue) {
    Write-OK "VS Code instalado."
    $status["vscode"] = "OK"
} else {
    if (Install-Winget "Microsoft.VisualStudioCode" "VS Code") {
        Write-OK "Instalado."
        $status["vscode"] = "OK"
    } else {
        Write-Err "Error instalando VS Code."
        $status["vscode"] = "ERROR"
    }
}

# ============================================================
#  [10] CLAUDE CODE CLI
# ============================================================
Write-Titulo 10 $T "Claude Code CLI" "IA que desarrolla con vos"
Write-Host "  Herramienta central. Lee, escribe y testea codigo."
Write-Host '  Ej: claude | claude "crea un componente Card en React"'
Write-Host ""
Write-Info "Verificando..."
Write-Host ""

$env:PATH = "$env:PATH;$env:ProgramFiles\nodejs;$env:APPDATA\npm"
$nm = Get-Command npm -ErrorAction SilentlyContinue
if (-not $nm) {
    Write-Warn "npm no disponible. Reinicia y corre el script de nuevo."
    $status["claude"] = "PENDIENTE"
    $necesitaReabrir = $true
} else {
    if (Get-Command claude -ErrorAction SilentlyContinue) {
        Write-OK "Claude Code ya instalado."
        $status["claude"] = "OK"
    } else {
        Write-Info "[INSTALANDO] Claude Code (puede tardar 3-8 min)..."
        Write-Dim "vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv"
        Invoke-ForjaTool npm install -g @anthropic-ai/claude-code --loglevel verbose 2>&1 | ForEach-Object { Write-Host "  $_" }
        Write-Dim "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
        $env:PATH = "$env:PATH;$env:APPDATA\npm"
        if ($LASTEXITCODE -eq 0 -and (Get-Command claude -ErrorAction SilentlyContinue)) {
            Write-OK "Instalado."
            $status["claude"] = "OK"
        } else {
            Write-Err "Error instalando Claude Code."
            $status["claude"] = "ERROR"
        }
    }

    if ($status["claude"] -eq "OK") {
        Write-Host ""
        Write-Separador
        Write-Info "Verificando instalacion..."
        # claude doctor es interactivo (TUI): no sirve en un script desatendido
        try {
            $cv = (Invoke-ForjaTool claude --version 2>&1) | Out-String
            if ($cv -match "\d+\.\d+") { Write-OK "Claude Code responde ($($cv.Trim()))." }
            else { Write-Warn "Instalado pero no responde. Corre 'claude doctor' en una terminal nueva." }
        } catch {
            Write-Warn "No se pudo verificar. Corre 'claude doctor' en una terminal nueva."
        }
    }
}

# ============================================================
#  [11] CLAUDE DESKTOP
# ============================================================
Write-Titulo 11 $T "Claude App" "Aplicacion de escritorio"
Write-Host "  App visual de Claude. Chat, archivos, atajos de teclado."
Write-Host "  Ej: Alt+Espacio (acceso rapido global)"
Write-Host ""
Write-Info "Verificando..."
Write-Host ""

if (Test-WingetPkg "Anthropic.Claude") {
    Write-OK "Claude Desktop instalado."
    $status["claudeApp"] = "OK"
} else {
    if (Install-Winget "Anthropic.Claude" "Claude Desktop") {
        Write-OK "Instalado."
        $status["claudeApp"] = "OK"
    } else {
        Write-Err "Error instalando Claude Desktop."
        $status["claudeApp"] = "ERROR"
    }
}

# ============================================================
#  [12] GITHUB CLI
# ============================================================
Write-Titulo 12 $T "GitHub CLI (gh)" "Gestionar repos desde terminal"
Write-Host "  CLI oficial de GitHub. Claude Code la usa internamente."
Write-Host "  Ej: gh auth login | gh repo create | gh pr create"
Write-Host ""
Write-Info "Verificando..."
Write-Host ""

if (Get-Command gh -ErrorAction SilentlyContinue) {
    $ghv = (gh --version 2>&1 | Select-Object -First 1) | Out-String
    Write-OK "GitHub CLI ($($ghv.Trim()))."
    $status["ghcli"] = "OK"
} else {
    if (Install-Winget "GitHub.cli" "GitHub CLI") {
        Write-OK "Instalado."
        $status["ghcli"] = "OK"
        $necesitaReabrir = $true
    } else {
        Write-Err "Error instalando GitHub CLI."
        $status["ghcli"] = "ERROR"
    }
}

# ============================================================
#  [13] DOCKER
# ============================================================
Write-Titulo 13 $T "Docker Desktop" "Contenedores y servicios"
Write-Host "  Corre apps en contenedores aislados. Necesita WSL."
Write-Host "  Ej: docker compose up | supabase start (requiere Docker)"
Write-Warn "  Nota: Requiere reiniciar PC despues de instalar."
Write-Host ""
Write-Info "Verificando..."
Write-Host ""

if (Get-Command docker -ErrorAction SilentlyContinue) {
    Write-OK "Docker instalado."
    $status["docker"] = "OK"
} else {
    if (Install-Winget "Docker.DockerDesktop" "Docker Desktop") {
        Write-OK "Instalado."
        Write-Warn "Requiere REINICIAR la PC para funcionar."
        $status["docker"] = "OK - REINICIAR"
        $necesitaReabrir = $true
    } else {
        Write-Err "Error instalando Docker."
        $status["docker"] = "ERROR"
    }
}

# ============================================================
#  [14] MONGOSH
# ============================================================
Write-Titulo 14 $T "mongosh" "Cliente de MongoDB"
Write-Host "  Cliente para conectarte a MongoDB Atlas o local."
Write-Host '  Ej: mongosh "mongodb+srv://..." | db.users.find()'
Write-Host ""
Write-Info "Verificando..."
Write-Host ""

if (Get-Command mongosh -ErrorAction SilentlyContinue) {
    Write-OK "mongosh instalado."
    $status["mongosh"] = "OK"
} else {
    if (Install-Winget "MongoDB.Shell" "mongosh") {
        Write-OK "Instalado."
        $status["mongosh"] = "OK"
        $necesitaReabrir = $true
    } else {
        Write-Err "Error instalando mongosh."
        $status["mongosh"] = "ERROR"
    }
}

# ============================================================
#  [15] OLLAMA
# ============================================================
Write-Titulo 15 $T "Ollama" "IA local sin internet"
Write-Host "  Corre modelos de IA en tu PC: Llama, Mistral, Gemma."
Write-Host "  Ej: ollama run llama3 | ollama run codellama"
Write-Host ""
Write-Info "Verificando..."
Write-Host ""

if (Get-Command ollama -ErrorAction SilentlyContinue) {
    Write-OK "Ollama instalado."
    $status["ollama"] = "OK"
} else {
    if (Install-Winget "Ollama.Ollama" "Ollama") {
        Write-OK "Instalado."
        $status["ollama"] = "OK"
        $necesitaReabrir = $true
    } else {
        Write-Err "Error instalando Ollama."
        $status["ollama"] = "ERROR"
    }
}

# ============================================================
#  [16] FFMPEG
# ============================================================
Write-Titulo 16 $T "FFmpeg" "Procesamiento de audio y video"
Write-Host "  Convierte, corta y procesa audio/video."
Write-Host "  Ej: ffmpeg -i video.mp4 audio.mp3"
Write-Host ""
Write-Info "Verificando..."
Write-Host ""

if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
    Write-OK "FFmpeg instalado."
    $status["ffmpeg"] = "OK"
} else {
    if (Install-Winget "Gyan.FFmpeg" "FFmpeg") {
        Write-OK "Instalado."
        $status["ffmpeg"] = "OK"
        $necesitaReabrir = $true
    } else {
        Write-Err "Error instalando FFmpeg."
        $status["ffmpeg"] = "ERROR"
    }
}

# ============================================================
#  [17] NETLIFY CLI
# ============================================================
Write-Titulo 17 $T "Netlify CLI" "Deploy de sitios web"
Write-Host "  Publica frontends y sitios estaticos desde la terminal."
Write-Host "  Ej: netlify login | netlify deploy --prod"
Write-Host ""
Write-Info "Verificando..."
Write-Host ""

$nm = Get-Command npm -ErrorAction SilentlyContinue
if (-not $nm) {
    Write-Warn "npm no disponible. Reinicia y corre el script de nuevo."
    $status["netlify"] = "PENDIENTE"
    $necesitaReabrir = $true
} else {
    if (Test-NpmPkg "netlify-cli") {
        Write-OK "Netlify CLI instalado."
        $status["netlify"] = "OK"
    } else {
        if (Install-Npm "netlify-cli" "Netlify CLI") {
            Write-OK "Instalado."
            $status["netlify"] = "OK"
        } else {
            Write-Err "Error instalando Netlify CLI."
            $status["netlify"] = "ERROR"
        }
    }
}

# ============================================================
#  [18] VERCEL CLI
# ============================================================
Write-Titulo 18 $T "Vercel CLI" "Deploy de apps Next.js y React"
Write-Host "  Plataforma de los creadores de Next.js."
Write-Host "  Ej: vercel login | vercel --prod | vercel dev"
Write-Host ""
Write-Info "Verificando..."
Write-Host ""

$nm = Get-Command npm -ErrorAction SilentlyContinue
if (-not $nm) {
    Write-Warn "npm no disponible. Reinicia y corre el script de nuevo."
    $status["vercel"] = "PENDIENTE"
    $necesitaReabrir = $true
} else {
    if (Test-NpmPkg "vercel") {
        Write-OK "Vercel CLI instalado."
        $status["vercel"] = "OK"
    } else {
        if (Install-Npm "vercel" "Vercel CLI") {
            Write-OK "Instalado."
            $status["vercel"] = "OK"
        } else {
            Write-Err "Error instalando Vercel CLI."
            $status["vercel"] = "ERROR"
        }
    }
}

# ============================================================
#  [19] SUPABASE CLI
# ============================================================
Write-Titulo 19 $T "Supabase CLI" "Base de datos y autenticacion"
Write-Host "  PostgreSQL, auth, storage y edge functions."
Write-Host "  Ej: supabase init | supabase start (requiere Docker)"
Write-Host ""
Write-Info "Verificando..."
Write-Host ""

$supabasePath=Get-ForjaToolPath 'supabase'
if($supabasePath){
    $sbv=Invoke-ForjaTool supabase --version | Out-String
    if($LASTEXITCODE -eq 0){Write-OK ("Supabase CLI: "+$sbv.Trim());$status['supabase']='OK'}
    else {$status['supabase']='ERROR'}
} else {
    $supabaseTool=Get-ForjaStackCatalog | Where-Object Id -eq 'supabase-native'
    $state=Invoke-ForjaArchiveTool $supabaseTool
    if($state -in @('ok','aldia')){$status['supabase']='OK'}
    elseif($state -eq 'pendiente'){$status['supabase']='PENDIENTE'}else{$status['supabase']='ERROR'}
}

# ============================================================
#  [20] SNYK CLI
# ============================================================
Write-Titulo 20 $T "Snyk CLI" "Escaner de vulnerabilidades"
Write-Host "  Escanea dependencias por fallas de seguridad."
Write-Host "  Cubre JS, Python y Docker. Gratis para uso personal."
Write-Host "  Ej: snyk test | snyk monitor"
Write-Host ""
Write-Info "Verificando..."
Write-Host ""

$nm = Get-Command npm -ErrorAction SilentlyContinue
if (-not $nm) {
    Write-Warn "npm no disponible. Reinicia y corre el script de nuevo."
    $status["snyk"] = "PENDIENTE"
    $necesitaReabrir = $true
} else {
    if (Test-NpmPkg "snyk") {
        Write-OK "Snyk CLI instalado."
        $status["snyk"] = "OK"
    } else {
        if (Install-Npm "snyk" "Snyk CLI") {
            Write-OK "Instalado."
            $status["snyk"] = "OK"
        } else {
            Write-Err "Error instalando Snyk CLI."
            $status["snyk"] = "ERROR"
        }
    }
}

Write-Section 'ELEGIR AGENTES, CLI Y SERVICIOS DEL STACK'
Write-Dim 'Cada herramienta es opcional; N o ENTER conserva la seleccion fuera de esta instalacion.'
$stackResults=@(Invoke-ForjaStackProfile)
foreach($result in $stackResults){
    $status['stack-'+$result.Id]=switch($result.State){'error'{'ERROR'};'pendiente'{'PENDIENTE'};'saltado'{'SALTADO'};default{'OK'}}
}
Show-ForjaProjectStack

# ============================================================
#  [21] SKILLS DE CLAUDE CODE
# ============================================================
Write-Titulo 21 $T "Skills de Claude Code" "Capacidades que se cargan bajo demanda"
Write-Host "  Una skill le ensena a Claude Code una capacidad nueva y se"
Write-Host "  carga SOLO cuando se usa: no gasta tokens el resto del tiempo."
Write-Host "  Ej: /bat-installer-builder | skill-creator | docx, pdf, xlsx"
Write-Host ""

$null=Invoke-ForjaSkillsTool

# ============================================================
#  RESUMEN DE INSTALACION
# ============================================================
Write-Host ""
Write-Host ""
Write-Section "============================================================"
Write-Section "  RESUMEN DE INSTALACION (base + stack elegido)"
Write-Section "============================================================"
Write-Host ""

$items = @(
    @("winget",    "winget"),
    @("pwsh",      "PowerShell 7"),
    @("wsl",       "WSL"),
    @("git",       "Git"),
    @("node",      "Node.js LTS"),
    @("pnpm",      "pnpm"),
    @("python",    "Python"),
    @("pylibs",    "Librerias Python"),
    @("vscode",    "VS Code"),
    @("claude",    "Claude Code CLI"),
    @("claudeApp", "Claude Desktop"),
    @("ghcli",     "GitHub CLI"),
    @("docker",    "Docker"),
    @("mongosh",   "mongosh"),
    @("ollama",    "Ollama"),
    @("ffmpeg",    "FFmpeg"),
    @("netlify",   "Netlify CLI"),
    @("vercel",    "Vercel CLI"),
    @("supabase",  "Supabase CLI"),
    @("snyk",      "Snyk CLI"),
    @("skills",    "Skills de Claude Code")
)

$items+=@($stackResults | ForEach-Object { ,@(('stack-'+$_.Id),$_.Name) })
foreach ($item in $items) {
    $val = $status[$item[0]]
    if (-not $val) { $val = "SALTADO" }
    if ($val -match "^OK") {
        Write-Host "  [OK] $($item[1])" -ForegroundColor Green
        if ($val -ne "OK") { Write-Dim "       $val" }
    } elseif ($val -match "ERROR") {
        Write-Host "  [X]  $($item[1])" -ForegroundColor Red
    } else {
        Write-Host "  [!!] $($item[1]) : $val" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Section "============================================================"

if ($necesitaReabrir) {
    Write-Host ""
    Write-Warn "Algunos cambios requieren reiniciar la terminal o la PC."
    Write-Warn "Ejecuta este script de nuevo despues de reiniciar para"
    Write-Warn "verificar que todo quedo instalado correctamente."
    Write-Host ""
    Write-Section "============================================================"
}

# ============================================================
#  [22] ASISTENTE DE VINCULACION
# ============================================================
Write-Host ""
Write-Section "============================================================"
Write-Section "  [22/$T] Asistente de vinculacion de servicios"
Write-Dim     "  Conecta cada herramienta con tu cuenta"
Write-Section "============================================================"
Write-Host ""
Write-Host "  Verificando y conectando servicios..."
Write-Host ""
Write-Section "------------------------------------------------------------"
Write-Host ""

$conexiones = @{}

# --- GITHUB CLI ---
Write-Info "GitHub CLI (gh)..."
try {
    $ghs = (gh auth status 2>&1) | Out-String
    if ($LASTEXITCODE -eq 0) { Write-OK "GitHub CLI: Conectado"; $conexiones["GitHub CLI"] = "OK" } else { throw }
} catch {
    Write-Warn "GitHub CLI: No conectado"
    $conexiones["GitHub CLI"] = "PENDIENTE"
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        Write-Host ""
        Write-Host "  GitHub CLI gestiona repos, PRs e issues desde la terminal." -ForegroundColor White
        Write-Host "  Claude Code lo usa internamente para crear repos y PRs." -ForegroundColor White
        Write-Host ""
        if (Ask-SN "Conectar GitHub CLI ahora?") {
            Write-Host ""
            Write-Info "Se va a abrir el navegador para loguearte en GitHub."
            Write-Host ""
            gh auth login
            try {
                $check = (gh auth status 2>&1) | Out-String
                if ($LASTEXITCODE -eq 0) { Write-OK "GitHub CLI conectado!"; $conexiones["GitHub CLI"] = "OK" }
            } catch {}
        }
    }
}

# --- CLAUDE MCP GITHUB ---
Write-Host ""
Write-Separador
Write-Info "Claude MCP — GitHub server..."
$conexiones['Claude MCP'] = 'OPCIONAL - MANUAL'
Write-Info 'GitHub CLI ya permite trabajar con repositorios desde Claude Code.'
Write-Dim 'El MCP es opcional; la Forja no solicita ni guarda tokens de GitHub.'
Write-Dim 'Configura el servidor mantenido por GitHub siguiendo su guia oficial:'
Write-Dim 'https://github.com/github/github-mcp-server/blob/main/docs/installation-guides/install-claude.md'
Write-Dim 'Limita repositorios, permisos y herramientas; empeza en modo solo lectura.'
Write-Warn 'Si usaste v6.0: revisa el PAT anterior y GITHUB_PERSONAL_ACCESS_TOKEN. Ver SECURITY.md.'

# --- NETLIFY ---
Write-Host ""
Write-Separador
Write-Info "Netlify..."
try {
    $ns = (Invoke-ForjaTool netlify status 2>&1) | Out-String
    if ($LASTEXITCODE -eq 0 -and $ns -match "Logged in|Email:") { Write-OK "Netlify: Conectado"; $conexiones["Netlify"] = "OK" } else { throw }
} catch {
    Write-Warn "Netlify: No conectado"
    $conexiones["Netlify"] = "PENDIENTE"
    if (Get-Command netlify -ErrorAction SilentlyContinue) {
        Write-Host ""
        Write-Host "  Publica sitios web con un comando: netlify deploy --prod" -ForegroundColor White
        Write-Host ""
        if (Ask-SN "Conectar Netlify ahora? (se abre el navegador)") {
            Write-Host ""
            Invoke-ForjaTool netlify login
            try {
                $nc = (Invoke-ForjaTool netlify status 2>&1) | Out-String
                if ($LASTEXITCODE -eq 0 -and $nc -match "Logged in|Email:") { Write-OK "Netlify conectado!"; $conexiones["Netlify"] = "OK" }
            } catch {}
        }
    }
}

# --- VERCEL ---
Write-Host ""
Write-Separador
Write-Info "Vercel..."
try {
    $vs = (Invoke-ForjaTool vercel whoami 2>&1) | Out-String
    if ($LASTEXITCODE -eq 0 -and $vs -match "\w" -and $vs -notmatch "Error|not logged|No user") {
        Write-OK "Vercel: Conectado como $($vs.Trim())"
        $conexiones["Vercel"] = "OK"
    } else { throw }
} catch {
    Write-Warn "Vercel: No conectado"
    $conexiones["Vercel"] = "PENDIENTE"
    if (Get-Command vercel -ErrorAction SilentlyContinue) {
        Write-Host ""
        Write-Host "  Publica apps Next.js y React: vercel --prod" -ForegroundColor White
        Write-Host ""
        if (Ask-SN "Conectar Vercel ahora?") {
            Write-Host ""
            Invoke-ForjaTool vercel login
            try {
                $vc = (Invoke-ForjaTool vercel whoami 2>&1) | Out-String
                if ($LASTEXITCODE -eq 0 -and $vc -match "\w" -and $vc -notmatch "Error") { Write-OK "Vercel conectado!"; $conexiones["Vercel"] = "OK" }
            } catch {}
        }
    }
}

# --- SUPABASE ---
Write-Host ""
Write-Separador
Write-Info "Supabase..."
try {
    $ss = (Invoke-ForjaTool supabase projects list 2>&1) | Out-String
    if ($LASTEXITCODE -eq 0 -and $ss -match "Name|ID" -and $ss -notmatch "error|not logged") {
        Write-OK "Supabase: Conectado"
        $conexiones["Supabase"] = "OK"
    } else { throw }
} catch {
    Write-Warn "Supabase: No conectado"
    $conexiones["Supabase"] = "PENDIENTE"
    if (Get-Command supabase -ErrorAction SilentlyContinue) {
        Write-Host ""
        Write-Host "  PostgreSQL, autenticacion y storage: supabase login" -ForegroundColor White
        Write-Host ""
        if (Ask-SN "Conectar Supabase ahora? (se abre el navegador)") {
            Write-Host ""
            Invoke-ForjaTool supabase login
            try {
                $sc = (Invoke-ForjaTool supabase projects list 2>&1) | Out-String
                if ($LASTEXITCODE -eq 0 -and $sc -match "Name|ID") { Write-OK "Supabase conectado!"; $conexiones["Supabase"] = "OK" }
            } catch {}
        }
    }
}

# --- SNYK ---
Write-Host ""
Write-Separador
Write-Info "Snyk..."
$conexiones['Snyk'] = 'PENDIENTE'
if (Get-Command snyk -ErrorAction SilentlyContinue) {
    if (Test-SnykAuth) { Write-OK 'Snyk: conectado'; $conexiones['Snyk'] = 'OK' }
    elseif (Ask-SN 'Conectar Snyk por navegador (OAuth)?') {
        Invoke-ForjaTool snyk auth
        if ($LASTEXITCODE -eq 0 -and (Test-SnykAuth)) {
            Write-OK 'Snyk conectado!'; $conexiones['Snyk'] = 'OK'
        } else { Write-Warn 'No se pudo verificar Snyk. Revisa snyk auth en una terminal nueva.' }
    }
} else { Write-Warn 'Snyk no disponible.' }

# --- DOCKER ---
Write-Host ""
Write-Separador
Write-Info "Docker..."
try {
    $ds = (docker info 2>&1) | Out-String
    if ($LASTEXITCODE -eq 0 -and $ds -match "Server Version") { Write-OK "Docker: Funcionando"; $conexiones["Docker"] = "OK" } else { throw }
} catch {
    Write-Warn "Docker: No esta corriendo"
    $conexiones["Docker"] = "PENDIENTE"
    Write-Host ""
    Write-Host "  Abri Docker Desktop y espera a que diga 'Docker is running'." -ForegroundColor White
    Write-Host "  Si recien lo instalaste, primero reinicia la PC." -ForegroundColor White
}

# ============================================================
#  ESTADO FINAL DE CONEXIONES
# ============================================================
Write-Host ""
Write-Host ""
Write-Section "============================================================"
Write-Section "  ESTADO FINAL DE CONEXIONES"
Write-Section "============================================================"
Write-Host ""

$pendientes = 0
foreach ($key in @("GitHub CLI","Claude MCP","Netlify","Vercel","Supabase","Snyk","Docker")) {
    $val = $conexiones[$key]
    if ($val -eq "OK") {
        Write-Host "  [OK] $key" -ForegroundColor Green
    } elseif ($val -like 'OPCIONAL*') {
        Write-Dim "$key - $val"
    } else {
        Write-Host "  [!!] $key - PENDIENTE" -ForegroundColor Red
        $pendientes++
    }
}

Write-Host ""
Write-Section "============================================================"

if ($pendientes -gt 0) {
    Write-Host ""
    Write-Warn "$pendientes servicio(s) pendiente(s) de vincular."
    Write-Warn "Volve a correr este script para verificar las conexiones."
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "  *** TODAS LAS CONEXIONES ESTAN ACTIVAS ***" -ForegroundColor Green
    Write-Host "  Las conexiones verificadas estan disponibles. Revisa tambien el resumen de instalacion." -ForegroundColor Green
    Write-Host ""
}

# ============================================================
#  PRIMEROS PASOS
# ============================================================
Write-Host ""
Write-Section "============================================================"
Write-Section "  PRIMEROS PASOS CON CLAUDE CODE"
Write-Section "============================================================"
Write-Host ""
Write-Host "  1. Abre una terminal nueva y ve a tu proyecto:" -ForegroundColor White
Write-Host "       cd C:\ruta\a\mi-proyecto" -ForegroundColor Green
Write-Host ""
Write-Host "  2. Inicia el agente elegido:" -ForegroundColor White
Write-Host "       claude | codex | agy | Cursor Agent" -ForegroundColor Green
Write-Host ""
Write-Host "  3. En la primera sesion, tu agente lee el proyecto y propone" -ForegroundColor White
Write-Host "     mejoras. Podes empezar con:" -ForegroundColor White
Write-Host '       "Hace un audit de este proyecto y listame que mejorar"' -ForegroundColor Green
Write-Host ""
Write-Dim     "  Recursos:"
Write-Dim     "    Docs: https://docs.anthropic.com/claude-code"
Write-Dim     "    Issues: https://github.com/anthropics/claude-code/issues"
Write-Dim     "    Actualizaciones de este script:"
Write-Dim     "    https://github.com/ragustingarcia/la-forja-del-desarrollador"
Write-Host ""

# ============================================================
#  CIERRE
# ============================================================
Write-Section "============================================================"
Write-Host ""
Write-Host "  La Forja del Desarrollador $VERSION" -ForegroundColor Yellow
Write-Dim   "  by Rodo Agustin Garcia  |  ragustingarcia.com"
Write-Host ""
Write-Section "  La forja termino. Es hora de construir."
Write-Host ""
Write-Section "============================================================"
Write-Host ""
Read-Host "  Presiona ENTER para cerrar"

if (@($status.Values | Where-Object { $_ -match '^(ERROR|PENDIENTE)' }).Count -gt 0) { exit 1 }; exit 0
