# Auditoría y correcciones de seguridad | La Forja del Desarrollador

Fecha: 27 de octubre de 2026. Base revisada: `39204a10fc5ce3027a3180cc69446266f9cefe7a` (v6.0).
Actualización propuesta: v6.1. El informe describe código y pruebas; no acredita una release publicada.

## Resultado

Se corrigieron riesgos de privilegios, exposición de tokens, manejo de temporales, descarga de skills
y falsos éxitos de instalación. No se encontró evidencia de compromiso en el material revisado.
No se afirma que una máquina donde se ejecutó v6.0 esté libre de incidentes o credenciales expuestas.

La aplicación es un instalador local de Windows: un BAT híbrido con PowerShell y una skill propia.
No hay servidor HTTP, login web, base de datos ni aplicación Node/Python propia. WinGet, npm y pip
son herramientas invocadas para instalar software ajeno. Headers/CSP, RLS, CORS y rate limiting
de un servidor propio no aplican a este repositorio.

## Alcance y método

- Lectura del árbol completo y revisión de los comandos de instalación, actualización, configuración,
  vinculación y skills. Comparación con la base Git indicada.
- Revisión por patrones de 13 commits y 35 blobs históricos distintos, buscando tokens de GitHub,
  claves cloud, tokens de proveedores, claves privadas y URLs de base de datos con contraseña.
  **Cero coincidencias en esos patrones**; no es una prueba de ausencia de todo tipo de secreto.
- Revisión del ZIP aportado como referencia, sin ejecutar ni instalar su MCP, dashboard o scripts.
  SHA-256 del ZIP: `22f417c937ee51d7ec88a05f12aa7c3d2fe2ba04d9fd6b30f79c04a3814ae9b5`.
  Sus instrucciones se distinguieron de la solicitud del usuario, que autorizó auditar y mejorar.
  Su escáner genérico omite `.bat` en `TEXT_EXT`, por lo que no habría cubierto el ejecutable principal.
  La revisión del BAT se hizo expresamente; no se usó un resultado genérico como certificado de seguridad.
- Fuentes oficiales para el comportamiento actual de GitHub MCP, Snyk OAuth y opciones/errores de WinGet.
- Pruebas con mocks y fixtures locales. No se ejecutaron instaladores reales, logins, rotaciones,
  cambios de registro, limpieza de instalaciones ni operaciones de producción en la computadora del usuario.

## Hallazgos y correcciones

La prioridad indica impacto y condiciones necesarias, no un ataque remoto demostrado.
No se confirmó una vulnerabilidad crítica explotable desde Internet.

| ID | Prioridad | Evidencia en v6.0 | Consecuencia y condición | Cambio en v6.1 |
|---|---|---|---|---|
| F01 | Alta | Encabezado BAT eleva todo; npm/pip/skills/logins heredan el token de administrador | Un paquete o herramienta maliciosa obtiene los mismos privilegios elevados que el instalador | Sesión normal obligatoria; UAC explícito solo para instalar WSL; otros proveedores gestionan su propio instalador |
| F02 | Alta | `%TEMP%\getadmin.vbs` y `%TEMP%\forja_setup.ps1` tienen nombres fijos | Colisiones y posible sustitución local entre escritura y ejecución; no se reprodujo una explotación de UAC | Lectura del BAT en memoria mediante PowerShell del sistema; sin esos archivos ni bypass de política |
| F03 | Alta | `Read-Host` visible para PAT y Snyk; PAT en entorno de usuario; Snyk por argumentos; instrucción de PAT classic `repo` completo | Exposición en pantalla/procesos y credencial persistente heredada por otros programas | Sin captura de tokens; Snyk OAuth; MCP manual con mínimo privilegio; guía para revisar/revocar credenciales anteriores |
| F04 | Media | MCP por `npx -y @modelcontextprotocol/server-github` y skills clonadas de ramas cambiantes | Código/instrucciones variables y servidor antiguo; no se verificó una CVE concreta en una instalación del usuario | Se retira ese registro automático; proveedores permitidos, SHA completo y verificación del checkout para skills |
| F05 | Alta | Borrado recursivo de temporales fijos y de `AppData\Roaming\npm\node_modules\@anthropic-ai\claude-code` como fallback | Archivos ajenos o rutas enlazadas pueden afectarse; depende del estado local de las rutas | Solo espacios aleatorios registrados por la ejecución; validación previa de árbol; desinstalación exclusivamente por npm con confirmación |
| F06 | Media | Copia recursiva de skills sin validar enlaces ni comprobar cada fallo | Salida del destino previsto por enlaces locales y skills incompletas que luego se saltean como existentes | Rechazo de reparse points en padres/contenido; staging y movimiento final sin reemplazar el destino |
| F07 | Media | `Install-Winget` emite stdout además de `$false`; npm verifica presencia anterior; consulta WinGet no comprueba su fallo; WSL setup anuncia éxito sin comprobar salida | PowerShell puede tomar un array de salida como verdadero y declarar OK una instalación fallida | Contratos de retorno escalares, exit codes, consulta de actualización diferenciada, WSL pendiente de reinicio/verificación y código de salida final |
| F08 | Media | El arranque requiere `pwsh` antes del paso que lo instala; se reescriben settings de Terminal/registro y se renombran alias Python | Fallo en equipo limpio y cambios ajenos al objetivo de instalación sin respaldo | Arranque con Windows PowerShell 5.1; ajustes manuales de Terminal; no se renombran alias |
| F09 | Media | La skill distribuida recomienda elevación global, temporales fijos, tokens visibles y WSL sin revisar salida | Nuevos instaladores generados con esa skill reproducen los defectos | Skill actualizada conservando autoría; las copias locales previas no se sobrescriben y requieren migración manual |
| F10 | Baja | No hay CI ni exclusiones para `.env`/logs | Regresiones no detectadas y mayor posibilidad de publicar archivos sensibles accidentalmente | CI Windows en dos shells, Action por SHA, permisos de lectura, credenciales no persistidas, Dependabot para Actions y `.gitignore` |

También se agregó una salida segura por defecto (ENTER), confirmación exacta para cambios y un modo
de diagnóstico que lista rutas sin ejecutar las herramientas. La actualización de PowerShell 7 ocurre
en la misma ventana, ya que el BAT arranca con Windows PowerShell 5.1.

## Pruebas ejecutadas

| Prueba | PowerShell 5.1 | PowerShell 7 | Qué demuestra |
|---|---|---|---|
| `tests/security.tests.ps1` | 62 PASS / 0 FAIL | 62 PASS / 0 FAIL | Retornos escalares, fallos de gestor, versión npm concreta, confirmación, tokens no emitidos, temporales propios, junctions, conservación de skills, copia parcial y SHA |
| `tests/flows.tests.ps1` | 6 PASS / 0 FAIL | 6 PASS / 0 FAIL | Setup correcto/fallido, actualización fallida, cancelar, diagnóstico y salida por defecto; todo con herramientas simuladas |
| Launcher CMD + PowerShell del sistema | Incluido en los 62 | Incluido en los 62 | Payload inerte en ruta con espacios, apóstrofe, `&`, `!`, paréntesis y `%`; conserva exit 7 |
| Revisión de diff y parser | Sin errores al cierre local | Sin errores al cierre local | Sintaxis y cambios propuestos; no demuestra instalaciones reales |

Los recorridos usan el cuerpo del producto con mocks y una fixture que omite el guard de administrador
para correr también en runners elevados. No se cambió ese guard en el producto. Las pruebas de archivos
crean solo carpetas propias y verifican que los centinelas fuera del temporal permanezcan intactos.

## Cobertura del kit de 25 controles

| Control | Aplicación en este proyecto / estado |
|---|---|
| ACC-01 | Sin objetos web/IDOR. Skills existentes protegidas contra reemplazo. |
| ACC-02 | Sin passwords propias; autenticación delegada a proveedores. MFA de las cuentas no inspeccionado. |
| ACC-03 | Sin sesiones/JWT propios. Almacenamiento interno de credenciales de terceros fuera del alcance. |
| ACC-04 | Corregida elevación global; revisar permisos de tokens antiguos manualmente. |
| ACC-05 | CSRF no aplica: sin servidor web propio. |
| INP-06 | SQL/NoSQL no aplica: sin base propia. |
| INP-07 | XSS no aplica: sin render web. |
| INP-08 | Opciones de menú, confirmación, nombre de skill, adaptador y revisiones validados. |
| INP-09 | Sin uploads web. Copia local de skills validada antes de publicarla. |
| INP-10 | Rutas del BAT no interpoladas como código; limpieza confinada; pruebas de junctions y traversal. |
| DAT-11 | Descargas Git por HTTPS; sin desactivar TLS o hashes de WinGet. Infraestructura de terceros no auditada. |
| DAT-12 | Ya no se piden tokens. Los proveedores pueden mostrar su propia identidad durante login. |
| DAT-13 | Cero patrones de secretos detectados en historial; migración de PAT/env anteriores pendiente de cada usuario. |
| DAT-14 | Sin BD/backups propios. No se borran skills previas; configuración de Terminal no se reescribe. |
| CFG-15 | Sin lockfile de aplicación propio. Versiones instaladas dinámicamente por gestores: CVEs no certificables para todas las máquinas. |
| CFG-16 | Sin servidor/debug propio. Bootstrap sin scripts fijos ni cambios de política persistente. |
| CFG-17 | Headers no aplica: no se publica un sitio desde este repo. |
| CFG-18 | CORS no aplica. |
| CFG-19 | CI por SHA y lectura; revisiones fijas de skills. Reglas y protecciones de rama requieren comprobación del administrador. |
| API-20 | APIs de login delegadas a proveedores; sin endpoints propios. |
| API-21 | Rate limiting no aplica a un endpoint propio; no se hicieron pruebas de abuso de proveedores. |
| API-22 | No recibe URLs arbitrarias para fetch de skills: allowlist exacta de dos repositorios HTTPS. |
| API-23 | Sin webhooks. Comprobación de errores de comandos de terceros; comportamiento real pendiente de VM. |
| AI-24 | Retirado MCP antiguo por NPX; mínimo privilegio/manual; skills externas tratadas como instrucciones que deben revisarse. No hay aislamiento completo frente a prompt injection. |
| MON-25 | Resúmenes y exit codes verificables; sin logs propios con secretos. Telemetría/alertas centralizadas no forman parte del instalador. |

## Límites y tareas pendientes antes de release

1. Ejecutar prueba manual en VM descartable Windows 10/11: sin PowerShell 7, UAC de WSL,
   reinicio, setup completo, repetición y modo actualizar. Confirmar comportamiento de los
   instaladores reales y sus scopes de usuario/máquina. Los mocks no prueban estos efectos.
2. Probar logins reales en cuentas de prueba, especialmente Snyk OAuth y las CLIs actuales.
   `whoami --experimental` puede variar por versión: un fallo queda pendiente, no conectado.
3. Revisar los tokens/configuraciones que pudieron quedar de v6.0 con [SECURITY.md](../SECURITY.md).
   La nueva versión no revoca ni borra secretos previos. No se inspeccionaron los del usuario.
4. Comprobar protecciones de `main` y exigir los checks de Windows antes de mergear.
   La consulta de rulesets devolvió `[]`; la protección clásica devolvió 403 por permisos de
   integración. **No se deduce que `main` esté desprotegida** a partir de esa respuesta.
5. Revisar las actualizaciones de proveedores al publicar. No hay un catálogo de versiones
   instaladas por usuario ni lockfile global con el que afirmar ausencia de CVEs. No se
   instaló el stack de 21 herramientas para inventariarlo durante esta auditoría.

Los hashes fijos hacen repetible la descarga de skills. No se auditó exhaustivamente cada
script del pack externo de Anthropic. Las validaciones de rutas no son una frontera frente a
un proceso malicioso que ya controle la misma cuenta. Si aparece un enlace durante la limpieza,
se conserva el temporal para revisión en vez de intentar forzar el borrado.

## Fuentes primarias consultadas

- [GitHub MCP para Claude](https://github.com/github/github-mcp-server/blob/main/docs/installation-guides/install-claude.md)
  y [configuración / solo lectura](https://github.com/github/github-mcp-server/blob/main/docs/server-configuration.md).
- [Servidor MCP GitHub anterior en archivo](https://github.com/modelcontextprotocol/servers-archived/tree/main/src/github).
- [Snyk auth y OAuth](https://docs.snyk.io/developer-tools/snyk-cli/commands/auth),
  [prueba oficial de whoami](https://github.com/snyk/cli/blob/main/cliv2/pkg/core/main_test.go).
- [WinGet install: ID exacto, fuente y controles de hash](https://learn.microsoft.com/en-us/windows/package-manager/winget/install),
  [códigos oficiales de error](https://github.com/microsoft/winget-cli/blob/master/src/AppInstallerSharedLib/Public/AppInstallerErrors.h).
