# Forja v6.2.0 · stack de desarrollo con agentes de IA

La Forja deja de estar presentada como un setup exclusivo de Claude. Conserva su base y agrega
una selección individual de editores, agentes, CLI, compiladores, bases de datos y servicios.
Quedan fuera controladores, multimedia de uso general, Office, juegos y aplicaciones cotidianas.

## Qué cambia al ejecutar el BAT

El modo 1 prepara la base y ofrece cada entrada adicional del catálogo. Se puede elegir Cursor,
Antigravity App e IDE, Gemini Desktop, Grok Bot y la app ChatGPT/Codex; las CLI se seleccionan
separadamente. El modo 2 consulta las herramientas instaladas y conserva un resultado por entrada.
El modo 3 es de diagnóstico; el modo 4 explica el stack por proyecto sin ejecutar las recetas.

El catálogo adicional tiene 25 entradas seleccionables. La entrada 26 corresponde al paquete
nativo de Supabase, que se usa desde el paso existente de la base. El JSON distribuido y el
embebido en el BAT deben coincidir; no se carga una configuración externa mutable al ejecutar.

Las instalaciones WinGet nuevas comprueban su presencia antes y después del instalador. Las CLI
npm comprueban el paquete registrado y el ejecutable; no basta con un exit code 0 del instalador.
Un fallo de una herramienta no interrumpe el recorrido de las demás ni borra su estado del resumen.

## Agentes y sus CLI

| Superficie | Instalación contemplada | Comprobación y límite |
|---|---|---|
| Cursor | `Anysphere.Cursor`, WinGet | Aplicación registrada; el agente terminal es otro paso. |
| Cursor Agent | ZIP oficial Windows x64, revisión `2026.10.22-27dcf5f` | SHA-256 fijo, extracción validada y respuesta de versión del runtime Node. |
| Antigravity App / IDE | `Google.Antigravity` / `Google.AntigravityIDE` | Son productos distintos y se eligen por separado. |
| Antigravity CLI | `Google.AntigravityCLI`, comando `agy` | ID existente verificado en WinGet. |
| Gemini Desktop | `Google.GeminiDesktop` | No se considera equivalente a Gemini CLI. |
| Gemini CLI | `@google/gemini-cli`, selección de compatibilidad | Se avisa de la retirada de acceso para cuentas personales. |
| Grok Bot | `xAI.GrokBot` | No se inventa una CLI independiente ni se instala un paquete Grok de terceros. |
| ChatGPT / Codex App | Microsoft Store, producto `9PLM9XGG6VKS` | ID documentado oficialmente. Store gestiona sus actualizaciones; el modo 2 lo indica y lo saltea. |
| Codex CLI | `@openai/codex` | Paquete npm oficial, distinto de la aplicación Store. |
| Claude | Se conserva el soporte existente | Instalación existente nativa/npm y updater propio; no se cambian sus skills o configuración. |

El instalador remoto de Cursor fue inspeccionado como texto. Su inicialización puede borrar el
directorio anterior y sus launchers incluyen una opción de política de ejecución. La Forja no lo
ejecuta: descarga el ZIP concreto y crea un launcher propio que llama al runtime de esa revisión.
No modifica el PATH persistente ni elimina versiones anteriores. Muestra la ruta completa del
comando; no presenta una conversación de agente como probada por haber pasado `--version`.

Google documenta la migración de las cuentas personales desde Gemini CLI a Antigravity. Gemini CLI
queda disponible explícitamente para cuentas compatibles; no se instala como reemplazo automático
de Antigravity. Las skills, reglas, extensiones y MCP de cada agente permanecen bajo su propia gestión.

## Servicios del stack

- **Neon:** paquete oficial `neon`. La denominación anterior `neonctl` no se usa para una nueva
  instalación. Forja no ejecuta `neon init`, crea proyectos ni cambia branches remotos.
- **Resend:** paquete oficial `resend-cli`, comando `resend`. Se muestran instrucciones de login;
  no se capturan API keys ni se envían correos para comprobar la instalación.
- **Render:** ZIP oficial `2.33.0` para Windows x64. La documentación ofrece `render.cli` en WinGet,
  pero ese ID no estaba disponible en la fuente consultada: se usa la descarga oficial con hash.
  No se ejecutan despliegues, reinicios, jobs ni escrituras de servicios.
- **Cloudflare:** `Cloudflare.cloudflared` para túneles, y Wrangler como dependencia del proyecto.
  Wrangler requiere una plataforma Windows compatible (Windows 11 en la documentación consultada).
  Se pide ruta absoluta, `package.json` y una confirmación del cambio concreto. Después se verifican
  el paquete y el comando local. No se inician túneles, se cambian DNS ni se publican Workers/Pages.
- **Netlify, Vercel, Supabase y Snyk:** se conserva el soporte de la base. En una instalación nueva,
  Supabase usa el ZIP oficial revisado. Si ya existe por npm, se respeta ese gestor y se selecciona
  su shim antes que otra copia de Scoop; no se desinstala ni modifica la otra instalación.

No se revisan ni modifican automáticamente los proyectos al ejecutar el modo 2. Para actualizar
Wrangler se elige de nuevo su proyecto desde el modo 1. El login de un servicio y el funcionamiento
de un proyecto se verifican por separado de la instalación de su CLI.

## Python y bibliotecas

El modo 2 comprueba todas las ramas WinGet contempladas, de 3.10 a 3.15, y actualiza cada una que
esté instalada. No se detiene en la primera rama encontrada. Si hay una rama anterior, puede
ofrecer agregar **3.14 en paralelo**, con confirmación adicional y comprobación del registro final.

3.14 es la rama de nueva instalación verificada en el catálogo WinGet durante este trabajo;
**no se afirma que sea la versión más nueva de Python.org**, que ya publica 3.15. La elección no
elimina 3.12, cambia los paquetes compartidos ni convierte entornos existentes a otra rama.

El venv base permanece en `Forja\Python\venv`. El perfil Flask/OpenCV/NumPy tiene su propio venv
`Forja\Python\web-vision`. Ambos están bajo LOCALAPPDATA y pasan las comprobaciones de aislamiento,
dependencias e imports correspondientes. Los entornos Conda y los venvs de proyectos conservan sus
versiones; migrarlos requiere verificar las dependencias del proyecto.

## React, TypeScript, Vite, Tailwind, PWA, extensiones y PostGIS

Son dependencias o configuraciones de un proyecto, no paquetes que deban instalarse globalmente
para todos los agentes. El modo 4 presenta la receta Vite `react-ts`, la integración actual de
Tailwind con Vite y el uso de entornos Python por proyecto. No crea carpetas de proyecto ni edita
sus lockfiles sin una elección explícita.

PostgreSQL 17 se puede instalar como herramienta opcional. PostGIS necesita una distribución
compatible y habilitar la extensión en la base seleccionada; no se ejecuta SQL desde la Forja.
mongosh es un cliente, no una instalación de MongoDB Server ni un respaldo de bases de datos.
Los proyectos que necesitan servidores adicionales pueden conservar sus recetas Docker.

Rust/Cargo, Build Tools, .NET SDK, Android Studio, JDK y Miniforge son selecciones técnicas opcionales.
El registro del instalador no demuestra que existan todos los workloads, SDK, toolchains o entornos.
Los JDK de Scoop y un rustup externo se reconocen para evitar agregar una segunda instalación;
si no pertenecen a WinGet, su actualización se indica como pendiente del gestor original.

## Integridad de los paquetes nativos

| Paquete | SHA-256 |
|---|---|
| Cursor Agent Windows x64 `2026.10.22-27dcf5f` | `864A8F6A22F8C5EBEDEF8E0CEBA529EAE9A59B3D7F6FCCB75E43E0F5EFC3C147` |
| Render Windows amd64 `2.33.0` | `7A16D74C9F18AC9A1383D9A3A43C3C07B4374DBDDB183F49A05810C130B5CA16` |
| Supabase Windows amd64 `2.122.0` | `60031FD5BF050FC12A0C6AEF68997600D143870F944BF13109C7765DCA329AF8` |

Cursor se contrastó con la URL versionada del instalador oficial inspeccionado y se congeló el hash
de la descarga HTTPS. Los hashes de Render y Supabase se contrastaron con los digest de los assets
de sus releases oficiales. Las tres descargas reales coincidieron y respondieron a su versión.

Antes de extraer se validan todas las entradas ZIP: sin rutas absolutas, traversal, ADS, duplicados,
enlaces o expansión excesiva. El archivo descargado permanece abierto sin permitir escritura.
Se comprueba la versión en staging; el directorio se publica únicamente después del éxito.
Los launchers propios no cambian políticas de ejecución. Las revisiones nuevas de estos ZIP
requieren actualizar el catálogo revisado de Forja; no se descargan automáticamente desde `latest`.

## Evidencia y límites

Validación local en PowerShell 5.1 y 7: **220 casos por shell** (81 de seguridad, 11 flujos,
5 de ejecución nativa, 11 Python, 16 MSI y 96 del catálogo/stack), sin fallos.

Las pruebas aisladas cubren selección y resumen completos, versiones Python coexistentes, rechazo
de instalación de una rama nueva, confirmación fallida, separación de Flask/OpenCV, paquetes npm
malformados, CLI rota, Store sin acceso, elección de proyecto y hashes/rutas ZIP inválidos. Se
conservan las baterías previas de seguridad, MSI y shims CMD bajo política Restricted.

También se extrajeron los tres ZIP reales **solo bajo un directorio de trabajo**, con comprobación
SHA-256 y prueba de versión en Windows PowerShell 5.1. No se instalaron los nuevos agentes ni CLI
en las carpetas de herramientas del usuario. No se iniciaron conversaciones, sesiones ni deploys.

La instalación completa en Windows limpio, disponibilidad futura de paquetes, compatibilidad real
de workloads/proyectos, logins, UAC y reinicios requieren validación propia. El catálogo no copia
datos privados del inventario personal ni promete reconstruir proyectos o bases después de formatear.

## Fuentes oficiales consultadas el 27 de octubre de 2026

- [Cursor Agent CLI](https://prod.cursor.com/docs/cli/installation).
- [Antigravity App, IDE y CLI](https://antigravity.google/docs/getting-started).
- [Retirada de acceso personal de Gemini CLI](https://developers.google.com/gemini-code-assist/docs/deprecations/code-assist-individuals).
- [Grok Bot](https://docs.x.ai/grok-bot/get-started).
- [Codex CLI](https://learn.chatgpt.com/docs/codex/cli) y [app Windows](https://learn.chatgpt.com/docs/app/windows).
- [Neon CLI](https://neon.com/docs/cli/install), [Resend CLI](https://resend.com/docs/cli) y [Render CLI](https://render.com/docs/cli).
- [Release Render 2.33.0](https://github.com/render-oss/cli/releases/tag/v2.33.0) y [Supabase 2.122.0](https://github.com/supabase/cli/releases/tag/v2.122.0).
- [Wrangler por proyecto](https://developers.cloudflare.com/workers/wrangler/install-and-update/).
- [Python para Windows](https://www.python.org/downloads/windows/), [Vite](https://vite.dev/guide/), [Tailwind con Vite](https://tailwindcss.com/docs/installation/using-vite) y [PostGIS en Windows](https://postgis.net/documentation/getting_started/install_windows/).
