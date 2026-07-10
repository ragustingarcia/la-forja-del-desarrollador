<# : batch portion
@echo off
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo.
    echo   [!] Se requieren privilegios de Administrador.
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    del "%temp%\getadmin.vbs"
    exit /B
)
pushd "%CD%"
CD /D "%~dp0"
copy "%~f0" "%temp%\forja_setup.ps1" >nul
pwsh -NoProfile -ExecutionPolicy Bypass -File "%temp%\forja_setup.ps1"
del "%temp%\forja_setup.ps1" >nul 2>&1
echo.
echo   Presiona cualquier tecla para cerrar...
pause >nul
exit /b
: end batch / begin PowerShell #>

# ============================================================
#  FORJA DEL DESARROLLADOR
#  Setup completo para desarrollar con Claude Code en Windows
#  by Rodolfo Agustin Garcia  |  ragustingarcia.com
#  https://github.com/ragustingarcia/la-forja-del-desarrollador
# ============================================================

$VERSION = "v5.7"
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
    try { $o = (python --version 2>&1) | Out-String; if ($o -match "Python \d+\.\d+\.\d+") { return $o.Trim() } } catch {}
    return $null
}
function Test-PipReal {
    try { $o = (pip --version 2>&1) | Out-String; if ($o -match "pip \d+") { return $true } } catch {}
    return $false
}
function Test-FastapiInstalled {
    try { $o = (pip show fastapi 2>&1) | Out-String; if ($o -match "Name: fastapi") { return $true } } catch {}
    try { $o = (python -m pip show fastapi 2>&1) | Out-String; if ($o -match "Name: fastapi") { return $true } } catch {}
    return $false
}
function Test-NpmPkg { param($pkg)
    try { $o = (npm list -g $pkg --depth=0 2>&1) | Out-String; if ($o -match $pkg) { return $true } } catch {}
    return $false
}
function Test-WingetPkg { param($id)
    try { $o = (winget list --id $id --accept-source-agreements 2>&1) | Out-String; if ($o -match $id) { return $true } } catch {}
    return $false
}
function Install-Winget { param($id, $nombre)
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Info "[INSTALANDO] $nombre via winget..."
        Write-Host ""
        winget install --id $id --source winget --accept-package-agreements --accept-source-agreements
        return ($LASTEXITCODE -eq 0)
    }
    return $false
}
function Install-Npm { param($pkg, $nombre)
    Write-Info "[INSTALANDO] $nombre via npm..."
    Write-Dim "vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv"
    npm install -g $pkg --loglevel verbose 2>&1 | ForEach-Object { Write-Host "  $_" }
    Write-Dim "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
    return (Test-NpmPkg $pkg)
}
function Ask-SN { param($pregunta)
    $r = Read-Host "  $pregunta (S/N)"
    return ($r -match "^[sS]")
}
function Write-Separador { Write-Dim "------------------------------------------------------------" }

$T = 21
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
Write-Host "  --- VINCULACIONES (21) ---" -ForegroundColor White
Write-Host "    [21] Asistente de conexion de servicios"
Write-Host ""
Write-Section "============================================================"
Write-Host ""
Write-Host "  MODO DE EJECUCION:" -ForegroundColor White
Write-Host ""
Write-Host "    [1] Setup completo    - instalar todo y vincular servicios" -ForegroundColor Green
Write-Host "    [2] Solo actualizar   - actualizar lo que ya esta instalado" -ForegroundColor Cyan
Write-Host ""
$modoSel = Read-Host "  Elegi una opcion (ENTER = 1)"

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
    $updatePwshAlCerrar = $false
    $env:PATH = "$env:PATH;$env:ProgramFiles\nodejs;$env:APPDATA\npm;$env:USERPROFILE\.local\bin"

    # winget devuelve 0x8A15002B (-1978335189) cuando NO hay update aplicable;
    # es la senal confiable, independiente del idioma de Windows
    $WINGET_SIN_UPDATE = -1978335189

    # Pre-chequea si hay update; solo si lo hay corre winget upgrade
    # mostrando su barra de progreso nativa en vivo
    function Invoke-WingetUpdate { param($id, $nombre)
        $chk = (winget list --id $id --upgrade-available --accept-source-agreements 2>&1) | Out-String
        if ($chk -notmatch [regex]::Escape($id)) {
            Write-OK "$nombre ya esta al dia."
            return "aldia"
        }
        Write-Dim "vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv"
        winget upgrade --id $id --source winget --accept-package-agreements --accept-source-agreements
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
        if ($lista -match ([regex]::Escape($pkg) + "@(\S+)")) { $vLocal = $Matches[1] }
        $vUltima = ((npm view $pkg version 2>&1) | Out-String).Trim()
        if ($vLocal -and $vUltima -and $vLocal -eq $vUltima) {
            Write-OK "$nombre ya esta al dia ($vLocal)."
            return "aldia"
        }
        Write-Dim "vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv"
        npm install -g "$pkg@latest"
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

    # --- PowerShell 7 (caso especial: este script corre EN pwsh) ---
    # No se puede actualizar un programa mientras esta en uso, y pwsh
    # siempre lo esta aca. Se verifica si hay update y se difiere al cierre.
    Write-Info "PowerShell 7..."
    if (Test-WingetPkg "Microsoft.PowerShell") {
        $pwshChk = (winget list --id Microsoft.PowerShell --upgrade-available --accept-source-agreements 2>&1) | Out-String
        if ($pwshChk -match "Microsoft\.PowerShell") {
            Write-Warn "PowerShell 7 tiene actualizacion, pero esta en uso (este script corre en el)."
            Write-Info "Se va a actualizar en una ventana aparte al cerrar este script."
            $updatePwshAlCerrar = $true
        } else {
            Write-OK "PowerShell 7 ya esta al dia."
            $updAlDia++
        }
    } else {
        Write-Dim "PowerShell 7 no instalado via winget. Saltado."
        $updSaltado++
    }
    Write-Host ""

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
        Write-Dim "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
        if ($codigo -eq 0) {
            # wsl --update devuelve 0 haya o no update: contarlo como "al dia"
            Write-OK "WSL al dia (se actualiza solo si hay version nueva)."
            $updAlDia++
        } else {
            Write-Warn "WSL: la actualizacion fallo (suele ser un error transitorio"
            Write-Warn "de red o del servidor de Microsoft). Reintenta mas tarde."
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
            # npm puede dejar shims sueltos si la instalacion estaba rota
            foreach ($s in @("claude","claude.cmd","claude.ps1")) {
                Remove-Item "$env:APPDATA\npm\$s" -Force -ErrorAction SilentlyContinue
            }
            Remove-Item "$env:APPDATA\npm\node_modules\@anthropic-ai\claude-code" -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path "$env:APPDATA\npm\claude*") {
                Write-Warn "No se pudo eliminar del todo (hay una sesion de Claude Code abierta?)."
                Write-Warn "Cerra todo y volve a correr el modo actualizacion."
            } else {
                Write-OK "Instalacion npm eliminada."
                $cv = $null
                try { $cv = (claude --version 2>&1) | Out-String } catch {}
                if ($cv -match "\d+\.\d+") {
                    Write-OK "La instalacion nativa responde ($($cv.Trim()))."
                } else {
                    Write-Warn "Abri una terminal NUEVA y verifica con: claude --version"
                }
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
        pip install --upgrade -q fastapi "uvicorn[standard]" python-multipart pdfplumber requests
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
    if ($updatePwshAlCerrar) {
        Write-Host "  Al cerrar:       PowerShell 7 (en ventana aparte)" -ForegroundColor Cyan
    }
    if ($updError -gt 0) {
        Write-Host "  Con errores:     $updError" -ForegroundColor Yellow
        Write-Host ""
        Write-Warn "Los errores suelen ser programas abiertos (VS Code, Docker)."
        Write-Warn "Cerralos y volve a correr el modo actualizacion."
    }
    Write-Host ""
    Write-Section "============================================================"
    Write-Host ""
    Write-Host "  La Forja del Desarrollador $VERSION" -ForegroundColor Yellow
    Write-Dim   "  by Rodolfo Agustin Garcia  |  ragustingarcia.com"
    Write-Host ""
    Write-Section "============================================================"
    Write-Host ""
    if ($updatePwshAlCerrar) {
        Write-Info "Al presionar ENTER se abre una ventana que actualiza PowerShell 7"
        Write-Info "cuando este script termine. Cerra otras ventanas de pwsh si tenes."
        Write-Host ""
    }
    Read-Host "  Presiona ENTER para cerrar"
    if ($updatePwshAlCerrar) {
        # cmd no depende de pwsh: espera a que este proceso muera y actualiza
        Start-Process cmd -ArgumentList '/c', 'title Actualizando PowerShell 7 && echo Esperando a que cierre la Forja... && timeout /t 6 /nobreak >nul && winget upgrade --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements && echo. && echo Listo. PowerShell 7 actualizado. && pause'
    }
    exit
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
Write-Host "  Terminal avanzada de Microsoft. Este script corre en pwsh."
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
Write-Info "Configurando PowerShell 7 como terminal por defecto..."
reg add "HKCU\Console\%Startup" /v "DelegationConsole" /t REG_SZ /d "{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}" /f 2>&1 | Out-Null
reg add "HKCU\Console\%Startup" /v "DelegationTerminal" /t REG_SZ /d "{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}" /f 2>&1 | Out-Null
$wt = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if (Test-Path $wt) {
    try {
        $j = Get-Content $wt -Raw | ConvertFrom-Json
        $pp = $j.profiles.list | Where-Object { $_.source -eq 'Windows.Terminal.PowershellCore' } | Select-Object -First 1
        if (-not $pp) { $pp = $j.profiles.list | Where-Object { $_.name -match 'PowerShell' -and $_.commandline -match 'pwsh' } | Select-Object -First 1 }
        if ($pp) { $j.defaultProfile = $pp.guid; $j | ConvertTo-Json -Depth 100 | Set-Content $wt -Encoding UTF8; Write-OK "Perfil por defecto configurado." }
    } catch { Write-Warn "No se pudo configurar automaticamente el perfil de Windows Terminal." }
}

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
    Write-OK "WSL ya instalado."
    Write-Info "Actualizando WSL..."
    cmd /c "wsl --update 2>&1" | Out-Null
    Write-OK "WSL actualizado."
    $status["wsl"] = "OK"
} else {
    Write-Info "[INSTALANDO] WSL..."
    cmd /c "wsl --install --no-distribution 2>&1" | Out-Null
    cmd /c "wsl --update 2>&1" | Out-Null
    Write-OK "WSL instalado."
    Write-Warn "Requiere REINICIAR la PC para completar."
    $status["wsl"] = "OK - REINICIAR PC"
    $necesitaReabrir = $true
}

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
            if (Get-Command pnpm -ErrorAction SilentlyContinue) { Write-OK "Instalado via npm."; $status["pnpm"] = "OK" }
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

$ap = "$env:LOCALAPPDATA\Microsoft\WindowsApps"
$fp = Join-Path $ap "python.exe"; $fp3 = Join-Path $ap "python3.exe"
if (Test-Path $fp) {
    $fs = (Get-Item $fp -ErrorAction SilentlyContinue).Length
    if ($fs -and $fs -lt 20000) {
        Rename-Item $fp  "$fp.bak"  -Force -ErrorAction SilentlyContinue
        Rename-Item $fp3 "$fp3.bak" -Force -ErrorAction SilentlyContinue
    }
}
$pyPaths = @(
    "$env:LOCALAPPDATA\Programs\Python\Python313",
    "$env:LOCALAPPDATA\Programs\Python\Python313\Scripts",
    "$env:ProgramFiles\Python313",
    "$env:ProgramFiles\Python313\Scripts"
)
foreach ($p in $pyPaths) { if ((Test-Path $p) -and ($env:PATH -notlike "*$p*")) { $env:PATH = "$env:PATH;$p" } }

$pv = Test-PythonReal
if ($pv) {
    Write-OK "Python ($pv)."
    $status["python"] = "OK"
} else {
    if (Install-Winget "Python.Python.3.13" "Python 3.13") {
        Write-OK "Instalado."
        foreach ($p in $pyPaths) { if ((Test-Path $p) -and ($env:PATH -notlike "*$p*")) { $env:PATH = "$env:PATH;$p" } }
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
    if (Test-PipReal) { $pc = "pip" }
    elseif (Test-PythonReal) { $pc = "python -m pip" }

    if ($pc) {
        Write-Info "[INSTALANDO] Librerias..."
        Write-Dim "vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv"
        if ($pc -eq "pip") {
            pip install fastapi "uvicorn[standard]" python-multipart pdfplumber requests 2>&1 | ForEach-Object { Write-Host "  $_" }
        } else {
            python -m pip install fastapi "uvicorn[standard]" python-multipart pdfplumber requests 2>&1 | ForEach-Object { Write-Host "  $_" }
        }
        Write-Dim "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
        if (Test-FastapiInstalled) { Write-OK "Instaladas."; $status["pylibs"] = "OK" }
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
        if (Get-Command claude -ErrorAction SilentlyContinue) {
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
#  RESUMEN DE INSTALACION
# ============================================================
Write-Host ""
Write-Host ""
Write-Section "============================================================"
Write-Section "  RESUMEN DE INSTALACION (Pasos 1-20)"
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
    @("snyk",      "Snyk CLI")
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
#  [21] ASISTENTE DE VINCULACION
# ============================================================
Write-Host ""
Write-Section "============================================================"
Write-Section "  [21/$T] Asistente de vinculacion de servicios"
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
    if ($ghs -match "Logged in") { Write-OK "GitHub CLI: Conectado"; $conexiones["GitHub CLI"] = "OK" } else { throw }
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
                if ($check -match "Logged in") { Write-OK "GitHub CLI conectado!"; $conexiones["GitHub CLI"] = "OK" }
            } catch {}
        }
    }
}

# --- CLAUDE MCP GITHUB ---
Write-Host ""
Write-Separador
Write-Info "Claude MCP — GitHub server..."
try {
    $mcp = (claude mcp list 2>&1) | Out-String
    if ($mcp -match "github") { Write-OK "Claude MCP GitHub: Configurado"; $conexiones["Claude MCP"] = "OK" } else { throw }
} catch {
    Write-Warn "Claude MCP GitHub: No configurado"
    $conexiones["Claude MCP"] = "PENDIENTE"
    if (Get-Command claude -ErrorAction SilentlyContinue) {
        Write-Host ""
        Write-Host "  El MCP de GitHub conecta Claude Code con tus repos." -ForegroundColor White
        Write-Host "  Permite crear repos, leer issues, hacer PRs desde Claude." -ForegroundColor White
        Write-Host ""
        Write-Host "  Necesitas un Personal Access Token de GitHub:" -ForegroundColor Cyan
        Write-Host "    1. Inicia sesion en github.com" -ForegroundColor White
        Write-Host "    2. Settings > Developer settings" -ForegroundColor White
        Write-Host "    3. Personal access tokens > Tokens (classic)" -ForegroundColor White
        Write-Host "    4. Generate new token (classic)" -ForegroundColor White
        Write-Host "    5. Nombre: 'Claude Code MCP', permiso: repo (completo)" -ForegroundColor White
        Write-Host "    6. Generate token y copiarlo" -ForegroundColor White
        Write-Host ""
        if (Ask-SN "Ya tenes tu token? Configurar ahora?") {
            Write-Host ""
            $token = Read-Host "  Pega tu token de GitHub aqui"
            if ($token -and $token.Length -gt 10) {
                Write-Info "Configurando variable de entorno GITHUB_PERSONAL_ACCESS_TOKEN..."
                [System.Environment]::SetEnvironmentVariable("GITHUB_PERSONAL_ACCESS_TOKEN", $token, "User")
                $env:GITHUB_PERSONAL_ACCESS_TOKEN = $token
                Write-Info "Registrando MCP server de GitHub en Claude Code..."
                claude mcp add github -s user -- npx -y @modelcontextprotocol/server-github 2>&1 | ForEach-Object { Write-Host "  $_" }
                try {
                    $checkMcp = (claude mcp list 2>&1) | Out-String
                    if ($checkMcp -match "github") { Write-OK "Claude MCP GitHub configurado!"; $conexiones["Claude MCP"] = "OK" }
                    else { Write-Warn "Configurado pero no aparece en la lista. Reinicia Claude Code." }
                } catch {}
            } else { Write-Warn "Token invalido o vacio." }
        }
    }
}

# --- NETLIFY ---
Write-Host ""
Write-Separador
Write-Info "Netlify..."
try {
    $ns = (netlify status 2>&1) | Out-String
    if ($ns -match "Logged in|Email:") { Write-OK "Netlify: Conectado"; $conexiones["Netlify"] = "OK" } else { throw }
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
                if ($nc -match "Logged in|Email:") { Write-OK "Netlify conectado!"; $conexiones["Netlify"] = "OK" }
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
    if ($vs -match "\w" -and $vs -notmatch "Error|not logged|No user") {
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
                if ($vc -match "\w" -and $vc -notmatch "Error") { Write-OK "Vercel conectado!"; $conexiones["Vercel"] = "OK" }
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
    if ($ss -match "Name|ID" -and $ss -notmatch "error|not logged") {
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
                if ($sc -match "Name|ID") { Write-OK "Supabase conectado!"; $conexiones["Supabase"] = "OK" }
            } catch {}
        }
    }
}

# --- SNYK ---
Write-Host ""
Write-Separador
Write-Info "Snyk..."
try {
    $sks = (snyk config get api 2>&1) | Out-String
    if ($sks -match "[a-f0-9\-]{20,}") {
        Write-OK "Snyk: Conectado (token configurado)"
        $conexiones["Snyk"] = "OK"
    } else { throw }
} catch {
    Write-Warn "Snyk: No conectado"
    $conexiones["Snyk"] = "PENDIENTE"
    if (Get-Command snyk -ErrorAction SilentlyContinue) {
        Write-Host ""
        Write-Host "  Escanea vulnerabilidades: snyk test" -ForegroundColor White
        Write-Host "  Token en: https://app.snyk.io/account > Auth Token" -ForegroundColor Cyan
        Write-Host ""
        if (Ask-SN "Tenes tu token de Snyk? Configurarlo ahora?") {
            $snykToken = Read-Host "  Pega tu token de Snyk aqui"
            if ($snykToken -and $snykToken.Length -gt 10) {
                snyk config set api=$snykToken 2>&1 | Out-Null
                $verify = (snyk config get api 2>&1) | Out-String
                if ($verify -match "[a-f0-9\-]{20,}") { Write-OK "Snyk conectado!"; $conexiones["Snyk"] = "OK" }
                else { Write-Warn "No se pudo guardar. Intenta: snyk config set api=TU_TOKEN" }
            } else { Write-Warn "Token vacio." }
        }
    }
}

# --- DOCKER ---
Write-Host ""
Write-Separador
Write-Info "Docker..."
try {
    $ds = (docker info 2>&1) | Out-String
    if ($ds -match "Server Version") { Write-OK "Docker: Funcionando"; $conexiones["Docker"] = "OK" } else { throw }
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
    Write-Host "  Tu estacion de trabajo esta 100% lista." -ForegroundColor Green
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
