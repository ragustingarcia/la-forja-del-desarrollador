![La Forja del Desarrollador](assets/banner.svg)

# La Forja del Desarrollador

> Stack de desarrollo con agentes de IA en Windows: editores, CLI, lenguajes, bases de datos y servicios cloud.
> Un BAT para preparar la base, elegir herramientas y actualizar lo que ya usás.

[![Licencia MIT](https://img.shields.io/badge/licencia-MIT-f0722e)](LICENSE)
[![Windows 10/11](https://img.shields.io/badge/Windows-10%2F11-ffb454)](https://github.com/ragustingarcia/la-forja-del-desarrollador)
[![Hecho por Rodolfo Agustín García](https://img.shields.io/badge/por-ragustingarcia.com-17151a)](https://ragustingarcia.com/)

## Empezar

Descargá `forja-del-desarrollador.bat` y abrilo con doble clic, **sin ejecutar toda la Forja como administrador**. Arranca con Windows PowerShell 5.1, incluido en Windows. Revisá los permisos de los instaladores de terceros.

| Modo | Qué hace |
|---|---|
| **[1] Preparar stack** | Instala/verifica la base y pregunta individualmente qué agentes, CLI y servicios agregar. |
| **[2] Solo actualizar** | Recorre la base y el catálogo ampliado; saltea herramientas ausentes. Puede ofrecer agregar Python 3.14 en paralelo, con confirmación adicional. |
| **[3] Diagnóstico** | Muestra rutas, registro Store y ubicaciones de paquetes nativos revisados; no instala ni autentica. |
| **[4] Stack por proyecto** | Muestra recetas para frontend, Flask/OpenCV, PostGIS y conexiones; no ejecuta esas recetas. |
| **[5] Catálogo completo** | Lista todas las herramientas por páginas; permite volver al menú sin instalar. |
| **[T01] … [T49]** | Instala o actualiza únicamente la selección elegida; las guías muestran instrucciones. |
| **[0] / ENTER** | Sale sin cambios. |

El menú es espaciado y está agrupado por categorías. Cada entrada explica para qué sirve en términos simples. Escribí su código (por ejemplo, `T05` para Node.js) para actuar sobre esa herramienta, sin recorrer el setup completo. La selección muestra su explicación y pide confirmación antes de instalar o actualizar.

Las descargas directas muestran una barra con porcentaje y MB recibidos. WinGet, npm, pip y Git muestran una barra de actividad cuando no informan un total medible; los avisos del proveedor se conservan. Si WinGet no permite actualizar Android Studio o Miniforge, quedan pendientes con indicaciones del gestor original.

No incluye controladores ni aplicaciones de uso diario. Cada agente conserva su propia configuración, skills y MCP.

## Base de desarrollo

WinGet, PowerShell 7, WSL, Git, Node.js LTS/npm, pnpm, Python, librerías Python aisladas, VS Code, Claude Code y Desktop, GitHub CLI, Docker Desktop, mongosh, Ollama, FFmpeg, Netlify CLI, Vercel CLI, Supabase CLI y Snyk CLI. Los packs de skills Claude son opcionales y se conservan las skills existentes.

El asistente de conexión de la base conserva los pasos de GitHub, Netlify, Vercel, Supabase, Snyk y Docker. Los servicios nuevos muestran sus comandos oficiales de autenticación para ejecutarlos manualmente. La instalación no crea bases, envía emails, publica dominios ni hace deploys.

## Elegir el stack ampliado

| Grupo | Herramienta | Método |
|---|---|---|
| Editores y agentes | Cursor | winget |
| Editores y agentes | Antigravity App | winget |
| Editores y agentes | Antigravity IDE | winget |
| Editores y agentes | Gemini Desktop | winget |
| Editores y agentes | Grok Bot | winget |
| Editores y agentes | App ChatGPT / Codex | store |
| CLI de agentes | Codex CLI | npm |
| CLI de agentes | Antigravity CLI (agy) | winget |
| CLI de agentes | Cursor Agent CLI (Windows x64) | archive |
| Gemini CLI (compatibilidad) | Gemini CLI (cuentas compatibles) | npm |
| Servicios cloud | Neon CLI | npm |
| Servicios cloud | Resend CLI | npm |
| Servicios cloud | Render CLI (Windows x64) | archive |
| Servicios cloud | Cloudflare Tunnel CLI | winget |
| Servicios cloud | Cloudflare Wrangler (por proyecto) | project-npm |
| Bases de datos locales | PostgreSQL 17 (servidor y cliente) | winget |
| Compilacion y escritorio | Rust / Cargo (rustup) | winget |
| Compilacion y escritorio | Visual Studio Build Tools 2022 | winget |
| Compilacion y escritorio | .NET SDK 10 | winget |
| Compilacion y escritorio | Inno Setup | winget |
| Android y Java | Android Studio | winget |
| Android y Java | Temurin JDK 17 | winget |
| Android y Java | Temurin JDK 21 | winget |
| Python cientifico | Miniforge3 | winget |
| Python cientifico | Flask + OpenCV + NumPy (venv aislado) | python-venv |

Los catálogos legibles están en [catalog/base.json](catalog/base.json) y [catalog/stack-ia.json](catalog/stack-ia.json). El BAT incluye una copia idéntica, por lo que sigue siendo un archivo único para el usuario. Los tests comprueban esa identidad.

**Apps y CLI se tratan por separado.** Cursor y Cursor Agent son entradas diferentes; también Antigravity App, IDE y `agy`, y la app ChatGPT/Codex frente a `codex`. No se instala un paquete Grok CLI de terceros: no se verificó una CLI independiente de Grok Bot.

**Gemini CLI:** Google retiró el acceso de las cuentas personales e indica migrar a Antigravity. Por eso `agy` es la opción normal y Gemini CLI queda como selección de compatibilidad, con aviso. [Fuente oficial](https://developers.google.com/gemini-code-assist/docs/deprecations/code-assist-individuals).

## Python actualizable, con entornos separados

- El modo 2 comprueba todas las ramas WinGet contempladas (3.10 a 3.15), sin detenerse en la primera instalada.
- La rama para instalaciones nuevas de este catálogo es **3.14**, verificada en WinGet. No se presenta como la última versión de Python.org.
- Si ya tenés otra rama, podés agregar 3.14 en paralelo. No se eliminan versiones, se migra Conda ni se reinstalan los paquetes compartidos.
- Las cinco librerías base viven en `%LOCALAPPDATA%\Forja\Python\venv`.
- Flask, OpenCV y NumPy tienen un perfil opcional separado en `%LOCALAPPDATA%\Forja\Python\web-vision`.
- Se comprueban aislamiento, `pip check`, presencia e imports. Los proyectos conservan sus venvs; actualizar el intérprete no los migra automáticamente.

Para un proyecto nuevo con una rama específica: `py -3.14 -m venv .venv`. Revisá sus dependencias y lockfile antes de cambiar la rama de un proyecto existente.

## Frontend y servicios por proyecto

React, TypeScript, Vite y Tailwind se instalan dentro de cada proyecto. Forja muestra cómo empezar, sin agregar paquetes globales que cambien proyectos existentes. PWA y extensiones Chrome son tipos de proyecto; PostGIS requiere componentes compatibles con PostgreSQL y habilitación en la base elegida.

Wrangler sigue la recomendación de Cloudflare de usar una dependencia de desarrollo local: al elegirlo en modo 1, pide una ruta absoluta con `package.json` y una segunda confirmación. npm modifica los archivos de dependencias solo allí. El modo 2 no recorre ni altera todos tus proyectos. Para actualizar Wrangler, volvé a elegir ese proyecto desde el modo 1. [Documentación de Cloudflare](https://developers.cloudflare.com/workers/wrangler/install-and-update/).

## Cómo se actualizan las herramientas

- WinGet usa ID exacto y fuente explícita; se comprueba el registro después de instalar las entradas nuevas del catálogo.
- Las CLI npm usan el paquete oficial, una versión concreta consultada al registro y comprobación de la CLI. Se evita iniciar una segunda instalación si se detecta otra vía.
- Cursor Agent, Render y Supabase nativos usan ZIP Windows x64 y SHA-256 revisados. Se validan rutas/enlaces del ZIP antes de extraer y se verifica la versión antes de publicar el directorio. No se ejecutan los scripts remotos de bootstrap.
- Esos ZIP quedan en `%LOCALAPPDATA%\Forja\Tools\<id>\<version>`. El BAT muestra el comando completo de su launcher. No cambia el PATH persistente ni borra versiones anteriores; una revisión nueva de estos paquetes requiere actualizar el catálogo de Forja.
- La app ChatGPT/Codex se instala por el ID oficial de Microsoft Store; sus actualizaciones se delegan a Store y aparecen como saltadas, con explicación, en el modo 2.
- Los JDK de Scoop y un rustup externo se reconocen para evitar duplicarlos. Su actualización queda pendiente con indicación de usar el gestor original. Los toolchains Rust, SDK Android y workloads de Build Tools requieren gestión propia.
- Supabase existente por npm se conserva. Una instalación nueva usa el ZIP nativo; se eliminó el fallback de instalación npm global. No se desinstala la copia de Scoop ni se cambia automáticamente el PATH.

Si una instalación no puede comprobarse, aparece como pendiente o error. Las versiones de servicios y paquetes pueden cambiar entre ejecuciones; esto no es una imagen exacta de una PC.

## Seguridad, respaldo y validación

La Forja mantiene el guard contra elevación global, confirmaciones, temporales propios, validación de reparse points, skills por SHA y verificación del MSI de reparación de mongosh. No desactiva SmartScreen, antivirus ni políticas de ejecución.

No contiene credenciales ni respalda proyectos, bases de datos o volúmenes Docker. Antes de formatear, guardá y verificá esos datos por separado. El inventario personal de una PC no forma parte de este repositorio público.

Leé [SECURITY.md](SECURITY.md), [el detalle de v6.2.0](docs/STACK-IA-v6.2.0.md) y [la auditoría inicial](docs/AUDITORIA-SEGURIDAD-v6.1.md). CI ejecuta pruebas simuladas en PowerShell 5.1 y 7. La descarga, extracción y respuesta de versión de las tres CLI ZIP se comprobaron bajo un directorio de prueba; la instalación completa de todos los proveedores, logins y reinicios en una VM limpia siguen siendo verificaciones separadas.

## Historial de versiones

| Versión | Cambios |
|---|---|
| v6.2.0 | Stack de agentes y servicios seleccionable; actualizaciones Python por rama; Flask/OpenCV aislados; Wrangler por proyecto; CLI nativas con ZIP y SHA revisados. [Detalle](docs/STACK-IA-v6.2.0.md) |
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
