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
#  Setup completo para desarrollar con Claude Code en Windows
#  by Rodolfo Agustin Garcia  |  ragustingarcia.com
#  https://github.com/ragustingarcia/la-forja-del-desarrollador
# ============================================================

$VERSION = "v6.1.3"
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
$ForjaSkillsRevision = 'c794d9488a1e8274af08b5c90f9dcfa96ec73580'
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
function Get-ForjaToolPath { param(
    [ValidateSet('npm','pnpm','claude','netlify','vercel','supabase','snyk')][string]$Name
)
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
        winget install --id $id --exact --source winget --accept-package-agreements --accept-source-agreements 2>&1 | ForEach-Object { Write-Host "  $_" }
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
    & git -C $repoPath -c core.hooksPath=NUL -c protocol.file.allow=never fetch --quiet --depth=1 --no-tags -- $Repository $Revision 2>&1 | Out-Null
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
    $commands=@{ 'netlify-cli'='netlify'; 'vercel'='vercel'; 'snyk'='snyk'; 'supabase'='supabase'; '@anthropic-ai/claude-code'='claude'; 'pnpm'='pnpm' }
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
    Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 120 -ErrorAction Stop | Out-Null
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
    try { & $Executable @pythonArguments 2>&1 | ForEach-Object { $_.ToString() }; $code=$LASTEXITCODE }
    catch { Write-Warn "No se pudo ejecutar Python ($($_.Exception.GetType().Name))."; $code=-1 }
    $global:LASTEXITCODE=$code
}
function Invoke-ForjaPythonLibraries { param([switch]$Update,[switch]$CheckShared)
    $result=[pscustomobject]@{ State='error'; SharedConflict=$false; Environment=$null }
    $base=Get-Command python.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $base) { Write-Warn 'Python no disponible.'; $result.State='saltado'; return $result }
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { Write-Warn 'LOCALAPPDATA no disponible.'; return $result }
    $expectedVenv=Join-Path $env:LOCALAPPDATA 'Forja\Python\venv'
    if ($CheckShared -or -not (Test-Path -LiteralPath $expectedVenv)) {
        $shared=Invoke-ForjaPython $base.Source -m pip check 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            $result.SharedConflict=$true
            Write-Warn 'El Python compartido tiene dependencias incompatibles o no pudo verificarse. La Forja no lo modifica.'
            $shared.Trim() -split '\r?\n' | Select-Object -First 8 | ForEach-Object { Write-Dim $_ }
        }
    }
    try {
        if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { throw 'LOCALAPPDATA no disponible' }
        $venv=Join-Path $env:LOCALAPPDATA 'Forja\Python\venv'
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
        $installArguments+=@('fastapi','uvicorn[standard]','python-multipart','pdfplumber','requests')
        Invoke-ForjaPython $python @installArguments 2>&1 | ForEach-Object { Write-Host "  $_" }
        if ($LASTEXITCODE -ne 0) { throw 'pip no pudo instalar las librerias' }
        $check=Invoke-ForjaPython $python -m pip check 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { Write-Warn $check.Trim(); throw 'Las dependencias del entorno no son compatibles' }
        $null=Invoke-ForjaPython $python -m pip show fastapi uvicorn python-multipart pdfplumber requests 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'Faltan librerias requeridas' }
        $after=Invoke-ForjaPython $python -m pip list --format=json --disable-pip-version-check 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo verificar la version instalada' }
        $null=$after | ConvertFrom-Json -ErrorAction Stop
        $imports=Invoke-ForjaPython $python -c 'import fastapi, uvicorn, multipart, pdfplumber, requests' 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { Write-Warn $imports.Trim(); throw 'Las librerias no se pueden cargar en ese interprete' }
        $result.State='ok'
        if ($before.Trim() -eq $after.Trim()) { $result.State='aldia' }
        Write-OK "Librerias Python verificadas en el entorno de la Forja: $python"
        Write-Dim "Para usarlas, ejecuta ese Python directamente; no hace falta activar scripts de PowerShell."
    } catch { Write-Warn "Librerias Python: $($_.Exception.Message)."; $result.State='error' }
    return $result
}

$T = 22
$status = @{}
$necesitaReabrir = $false

# ============================================================
#  BIENVENIDA
# ============================================================
Clear-Host
Write-Host ""
Write-Section "============================================================"
Write-Host ""
Write-Host "    FORJA DEL DESARROLLADOR $VERSION" -ForegroundColor Yellow
Write-Host "    Setup completo para desarrollar con Claude Code" -ForegroundColor White
Write-Host ""
Write-Dim   "    by Rodo Agustin Garcia  |  ragustingarcia.com"
Write-Host ""
Write-Section "============================================================"
Write-Host ""
Write-Host '  "Todo gran proyecto empieza con las herramientas correctas."'
Write-Host ""
Write-Section "============================================================"
Write-Host ""
Write-Host "  --- INFRAESTRUCTURA (1-4) ---" -ForegroundColor White
Write-Host "    [ 1] winget        [ 2] PowerShell 7"
Write-Host "    [ 3] WSL           [ 4] Git"
Write-Host ""
Write-Host "  --- LENGUAJES (5-8) ---" -ForegroundColor White
Write-Host "    [ 5] Node.js LTS   [ 6] pnpm"
Write-Host "    [ 7] Python 3.13   [ 8] Libs Python"
Write-Host ""
Write-Host "  --- DESARROLLO (9-12) ---" -ForegroundColor White
Write-Host "    [ 9] VS Code       [10] Claude Code CLI"
Write-Host "    [11] Claude App    [12] GitHub CLI"
Write-Host ""
Write-Host "  --- SERVICIOS (13-16) ---" -ForegroundColor White
Write-Host "    [13] Docker        [14] mongosh"
Write-Host "    [15] Ollama        [16] FFmpeg"
Write-Host ""
Write-Host "  --- DEPLOY Y SEGURIDAD (17-20) ---" -ForegroundColor White
Write-Host "    [17] Netlify CLI   [18] Vercel CLI"
Write-Host "    [19] Supabase CLI  [20] Snyk CLI"
Write-Host ""
Write-Host "  --- SKILLS (21) ---" -ForegroundColor White
Write-Host "    [21] Skills de Claude Code (pack Forja + oficiales)"
Write-Host ""
Write-Host "  --- VINCULACIONES (22) ---" -ForegroundColor White
Write-Host "    [22] Asistente de conexion de servicios"
Write-Host ""
Write-Section "============================================================"
Write-Host ""
Write-Host "  MODO DE EJECUCION:" -ForegroundColor White
Write-Host ""
Write-Host "    [1] Setup completo    - instalar todo y vincular servicios" -ForegroundColor Green
Write-Host "    [2] Solo actualizar   - actualizar lo que ya esta instalado" -ForegroundColor Cyan
Write-Host ""
Write-Host "    [3] Diagnostico       - rutas de herramientas, sin ejecutar instaladores" -ForegroundColor Cyan
Write-Host "    [0] Salir (por defecto)" -ForegroundColor DarkGray
$modoSel = Read-Host "  Elegi 1, 2 o 3 (ENTER = salir)"
if ($modoSel -eq '3') {
    foreach ($tool in @('winget','pwsh','wsl','git','node','npm','python','pip','claude','gh','docker','snyk')) {
        $command = Get-Command $tool -ErrorAction SilentlyContinue
        if ($command) { Write-Info "$tool : $($command.Source)" } else { Write-Dim "$tool : no encontrado" }
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
            winget upgrade --id $id --exact --source winget --accept-package-agreements --accept-source-agreements 2>&1 | ForEach-Object { $installerOutput.Add($_.ToString()); Write-Host "  $_" }
            $codigo = $LASTEXITCODE
        } catch { Write-Warn "${nombre}: no se pudo iniciar la actualizacion."; return 'error' }
        if ($codigo -eq $WINGET_SIN_UPDATE) { Write-OK "$nombre sin actualizacion aplicable (instalada: $($info.Version))."; return 'aldia' }
        if ($codigo -eq 0) {
            $script:ForjaWingetInventory = $null
            $after = Get-WingetPackageInfo $id
            if ($after.State -eq 'installed' -and $after.Version -eq $info.Available) {
                Write-OK "$nombre actualizado. Version instalada: $($after.Version)."; return 'ok'
            }
            Write-Warn "$nombre : el instalador termino, pero no se pudo confirmar la version esperada. Volve a verificar."
            return 'error'
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

    # --- Python (el id de winget incluye la version: 3.13, 3.12, etc.) ---
    Write-Info "Python..."
    $pyId = $null
    foreach ($v in @("3.13","3.12","3.11","3.10")) {
        if (Test-WingetPkg "Python.Python.$v") { $pyId = "Python.Python.$v"; break }
    }
    if ($pyId) {
        Add-UpdResultado (Invoke-WingetUpdate $pyId "Python")
    } else {
        Write-Dim "Python no esta instalado via winget. Saltado."
        $script:updSaltado++
    }
    Write-Host ""

    # --- Supabase CLI (winget o npm, segun como se instalo) ---
    Write-Info "Supabase CLI..."
    if (Test-WingetPkg "Supabase.CLI") {
        Add-UpdResultado (Invoke-WingetUpdate "Supabase.CLI" "Supabase CLI")
    } elseif (Get-Command supabase -ErrorAction SilentlyContinue) {
        if ((Get-Command npm -ErrorAction SilentlyContinue) -and (Test-NpmPkg "supabase")) {
            Add-UpdResultado (Invoke-NpmUpdate "supabase" "Supabase CLI")
        } else {
            Write-Warn "Supabase CLI instalado por otro medio: actualizalo manualmente."
            $script:updError++
        }
    } else {
        Write-Dim "Supabase CLI no esta instalado. Saltado."
        $script:updSaltado++
    }
    Write-Host ""

    # --- WSL ---
    Write-Info "WSL..."
    cmd /c "wsl --status >nul 2>&1"
    if ($LASTEXITCODE -eq 0) {
        Write-Dim "vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv"
        cmd /c "wsl --update"
        $codigo = $LASTEXITCODE
        if ($codigo -ne 0) {
            # El CDN de Microsoft Store a veces devuelve 403 (Wsl/UpdatePackage/
            # 0x80190193); --web-download baja desde GitHub y lo esquiva
            Write-Warn "Fallo la descarga desde Microsoft Store. Reintentando desde GitHub..."
            cmd /c "wsl --update --web-download"
            $codigo = $LASTEXITCODE
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
    try {
        $wslExe = Join-Path $env:SystemRoot 'System32\wsl.exe'
        $process = Start-Process -FilePath $wslExe -ArgumentList '--install','--no-distribution' -Verb RunAs -Wait -PassThru -ErrorAction Stop
        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
            Write-Warn 'WSL: instalacion aceptada; reinicia y verifica wsl --status.'
            $status['wsl'] = 'PENDIENTE - REINICIAR Y VERIFICAR'
            $necesitaReabrir = $true
        } else { throw 'Fallo la instalacion.' }
    } catch { Write-Err 'WSL no se instalo o se cancelo UAC.'; $status['wsl'] = 'ERROR' }
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
Write-Titulo 7 $T "Python 3.13" "Lenguaje para backend e IA"
Write-Host "  Popular para IA, automatizacion y web."
Write-Host "  Ej: python script.py | pip install fastapi"
Write-Host ""
Write-Info "Verificando..."
Write-Host ""

$pyPaths = @(
    "$env:LOCALAPPDATA\Programs\Python\Python313",
    "$env:LOCALAPPDATA\Programs\Python\Python313\Scripts",
    "$env:ProgramFiles\Python313",
    "$env:ProgramFiles\Python313\Scripts"
)
foreach ($p in $pyPaths) { if ((Test-Path $p) -and ($env:PATH -notlike "*$p*")) { $env:PATH = "$p;$env:PATH" } }

$pv = Test-PythonReal
if ($pv) {
    Write-OK "Python ($pv)."
    $status["python"] = "OK"
} else {
    if (Install-Winget "Python.Python.3.13" "Python 3.13") {
        Write-OK "Instalado."
        foreach ($p in $pyPaths) { if ((Test-Path $p) -and ($env:PATH -notlike "*$p*")) { $env:PATH = "$p;$env:PATH" } }
        if (Test-PythonReal) { $status["python"] = "OK" }
        else { $status["python"] = "OK - REABRIR"; $necesitaReabrir = $true }
    } else {
        Write-Err "Error instalando Python 3.13."
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

if (Get-Command supabase -ErrorAction SilentlyContinue) {
    $sbv = (Invoke-ForjaTool supabase --version 2>&1) | Out-String
    Write-OK "Supabase CLI ($($sbv.Trim()))."
    $status["supabase"] = "OK"
} else {
    if (Install-Winget "Supabase.CLI" "Supabase CLI") {
        Write-OK "Instalado."
        $status["supabase"] = "OK"
        $necesitaReabrir = $true
    } else {
        $nm = Get-Command npm -ErrorAction SilentlyContinue
        if ($nm) {
            Write-Info "[INSTALANDO] Supabase CLI via npm (fallback)..."
            Invoke-ForjaTool npm install -g supabase 2>&1 | Out-Null
            if (Get-Command supabase -ErrorAction SilentlyContinue) {
                Write-OK "Instalado via npm."
                $status["supabase"] = "OK"
            } else {
                Write-Err "Error instalando Supabase CLI."
                $status["supabase"] = "ERROR"
            }
        } else {
            Write-Warn "npm no disponible."
            $status["supabase"] = "PENDIENTE"
            $necesitaReabrir = $true
        }
    }
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

# ============================================================
#  [21] SKILLS DE CLAUDE CODE
# ============================================================
Write-Titulo 21 $T "Skills de Claude Code" "Capacidades que se cargan bajo demanda"
Write-Host "  Una skill le ensena a Claude Code una capacidad nueva y se"
Write-Host "  carga SOLO cuando se usa: no gasta tokens el resto del tiempo."
Write-Host "  Ej: /bat-installer-builder | skill-creator | docx, pdf, xlsx"
Write-Host ""

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

# ============================================================
#  RESUMEN DE INSTALACION
# ============================================================
Write-Host ""
Write-Host ""
Write-Section "============================================================"
Write-Section "  RESUMEN DE INSTALACION (Pasos 1-21)"
Write-Section "============================================================"
Write-Host ""

$items = @(
    @("winget",    "winget"),
    @("pwsh",      "PowerShell 7"),
    @("wsl",       "WSL"),
    @("git",       "Git"),
    @("node",      "Node.js LTS"),
    @("pnpm",      "pnpm"),
    @("python",    "Python 3.13"),
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
Write-Host "  2. Inicia Claude Code:" -ForegroundColor White
Write-Host "       claude" -ForegroundColor Green
Write-Host ""
Write-Host "  3. En la primera sesion, Claude lee el proyecto y propone" -ForegroundColor White
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

if (@($status.Values | Where-Object { $_ -match '^ERROR' }).Count -gt 0) { exit 1 }; exit 0
