<# : batch portion
@echo off
setlocal DisableDelayedExpansion
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

$VERSION = "v6.1"
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
$ForjaSkillsRevision = '39204a10fc5ce3027a3180cc69446266f9cefe7a'
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
    try { $o = (npm list -g $pkg --depth=0 2>&1) | Out-String; if ($LASTEXITCODE -eq 0 -and $o -match ([regex]::Escape($pkg) + "@")) { return $true } } catch {}
    return $false
}
function Test-WingetPkg { param($id)
    try { $o = (winget list --id $id --exact --source winget --accept-source-agreements 2>&1) | Out-String; if ($LASTEXITCODE -eq 0 -and $o -match [regex]::Escape($id)) { return $true } } catch {}
    return $false
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
    npm install -g $pkg --loglevel verbose 2>&1 | ForEach-Object { Write-Host "  $_" }
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
function New-ForjaWorkspace {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { throw 'LOCALAPPDATA no disponible.' }
    $base = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Forja\Staging'))
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
    $output = (winget list --id $Id --exact --source winget --upgrade-available --accept-source-agreements 2>&1) | Out-String
    $code = $LASTEXITCODE
    if ($code -eq -1978335189 -or $code -eq -1978335212) { return 'aldia' }
    if ($code -ne 0) { return 'error' }
    if ($output -match ('(?m)(?<!\S)' + [regex]::Escape($Id) + '(?=\s|$)')) { return 'update' }
    # Un resultado vacio/desconocido con exit 0 NO demuestra estar actualizado.
    return 'error'
}
function Test-SnykAuth {
    # No consultar config get api: devuelve el secreto y no contempla OAuth.
    $null = & snyk whoami --experimental 2>&1
    return ($LASTEXITCODE -eq 0)
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

    $updOK = 0; $updAlDia = 0; $updSaltado = 0; $updError = 0
    $env:PATH = "$env:PATH;$env:ProgramFiles\nodejs;$env:APPDATA\npm;$env:USERPROFILE\.local\bin"

    # winget devuelve 0x8A15002B (-1978335189) cuando NO hay update aplicable;
    # es la senal confiable, independiente del idioma de Windows
    $WINGET_SIN_UPDATE = -1978335189

    # Pre-chequea si hay update; solo si lo hay corre winget upgrade
    # mostrando su barra de progreso nativa en vivo
    function Invoke-WingetUpdate { param($id, $nombre)
        $state = Get-WingetUpdateState $id
        if ($state -eq 'error') { Write-Warn "${nombre}: no se pudo consultar la actualizacion."; return 'error' }
        if ($state -eq 'aldia') {
            Write-OK "$nombre ya esta al dia."
            return "aldia"
        }
        Write-Dim "vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv"
        winget upgrade --id $id --exact --source winget --accept-package-agreements --accept-source-agreements 2>&1 | ForEach-Object { Write-Host "  $_" }
        $codigo = $LASTEXITCODE
        Write-Dim "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
        if ($codigo -eq $WINGET_SIN_UPDATE) { Write-OK "$nombre ya esta al dia."; return "aldia" }
        if ($codigo -eq 0) { Write-OK "$nombre actualizado."; return "ok" }
        Write-Warn "${nombre}: no se pudo actualizar. Si esta abierto, cerralo y reintenta."
        return "error"
    }

    # Actualiza un paquete npm global solo si la version instalada
    # difiere de la ultima publicada (evita reinstalaciones de minutos)
    function Invoke-NpmUpdate { param($pkg, $nombre)
        $vLocal = $null
        $lista = (npm list -g $pkg --depth=0 2>&1) | Out-String
        if ($LASTEXITCODE -ne 0) { Write-Warn "${nombre}: fallo la consulta local de npm."; return 'error' }
        if ($lista -match ([regex]::Escape($pkg) + "@(\S+)")) { $vLocal = $Matches[1] }
        $vUltima = ((npm view $pkg version 2>&1) | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $vUltima -notmatch '^\d+\.\d+\.\d+([+-][0-9A-Za-z.-]+)?$') {
            Write-Warn "${nombre}: no se pudo consultar una version valida del registro."; return 'error'
        }
        if ($vLocal -and $vUltima -and $vLocal -eq $vUltima) {
            Write-OK "$nombre ya esta al dia ($vLocal)."
            return "aldia"
        }
        Write-Dim "vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv"
        npm install -g "$pkg@$vUltima" 2>&1 | ForEach-Object { Write-Host "  $_" }
        $codigo = $LASTEXITCODE
        Write-Dim "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
        if ($codigo -eq 0) { Write-OK "$nombre actualizado a la ultima version."; return "ok" }
        Write-Warn "${nombre}: error al actualizar."
        return "error"
    }
    function Add-UpdResultado { param($r)
        switch ($r) {
            "ok"    { $script:updOK++ }
            "aldia" { $script:updAlDia++ }
            "error" { $script:updError++ }
        }
    }

    # El lanzador usa Windows PowerShell 5.1, por lo que pwsh no queda bloqueado.
    Write-Info 'PowerShell 7...'
    if (Test-WingetPkg 'Microsoft.PowerShell') {
        Add-UpdResultado (Invoke-WingetUpdate 'Microsoft.PowerShell' 'PowerShell 7')
    } else { Write-Dim 'PowerShell 7 no instalado via winget. Saltado.'; $updSaltado++ }
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
        if (Test-WingetPkg $id) {
            Add-UpdResultado (Invoke-WingetUpdate $id $nombre)
        } else {
            Write-Dim "$nombre no esta instalado. Saltado."
            $updSaltado++
        }
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
        $updSaltado++
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
            $updError++
        }
    } else {
        Write-Dim "Supabase CLI no esta instalado. Saltado."
        $updSaltado++
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
            $updAlDia++
        } else {
            Write-Warn "WSL: la actualizacion fallo por ambas vias. Reintenta mas tarde"
            Write-Warn "o corre manualmente: wsl --update --web-download"
            $updError++
        }
    } else {
        Write-Dim "WSL no esta instalado. Saltado."
        $updSaltado++
    }
    Write-Host ""

    # --- Claude Code CLI (updater propio: cubre instalacion nativa y npm) ---
    Write-Info "Claude Code CLI..."

    # Deteccion de doble instalacion (npm global + nativa). Tener las dos
    # confunde al PATH y al updater; Anthropic recomienda la nativa.
    $claudeNpm    = (Test-Path "$env:APPDATA\npm\claude*") -or (Test-Path "$env:APPDATA\npm\node_modules\@anthropic-ai\claude-code")
    $claudeNativo = (Test-Path "$env:USERPROFILE\.local\bin\claude.exe") -or (Test-Path "$env:USERPROFILE\.local\share\claude")
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
            npm uninstall -g "@anthropic-ai/claude-code" 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Warn 'npm no pudo desinstalar Claude Code; no se borraron archivos manualmente.'
                $updError++
            } else {
                Write-OK 'Desinstalador npm completado. Verifica claude --version en una terminal nueva.'
            }
            Write-Host ""
        } else {
            Write-Dim "Se mantienen las dos instalaciones."
            Write-Host ""
        }
    }

    if (Get-Command claude -ErrorAction SilentlyContinue) {
        Write-Dim "vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv"
        claude update
        $codigo = $LASTEXITCODE
        Write-Dim "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
        if ($codigo -eq 0) { Write-OK "Claude Code CLI al dia."; $updOK++ }
        else { Write-Warn "Claude Code CLI: proba 'claude update' en una terminal nueva."; $updError++ }
    } else {
        Write-Dim "Claude Code CLI no esta instalado. Saltado."
        $updSaltado++
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
                $updSaltado++
            }
            Write-Host ""
        }
    } else {
        Write-Warn "npm no disponible: se saltean los paquetes npm."
        Write-Host ""
    }

    # --- Librerias Python ---
    Write-Info "Librerias Python..."
    if (Test-PipReal) {
        # -q oculta el listado "Requirement already satisfied"; solo muestra cambios reales
        python -m pip install --upgrade -q fastapi "uvicorn[standard]" python-multipart pdfplumber requests
        $codigo = $LASTEXITCODE
        if ($codigo -eq 0) { Write-OK "Librerias Python al dia."; $updAlDia++ }
        else { Write-Warn "Librerias Python: error al actualizar."; $updError++ }
    } else {
        Write-Dim "pip no disponible. Saltado."
        $updSaltado++
    }

    # --- Resumen ---
    Write-Host ""
    Write-Section "============================================================"
    Write-Section "  RESUMEN DE ACTUALIZACION"
    Write-Section "============================================================"
    Write-Host ""
    Write-Host "  Actualizados:    $updOK" -ForegroundColor Green
    Write-Host "  Ya al dia:       $updAlDia" -ForegroundColor Green
    Write-Host "  Saltados:        $updSaltado" -ForegroundColor DarkGray

    if ($updError -gt 0) {
        Write-Host "  Con errores:     $updError" -ForegroundColor Yellow
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

    if ($updError -gt 0) { exit 1 }; exit 0
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
    $pnpmv = (pnpm --version 2>&1) | Out-String
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
            npm install -g pnpm 2>&1 | Out-Null
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

if (Test-FastapiInstalled) {
    Write-OK "Librerias ya instaladas."
    $status["pylibs"] = "OK"
} else {
    $pc = $null
    if (Test-PipReal) { $pc = "python -m pip" }

    if ($pc) {
        Write-Info "[INSTALANDO] Librerias..."
        Write-Dim "vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv"
        python -m pip install fastapi "uvicorn[standard]" python-multipart pdfplumber requests 2>&1 | ForEach-Object { Write-Host "  $_" }
        Write-Dim "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
        if ($LASTEXITCODE -eq 0 -and (Test-FastapiInstalled)) { Write-OK "Instaladas."; $status["pylibs"] = "OK" }
        else { Write-Err "Error."; $status["pylibs"] = "ERROR" }
    } else {
        Write-Warn "pip no disponible. Reinicia y corre el script de nuevo."
        $status["pylibs"] = "PENDIENTE"
        $necesitaReabrir = $true
    }
}

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
        npm install -g @anthropic-ai/claude-code --loglevel verbose 2>&1 | ForEach-Object { Write-Host "  $_" }
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
            $cv = (claude --version 2>&1) | Out-String
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
    $sbv = (supabase --version 2>&1) | Out-String
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
            npm install -g supabase 2>&1 | Out-Null
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
    $ns = (netlify status 2>&1) | Out-String
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
            netlify login
            try {
                $nc = (netlify status 2>&1) | Out-String
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
    $vs = (vercel whoami 2>&1) | Out-String
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
            vercel login
            try {
                $vc = (vercel whoami 2>&1) | Out-String
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
    $ss = (supabase projects list 2>&1) | Out-String
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
            supabase login
            try {
                $sc = (supabase projects list 2>&1) | Out-String
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
        snyk auth
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
