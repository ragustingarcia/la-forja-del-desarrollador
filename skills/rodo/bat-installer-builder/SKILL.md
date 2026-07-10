---
name: bat-installer-builder
description: Construye instaladores .bat de alta calidad para Windows usando arquitectura híbrida .bat/PowerShell 7. Usar cuando el usuario pida crear un archivo .bat que instale programas, un script de setup o configuración para Windows, un instalador automatizado con verificaciones, o algo similar a "La Forja del Desarrollador". Aplica reglas: verificar antes de instalar, mostrar progreso siempre, ser re-ejecutable, explicar cada herramienta, manejar trampas de Windows (Python falso de MS Store, encoding roto de WSL, npm silencioso en CMD elevado, autenticación de Snyk CLI, refresco de PATH post-instalación). Incluye funciones auxiliares reutilizables (Write-OK/Err/Warn, Test-NpmPkg, Install-Winget, Ask-SN) y patrones para vinculaciones interactivas con login o token manual.
---

> 🔨 **Skill desarrollada por Rodolfo Agustín García** — [ragustingarcia.com](https://ragustingarcia.com/)
> Distribuida con [La Forja del Desarrollador](https://github.com/ragustingarcia/la-forja-del-desarrollador).
> Si la adaptás o redistribuís, conservá este crédito. ¡Gracias!

# Skill: Constructor de Instaladores .bat (Forja Style)

## Descripcion
Esta skill define como construir archivos .bat instaladores de alta calidad para Windows.
Aplica las lecciones aprendidas construyendo "La Forja del Desarrollador" - un instalador
de 20 pasos que instala, configura y vincula herramientas de desarrollo.

## Cuando usar esta skill
- Cuando el usuario pide crear un archivo .bat que instale programas
- Cuando el usuario pide un script de setup/configuracion para Windows
- Cuando se necesite un instalador automatizado con verificaciones
- Cuando se pida algo similar a "La Forja del Desarrollador"

## Arquitectura: Hibrido .bat/PowerShell

SIEMPRE usar la estructura hibrida. El .bat solo maneja la elevacion UAC,
luego copia el archivo a un .ps1 temporal y lo ejecuta en PowerShell 7.

```bat
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
copy "%~f0" "%temp%\setup_script.ps1" >nul
pwsh -NoProfile -ExecutionPolicy Bypass -File "%temp%\setup_script.ps1"
del "%temp%\setup_script.ps1" >nul 2>&1
echo.
echo   Presiona cualquier tecla para cerrar...
pause >nul
exit /b
: end batch / begin PowerShell #>
# PowerShell code starts here
```

### Por que esta estructura:
- Los .bat siempre corren en CMD aunque PowerShell sea la terminal por defecto
- CMD no muestra progreso de npm, pip y otros instaladores
- PowerShell 7 (pwsh) muestra todo el progreso correctamente
- El `copy` a .ps1 temporal es necesario porque `pwsh -File` no acepta .bat

## Reglas fundamentales

### 1. SIEMPRE verificar antes de instalar
NUNCA asumir que algo no esta instalado. Verificar primero con el comando apropiado.
Si ya esta instalado, mostrar version y saltar.

```powershell
# CORRECTO
if (Get-Command git -ErrorAction SilentlyContinue) {
    $ver = (git --version 2>&1) | Out-String
    Write-OK "Git ya instalado ($($ver.Trim()))."
} else {
    # instalar
}

# INCORRECTO - instalar sin verificar
winget install Git.Git
```

### 2. SIEMPRE mostrar progreso
NUNCA dejar la pantalla en silencio. Si un comando tarda mas de 2 segundos,
debe mostrar output visible.

```powershell
# Para npm (no muestra progreso en CMD):
npm install -g paquete --loglevel verbose 2>&1 | ForEach-Object { Write-Host "  $_" }

# Para pip:
pip install paquete 2>&1 | ForEach-Object { Write-Host "  $_" }

# Para winget: ya muestra progreso nativo, no necesita cambios

# Para comandos silenciosos (WSL, etc): redirigir a Out-Null y usar mensajes propios
cmd /c "wsl --update 2>&1" | Out-Null
Write-OK "WSL actualizado."
```

### 3. El script NUNCA debe cerrarse inesperadamente
Usar la estructura `call :main` en .bat o equivalente en PowerShell.
SIEMPRE tener `Read-Host` o `pause` al final.

### 4. El script debe ser RE-EJECUTABLE
Cada paso debe verificar si ya esta hecho y saltar automaticamente.
El usuario debe poder correr el script multiples veces sin efectos negativos.

### 5. Cada herramienta debe explicarse
Antes de instalar, mostrar:
- Que es (1-2 lineas)
- Ejemplos practicos de uso
- Por que se necesita en este contexto

## Trampas conocidas de Windows

### Python falso de Microsoft Store
Windows tiene un `python.exe` falso en `%LOCALAPPDATA%\Microsoft\WindowsApps`
que solo redirige a la Microsoft Store. Pesa menos de 20KB.

```powershell
# Detectar y desactivar el alias falso
$ap = "$env:LOCALAPPDATA\Microsoft\WindowsApps"
$fp = Join-Path $ap "python.exe"
if (Test-Path $fp) {
    $fs = (Get-Item $fp -ErrorAction SilentlyContinue).Length
    if ($fs -and $fs -lt 20000) {
        Rename-Item $fp "$fp.bak" -Force -ErrorAction SilentlyContinue
    }
}

# Verificar Python REAL (no solo que exista el comando)
function Test-PythonReal {
    try {
        $o = (python --version 2>&1) | Out-String
        if ($o -match "Python \d+\.\d+\.\d+") { return $o.Trim() }
    } catch {}
    return $null
}
```

### WSL output con encoding roto
WSL devuelve texto en encoding que PowerShell no maneja bien.
NUNCA mostrar output de WSL directamente.

```powershell
# CORRECTO - redirigir a null y usar mensajes propios
cmd /c "wsl --update 2>&1" | Out-Null
Write-OK "WSL actualizado."

# INCORRECTO - muestra caracteres rotos
wsl --update 2>&1 | ForEach-Object { Write-Host "  $_" }
```

### npm silencioso en CMD elevado
npm no muestra progreso en CMD elevado. Usar PowerShell con --loglevel verbose.

```powershell
npm install -g paquete --loglevel verbose 2>&1 | ForEach-Object { Write-Host "  $_" }
```

### Verificacion de librerias Python post-instalacion
`python -c "import fastapi"` puede fallar si Python se instalo en la misma sesion
y el PATH no se actualizo. Usar `pip show` en su lugar.

```powershell
# CORRECTO
$o = (pip show fastapi 2>&1) | Out-String
if ($o -match "Name: fastapi") { # instalado }

# INCORRECTO - falla si Python se instalo en esta sesion
python -c "import fastapi"
```

### Snyk CLI autenticacion
`snyk whoami` es experimental y falla. `snyk auth` no guarda token en versiones nuevas.
Usar `snyk config get api` para verificar y `snyk config set api=TOKEN` para configurar.

```powershell
# Verificar
$sks = (snyk config get api 2>&1) | Out-String
if ($sks -match "[a-f0-9\-]{20,}") { # conectado }

# Configurar manualmente
snyk config set api=$token
```

## Funciones auxiliares reutilizables

Incluir siempre estas funciones al inicio del script:

```powershell
function Write-OK      { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Err     { param($msg) Write-Host "  [X] $msg" -ForegroundColor Red }
function Write-Warn    { param($msg) Write-Host "  [!] $msg" -ForegroundColor Yellow }
function Write-Info    { param($msg) Write-Host "  $msg" -ForegroundColor Cyan }
function Write-Section { param($msg) Write-Host $msg -ForegroundColor Yellow }

function Write-Titulo { param($num, $total, $nombre, $desc)
    Write-Host ""
    Write-Section "============================================================"
    Write-Section "  [$num/$total] $nombre - $desc"
    Write-Section "============================================================"
    Write-Host ""
}

function Test-NpmPkg { param($pkg)
    try { $o = (npm list -g $pkg --depth=0 2>&1) | Out-String
        if ($o -match $pkg) { return $true } } catch {}
    return $false
}

function Test-WingetPkg { param($id)
    try { $o = (winget list --id $id --accept-source-agreements 2>&1) | Out-String
        if ($o -match $id) { return $true } } catch {}
    return $false
}

function Install-Winget { param($id, $nombre)
    $hw = Get-Command winget -ErrorAction SilentlyContinue
    if ($hw) {
        Write-Info "[INSTALANDO] $nombre via winget..."
        winget install --id $id --source winget --accept-package-agreements --accept-source-agreements
        return ($LASTEXITCODE -eq 0)
    }
    return $false
}

function Install-Npm { param($pkg, $nombre)
    Write-Info "[INSTALANDO] $nombre via npm..."
    Write-Host "  vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv" -ForegroundColor DarkGray
    npm install -g $pkg --loglevel verbose 2>&1 | ForEach-Object { Write-Host "  $_" }
    Write-Host "  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^" -ForegroundColor DarkGray
    return (Test-NpmPkg $pkg)
}

function Ask-SN { param($pregunta)
    $r = Read-Host "  $pregunta (S/N)"
    return ($r -match "^[sS]")
}
```

## Estructura de un paso de instalacion

Cada paso sigue este patron exacto:

```powershell
# ============================================================
#  [N/TOTAL] NOMBRE - Descripcion corta
# ============================================================
Write-Titulo N $T "Nombre" "Descripcion corta"
Write-Host "  Que es y para que sirve (1-2 lineas)."
Write-Host "  Ej: comando ejemplo / otro ejemplo"
Write-Host ""
Write-Info "Verificando..."
Write-Host ""

# 1. Verificar si ya esta instalado
if (CONDICION_YA_INSTALADO) {
    Write-OK "Nombre ya instalado."
    $status["nombre"] = "OK"
} else {
    # 2. Instalar
    if (Install-Winget "ID" "Nombre") {  # o Install-Npm
        Write-OK "Instalado."
        $status["nombre"] = "OK"
    } else {
        Write-Err "Error."
        $status["nombre"] = "ERROR"
    }
}
```

## Vinculaciones interactivas

Para servicios que requieren login, usar este patron:

```powershell
Write-Info "Verificando Servicio..."
try {
    $output = (comando-verificacion 2>&1) | Out-String
    if ($output -match "patron_exito") {
        Write-OK "Servicio: Conectado"
        $conexiones["Servicio"] = "OK"
    } else { throw }
} catch {
    Write-Warn "Servicio: No conectado"
    $conexiones["Servicio"] = "PENDIENTE"
    if (Get-Command servicio -ErrorAction SilentlyContinue) {
        Write-Host ""
        Write-Host "  Explicacion de que hace el servicio." -ForegroundColor White
        Write-Host "  Que va a pasar al conectar." -ForegroundColor White
        Write-Host ""
        if (Ask-SN "Queres conectar Servicio ahora?") {
            servicio login
            # re-verificar despues del login
        }
    }
}
```

Para servicios que necesitan token manual (como Snyk o Claude MCP GitHub):

```powershell
Write-Host "  Pasos para obtener el token:" -ForegroundColor Cyan
Write-Host "    1. Ir a URL" -ForegroundColor White
Write-Host "    2. Hacer tal cosa" -ForegroundColor White
Write-Host ""
if (Ask-SN "Tenes tu token? Configurarlo ahora?") {
    $token = Read-Host "  Pega tu token aqui"
    if ($token -and $token.Length -gt 10) {
        # configurar con el token
    }
}
```

## Resumen final

Siempre incluir al final:
1. **Resumen de instalacion** - Lista de todo con estado OK/ERROR/PENDIENTE
2. **Estado de conexiones** - Lista de servicios vinculados
3. **Mensaje dinamico** - Si hay pendientes: instrucciones + "volve a ejecutar". Si todo OK: "100% lista"
4. **Read-Host al final** - Para que no se cierre

## Orden logico de instalacion

Cuando hay multiples herramientas, agrupar asi:
1. **Infraestructura** - winget, PowerShell, WSL, Git (prerequisitos)
2. **Lenguajes** - Node.js, Python, librerias
3. **Desarrollo** - Editor, CLI de IA, GitHub CLI
4. **Servicios** - Docker, bases de datos, IA local
5. **Deploy y seguridad** - CLIs de hosting, escaner de vulnerabilidades
6. **Vinculaciones** - Login interactivo a servicios

## Refrescar PATH despues de instalar

Cuando se instala Node.js, Python o similar, refrescar PATH inmediatamente:

```powershell
# Node.js
$env:PATH = "$env:PATH;$env:ProgramFiles\nodejs;$env:APPDATA\npm"

# Python
$pyPaths = @(
    "$env:LOCALAPPDATA\Programs\Python\Python312",
    "$env:LOCALAPPDATA\Programs\Python\Python312\Scripts"
)
foreach ($p in $pyPaths) {
    if ((Test-Path $p) -and ($env:PATH -notlike "*$p*")) {
        $env:PATH = "$env:PATH;$p"
    }
}
```
