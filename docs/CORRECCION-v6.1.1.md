# Corrección v6.1.1 | segunda pasada y cierre en npm

El uso real de v6.1 mostró dos defectos que las pruebas iniciales con comandos simulados no cubrían.

## Causas reproducidas

1. `winget list --id Git.Git --exact --source winget --upgrade-available` devuelve **código 0**
   y `No installed package found matching input criteria.` cuando Git ya está al día.
   La Forja esperaba una fila o un código de error específico, y anunciaba que falló la consulta.
   También se observó que PowerShell 7 aparecía en el inventario general pero no con ciertos filtros
   por fuente/ID exacto. No se debe confundir ese resultado con ausencia de la herramienta.
2. Windows PowerShell selecciona `C:\Program Files\nodejs\npm.ps1` al invocar `npm`.
   En la configuración Restricted del equipo ese shim está bloqueado. La excepción escapaba
   de la limpieza opcional de Claude y el catch del lanzador cerraba toda la pasada.
   Las CLIs instaladas mediante npm pueden tener el mismo conflicto `.ps1` / `.cmd`.

## Correcciones

- Se lee la tabla de aplicaciones instaladas, conservando la versión instalada y la disponible.
  La ausencia de columna de actualización en una fila válida significa “ya al día”.
- Si el filtro exacto no encuentra el paquete, se contrasta su ID visible con el inventario general.
  Un resultado sin información verificable sigue siendo error o ausente, nunca éxito inventado.
- Instalar/actualizar mantiene `--id`, `--exact` y `--source winget`; ampliar la lectura del inventario
  no amplía las fuentes desde las que se instala.
- npm, pnpm, Claude, Netlify, Vercel, Supabase y Snyk se resuelven como aplicaciones `.exe` / `.cmd`.
  No se modifica ExecutionPolicy ni se ejecuta su shim `.ps1` para sortearla.
- Una desinstalación npm fallida se registra como error y la pasada continúa hasta el resumen.
  No se borran archivos manualmente. La instalación nativa de Claude requiere un `claude.exe`
  existente; una carpeta de caché por sí sola ya no cuenta como instalación nativa.
- Después de un upgrade WinGet o npm exitoso se vuelve a consultar la versión instalada.
  Si no coincide con la esperada, se informa que falta verificar. Claude también informa su versión.
- El lanzador restablece solo para su proceso la búsqueda de módulos de Windows PowerShell,
  para evitar cargar módulos incompatibles heredados de una sesión de PowerShell 7.

## Evidencia local

Consultas reales de solo lectura realizadas el 27/10/2026 con las funciones corregidas:

| Herramienta | Versión instalada observada | Actualización disponible observada |
|---|---|---|
| PowerShell | 7.6.9.0 | Ninguna en la consulta |
| Git | 2.56.0.3 | Ninguna en la consulta |
| Node LTS | 24.22.1 | Ninguna en la consulta |
| Docker Desktop | 4.97.0 | Ninguna en la consulta |
| MongoDB Shell | 2.9.2 | 2.14.0 |
| Ollama | 0.40.11 | Ninguna en la consulta |
| FFmpeg | 9.0.2 | Ninguna en la consulta |
| npm | 11.19.1, ejecutado por `npm.cmd` | No se consultó actualización |

Esas versiones describen la consulta realizada, no el estado de otros equipos ni una instalación
completa repetida durante la prueba. El error MSI 1603 de MongoDB aportado por el usuario sigue
siendo un fallo de ese instalador; esta corrección no afirma repararlo ni desinstala MongoDB.

## Regresión

- `security.tests.ps1`: **71 PASS / 0 FAIL** en Windows PowerShell 5.1 y PowerShell 7.
- `flows.tests.ps1`: **8 PASS / 0 FAIL** en ambos; incluye segunda pasada al día y excepción de
  limpieza de Claude, comprobando que se ejecutan pasos posteriores y aparece el resumen.
- `native-tools.tests.ps1`: **5 PASS / 0 FAIL** desde ambos shells. Lanza Windows PowerShell real
  bajo `ExecutionPolicy Restricted`, comprueba el bloqueo de un `npm.ps1` de prueba y ejecuta
  únicamente un `npm.cmd` inerte. Cubre stderr con exit 0, exit 1603, comando ausente y continuación.
- Los flujos sustituyen explícitamente la frontera de ejecución de CLIs en una fixture en memoria.
  Las pruebas nativas no usan npm real para instalar/desinstalar: solo archivos CMD de prueba.

La prueba completa de instalación, WSL/UAC, reinicio y autenticación real en VM sigue pendiente.

## Fuentes de comportamiento

- [WinGet list: la columna de actualización no se muestra si no hay actualización](https://learn.microsoft.com/en-us/windows/package-manager/winget/list).
- [PowerShell: resolución de comandos y uso de una extensión explícita](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_command_precedence?view=powershell-5.1).
