![La Forja del Desarrollador](assets/banner.svg)

# La Forja del Desarrollador

> Setup completo para desarrollar con Claude Code en Windows.  
> 21 herramientas + skills de Claude Code, instaladas, configuradas y vinculadas en un solo script.

[![Licencia MIT](https://img.shields.io/badge/licencia-MIT-f0722e)](LICENSE)
[![Windows 10/11](https://img.shields.io/badge/Windows-10%2F11-ffb454)](https://github.com/ragustingarcia/la-forja-del-desarrollador)
[![Hecho por Rodolfo Agustín García](https://img.shields.io/badge/por-ragustingarcia.com-17151a)](https://ragustingarcia.com/)

---

## Qué hace

Un `.bat` que corre en tu sesión normal de Windows, instala todo lo que necesitás para desarrollar con Claude Code en Windows, y te guía paso a paso para conectar cada servicio.

Si algo ya está instalado, lo detecta y lo saltea. Si algo falla, te dice qué hacer. Podés volver a correrlo: verifica instalaciones y conserva las skills que ya existen. Revisá siempre el resumen y los avisos de cada proveedor.

---

## Cómo usarlo

```
1. Descargá forja-del-desarrollador.bat
2. Abrilo con doble clic, SIN "Ejecutar como administrador"
3. Elegí el modo, confirmá y seguí las instrucciones en pantalla
```

Al arrancar, el script pregunta qué modo querés:

| Modo | Qué hace |
|---|---|
| **[1] Setup completo** | Instala las 21 herramientas y te guía para vincular cada servicio |
| **[2] Solo actualizar** | Recorre lo que ya tenés instalado y lo actualiza a la versión publicada, en la misma ventana |
| **[3] Diagnóstico** | Muestra las rutas de herramientas disponibles, sin ejecutar instaladores ni logins |
| **[0] Salir / ENTER** | Cierra sin instalar nada |

La Forja arranca con **Windows PowerShell 5.1**, incluido en Windows; no necesitás instalar
PowerShell 7 previamente. Si abrís toda la Forja como administrador, se detiene. WSL pide
UAC solo para su instalación y otros instaladores pueden mostrar su propio aviso de permisos.

Descargá el BAT desde este repositorio y revisá el código antes de ejecutarlo. Si Windows o
una política de tu organización lo bloquea, verificá el origen y consultá al administrador del equipo.
La Forja no desactiva SmartScreen, antivirus ni políticas corporativas.

**Seguridad y migración desde versiones anteriores:** [SECURITY.md](SECURITY.md).
**Auditoría y límites de las pruebas:** [docs/AUDITORIA-SEGURIDAD-v6.1.md](docs/AUDITORIA-SEGURIDAD-v6.1.md).

---

## Qué instala

### Infraestructura
| # | Herramienta | Para qué |
|---|---|---|
| 1 | winget | Gestor de paquetes de Windows |
| 2 | PowerShell 7 | Terminal moderna (se instala sin ser necesaria para arrancar) |
| 3 | WSL | Linux dentro de Windows (necesario para Docker) |
| 4 | Git | Control de versiones + configura nombre y email |

### Lenguajes
| # | Herramienta | Para qué |
|---|---|---|
| 5 | Node.js LTS | JavaScript del lado del servidor + npm |
| 6 | pnpm | Alternativa a npm: más rápido, menos disco |
| 7 | Python 3.13 | Backend, IA, automatización |
| 8 | Libs Python | fastapi, uvicorn, python-multipart, pdfplumber, requests, en un entorno propio de Forja |

### Desarrollo
| # | Herramienta | Para qué |
|---|---|---|
| 9 | VS Code | Editor de código |
| 10 | Claude Code CLI | IA que desarrolla con vos (herramienta central) |
| 11 | Claude Desktop | App de escritorio de Claude |
| 12 | GitHub CLI | Gestionar repos, PRs e issues desde terminal |

### Servicios
| # | Herramienta | Para qué |
|---|---|---|
| 13 | Docker Desktop | Contenedores (necesario para Supabase local) |
| 14 | mongosh | Cliente de MongoDB |
| 15 | Ollama | Modelos de IA locales (Llama, Mistral, Gemma) |
| 16 | FFmpeg | Procesamiento de audio y video |

### Deploy y seguridad
| # | Herramienta | Para qué |
|---|---|---|
| 17 | Netlify CLI | Deploy de frontends y sitios estáticos |
| 18 | Vercel CLI | Deploy de apps Next.js y React |
| 19 | Supabase CLI | PostgreSQL, auth, storage y edge functions |
| 20 | Snyk CLI | Scanner de vulnerabilidades en dependencias |

### Skills de Claude Code
| # | Herramienta | Para qué |
|---|---|---|
| 21 | Skills | Pack de la Forja (skills del autor, con crédito) + oficiales de Anthropic (skill-creator, docx, pdf, xlsx, pptx) |

### Vinculaciones
| # | Herramienta | Para qué |
|---|---|---|
| 22 | Asistente de conexión | Conecta GitHub CLI, Claude MCP, Netlify, Vercel, Supabase, Snyk y Docker con tu cuenta |

---

## Qué hace el paso 22 en particular

El asistente de vinculación verifica y conecta cada servicio:

- **GitHub CLI** → `gh auth login` (navegador)
- **Claude MCP GitHub** → opcional, con guía para configurar manualmente el servidor mantenido por GitHub y limitar sus permisos; la Forja no solicita ni guarda un PAT
- **Netlify** → `netlify login` (navegador)
- **Vercel** → `vercel login` (navegador o email)
- **Supabase** → `supabase login` (navegador)
- **Snyk** → login por navegador con OAuth; verificación mediante `snyk whoami --experimental` (si no se puede verificar, queda pendiente)
- **Docker** → verifica que Docker Desktop esté corriendo

Si detecta una conexión válida, la marca como OK. Las conexiones que no puede verificar quedan pendientes; el MCP manual se muestra como opcional.

---

## Skills de Claude Code (paso 21)

Una skill le enseña a Claude Code una capacidad nueva, y se carga **solo cuando se usa** — por eso ahorra tokens frente a instrucciones permanentes. El paso 21 ofrece dos packs, cada uno opcional:

**Pack de la Forja** — skills desarrolladas por el autor ([detalle en `skills/`](skills/README.md)). Al instalarlas elegís:
1. **Tal cual están**, con el agradecimiento al autor en cada archivo, o
2. **Personalizadas**: se agrega tu nombre como adaptador.

En ambos casos **el crédito del desarrollador original se conserva** — es la única condición de uso.

**Oficiales de Anthropic** — `skill-creator`, `docx`, `pdf`, `xlsx`, `pptx`. Se descargan por una revisión fija del repo oficial [anthropics/skills](https://github.com/anthropics/skills) (no se redistribuyen desde acá).

Las skills existentes en tu `~/.claude/skills` **se conservan**: si ya tenés una con el mismo
nombre, se saltea. Las nuevas se preparan fuera de esa carpeta y se mueven al completar la copia.
Se rechazan enlaces y junctions en las rutas. El script muestra los SHA utilizados y no ejecuta
el contenido descargado. Revisá las instrucciones antes de habilitarlas en Claude.

---

## Requisitos

- Windows 10/11
- Conexión a internet
- Cuenta en GitHub (para el paso de vinculación)
- Cuentas opcionales: Netlify, Vercel, Supabase, Snyk

---

## Notas

- Algunos pasos instalan programas que necesitan **reiniciar la terminal o la PC** para que el PATH se actualice. El script te avisa cuándo. Podés volver a correrlo después del reinicio para completar los pasos pendientes.
- Docker Desktop requiere reiniciar la PC después de instalarse.
- El setup puede instalar paquetes y configurar tu identidad Git. El modo actualización modifica versiones existentes; la limpieza opcional de Claude usa únicamente el desinstalador de npm, con confirmación.
- El MCP antiguo por NPX ya no se configura. Si lo instalaste antes, seguí la migración de [SECURITY.md](SECURITY.md).

---

## Actualizar tus herramientas

Corré el script y elegí el modo **[2] Solo actualizar**. Recorre las herramientas instaladas y las actualiza:

- **winget**: PowerShell 7, Git, Node.js, pnpm, Python, VS Code, Claude Desktop, GitHub CLI, Docker, mongosh, Ollama, FFmpeg, Supabase CLI
- **Claude Code CLI**: su propio comando `claude update`
- **npm**: Netlify CLI, Vercel CLI y Snyk CLI, consultando e instalando una versión concreta
- **WSL** y **librerías Python**, estas últimas únicamente dentro de `%LOCALAPPDATA%\Forja\Python\venv`

Lo que no está instalado se saltea sin preguntar. Al final muestra un resumen: actualizados / ya al día / saltados / con errores.

> Tip: cerrá VS Code y Docker antes de actualizar — un programa abierto puede bloquear su propia actualización.

**PowerShell 7** se actualiza en la misma ventana: el lanzador usa Windows PowerShell 5.1. Cerrá otras sesiones de PowerShell 7 si el instalador avisa que está en uso.

**Caso especial — doble instalación de Claude Code**: si detecta que tenés Claude Code instalado dos veces (npm global + instalador nativo), te ofrece eliminar la npm y quedarte solo con la nativa (la recomendada por Anthropic). Requiere cerrar todas las sesiones de Claude Code primero — el script te lo avisa y pide confirmación.

Para actualizar **el script en sí**, descargá la última versión de este repo.

---

## Historial de versiones

| Versión | Cambios |
|---|---|
| v6.1.3 | Reparación opcional de mongosh mediante su MSI oficial verificado y UAC limitado al instalador; validación de versión registrada y ejecutable; los avisos del Python compartido no se repiten cuando el entorno de Forja ya existe. Reparación real confirmada en 2.14.0. [Detalle](docs/CORRECCION-v6.1.3.md) |
| v6.1.2 | Corrige los contadores del resumen; aísla las librerías Python de Forja y verifica dependencias/imports; distingue avisos npm de fallos y verifica las CLIs; muestra el diagnóstico MSI de mongosh y evita reintentos de fallos conocidos sin confirmación. [Detalle](docs/CORRECCION-v6.1.2.md) |
| v6.1.1 | Corrige la segunda pasada de WinGet, muestra versiones instaladas, reconoce PowerShell desde el inventario general, usa ejecutables `.exe`/`.cmd` para CLIs npm y continúa ante una limpieza fallida de Claude. Agrega pruebas nativas bajo política Restricted. [Detalle](docs/CORRECCION-v6.1.1.md) |
| v6.1 | **Seguridad**: sin elevación global ni bootstrap temporal; inicio con Windows PowerShell 5.1; diagnóstico; confirmación explícita; sin captura de tokens; skills por SHA fijo, sin enlaces ni sobrescrituras; verificación de fallos y pruebas Windows en CI |
| v6.0 | **Paso 21 — Skills de Claude Code**: pack de la Forja (skills del autor con crédito preservado, opción de personalizar con tu nombre) + set oficial de Anthropic clonado de su repo; vinculaciones pasan a ser el paso 22 |
| v5.8 | WSL: si la descarga desde Microsoft Store falla (403 `Wsl/UpdatePackage/0x80190193`), reintenta automáticamente con `--web-download` (baja desde GitHub) |
| v5.7 | Detección de doble instalación de Claude Code (npm global + nativa): ofrece eliminar la npm y quedarse con la nativa, con confirmación y verificación posterior |
| v5.6 | WSL: un fallo de `wsl --update` (ej. error 403 transitorio del servidor de Microsoft) ya no se reporta como OK — se cuenta como error con sugerencia de reintentar |
| v5.5 | Modo actualización mucho más rápido: los paquetes npm comparan versión instalada vs última publicada y saltean la reinstalación si coinciden (antes Netlify CLI reinstalaba 1100 paquetes por 2 min para quedar igual); winget pre-chequea con `--upgrade-available` (sin bloques de progreso vacíos); pip en modo silencioso; WSL cuenta como "ya al día" |
| v5.4 | Modo actualización: progreso en vivo (barras nativas de winget/npm/pip/WSL, ya no parece congelado); detección de Python por versión instalada (3.13/3.12/3.11/3.10 — antes solo buscaba 3.13); Claude Code CLI se actualiza con `claude update` (cubre instalación nativa, no solo npm); Supabase CLI con fallback a npm |
| v5.3 | Modo actualización: detección "ya al día" por exit code de winget (`0x8A15002B`, independiente del idioma — antes daba falso error); PowerShell 7 se actualiza en ventana aparte al cerrar (no puede actualizarse mientras el script corre en él) |
| v5.2 | **Modo actualización**: menú al inicio ([1] Setup completo / [2] Solo actualizar); actualiza winget + npm + WSL + libs Python de lo ya instalado, con resumen final |
| v5.1 | Verificación de Claude Code no interactiva (`claude doctor` colgaba el script), guard en la configuración de Git recién instalado, detección WSL por exit code (el output UTF-16 de wsl.exe rompía el parseo de texto), mensaje de éxito restaurado, URL de actualizaciones, kit de marca (banner, badges, CITATION.cff) |
| v5 | Python 3.13, pnpm, Supabase CLI via winget, MCP GitHub corregido (server-github oficial), configuración de identidad Git, detección WSL mejorada |
| v4 | Asistente interactivo de vinculación, detección de stubs de Python en WindowsApps |

---

## Autor

Hecho por **Rodolfo Agustín García** — [ragustingarcia.com](https://ragustingarcia.com/)

- GitHub: [@ragustingarcia](https://github.com/ragustingarcia)
- LinkedIn: [ragustingarcia](https://www.linkedin.com/in/ragustingarcia/)
- Lab: [rcwe.ragustingarcia.com](https://rcwe.ragustingarcia.com/)

Si te resultó útil, issues y PRs son bienvenidos. Para citar esta herramienta, usá el botón **"Cite this repository"** de GitHub (definido en [CITATION.cff](CITATION.cff)).

---

## Licencia

MIT — libre para usar, modificar y distribuir.
