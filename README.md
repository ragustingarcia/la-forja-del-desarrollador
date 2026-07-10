![La Forja del Desarrollador](assets/banner.svg)

# La Forja del Desarrollador

> Setup completo para desarrollar con Claude Code en Windows.  
> 21 herramientas instaladas, configuradas y vinculadas en un solo script.

[![Licencia MIT](https://img.shields.io/badge/licencia-MIT-f0722e)](LICENSE)
[![Windows 10/11](https://img.shields.io/badge/Windows-10%2F11-ffb454)](https://github.com/ragustingarcia/la-forja-del-desarrollador)
[![Hecho por Rodolfo Agustín García](https://img.shields.io/badge/por-ragustingarcia.com-17151a)](https://ragustingarcia.com/)

---

## Qué hace

Un `.bat` que corre como Administrador, instala todo lo que necesitás para desarrollar con Claude Code en Windows, y te guía paso a paso para conectar cada servicio.

Si algo ya está instalado, lo detecta y lo saltea. Si algo falla, te dice qué hacer. Podés correrlo múltiples veces sin romper nada.

---

## Cómo usarlo

```
1. Descargá forja-del-desarrollador.bat
2. Click derecho → "Ejecutar como administrador"
3. Elegí el modo y seguí las instrucciones en pantalla
```

Al arrancar, el script pregunta qué modo querés:

| Modo | Qué hace |
|---|---|
| **[1] Setup completo** | Instala las 21 herramientas y te guía para vincular cada servicio |
| **[2] Solo actualizar** | Recorre lo que ya tenés instalado y lo actualiza a la última versión, en la misma ventana |

Si Windows bloquea el script, click en "Más información" → "Ejecutar de todas formas".

---

## Qué instala

### Infraestructura
| # | Herramienta | Para qué |
|---|---|---|
| 1 | winget | Gestor de paquetes de Windows |
| 2 | PowerShell 7 | Terminal moderna (el script corre en pwsh) |
| 3 | WSL | Linux dentro de Windows (necesario para Docker) |
| 4 | Git | Control de versiones + configura nombre y email |

### Lenguajes
| # | Herramienta | Para qué |
|---|---|---|
| 5 | Node.js LTS | JavaScript del lado del servidor + npm |
| 6 | pnpm | Alternativa a npm: más rápido, menos disco |
| 7 | Python 3.13 | Backend, IA, automatización |
| 8 | Libs Python | fastapi, uvicorn, python-multipart, pdfplumber, requests |

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

### Vinculaciones
| # | Herramienta | Para qué |
|---|---|---|
| 21 | Asistente de conexión | Conecta GitHub CLI, Claude MCP, Netlify, Vercel, Supabase, Snyk y Docker con tu cuenta |

---

## Qué hace el paso 21 en particular

El asistente de vinculación verifica y conecta cada servicio:

- **GitHub CLI** → `gh auth login` (navegador)
- **Claude MCP GitHub** → configura `GITHUB_PERSONAL_ACCESS_TOKEN` como variable de entorno de usuario y registra el servidor `@modelcontextprotocol/server-github` en Claude Code
- **Netlify** → `netlify login` (navegador)
- **Vercel** → `vercel login` (navegador o email)
- **Supabase** → `supabase login` (navegador)
- **Snyk** → ingreso manual de API token
- **Docker** → verifica que Docker Desktop esté corriendo

Si ya estás conectado a algún servicio, el script lo detecta y lo marca como OK sin pedirte nada.

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
- El script **no toca ni borra** lo que ya tenés instalado.
- El MCP de GitHub usa el servidor oficial `@modelcontextprotocol/server-github` vía NPX.

---

## Actualizar tus herramientas

Corré el script y elegí el modo **[2] Solo actualizar**. Recorre las herramientas instaladas y las actualiza:

- **winget**: PowerShell 7, Git, Node.js, pnpm, Python, VS Code, Claude Desktop, GitHub CLI, Docker, mongosh, Ollama, FFmpeg, Supabase CLI
- **npm**: Claude Code CLI, Netlify CLI, Vercel CLI, Snyk CLI (a `@latest`)
- **WSL** y **librerías Python** (`pip --upgrade`)

Lo que no está instalado se saltea sin preguntar. Al final muestra un resumen: actualizados / ya al día / saltados / con errores.

> Tip: cerrá VS Code y Docker antes de actualizar — un programa abierto puede bloquear su propia actualización.

**Caso especial — PowerShell 7**: el script corre en pwsh, así que no puede actualizarlo mientras se ejecuta. Si detecta un update disponible, al cerrar el script se abre una ventana aparte que lo actualiza automáticamente.

**Caso especial — doble instalación de Claude Code**: si detecta que tenés Claude Code instalado dos veces (npm global + instalador nativo), te ofrece eliminar la npm y quedarte solo con la nativa (la recomendada por Anthropic). Requiere cerrar todas las sesiones de Claude Code primero — el script te lo avisa y pide confirmación.

Para actualizar **el script en sí**, descargá la última versión de este repo.

---

## Historial de versiones

| Versión | Cambios |
|---|---|
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
