# Seguridad y migración a v6.1

La Forja instala software de terceros y configura herramientas en tu cuenta de Windows.
Ejecutala con doble clic, desde una cuenta sin elevar. Los instaladores de paquetes pueden
mostrar su propio UAC; la Forja solo eleva explícitamente `wsl.exe --install --no-distribution`.
Si se inicia toda la Forja como administrador, se detiene antes del menú.

## Qué protege esta versión

- Arranque con Windows PowerShell 5.1 del sistema, sin depender de tener PowerShell 7 instalado.
- El BAT se lee en memoria. No crea VBS/PS1 temporales ni cambia la política de ejecución del equipo.
- ENTER, 0 o una opción desconocida salen sin instalar. El modo 3 solo lista rutas de herramientas.
- Descargas de skills por SHA de 40 caracteres y proveedor permitido. No se ejecuta su contenido.
- Temporales únicos en `%LOCALAPPDATA%\Forja\Staging`. Solo se limpian los creados durante esa ejecución.
- Validación de junctions/enlaces en padres, origen, destino y limpieza. Las skills existentes se saltean.
- Cada skill se prepara fuera del directorio activo y se mueve al destino al completar la copia.
- Sin pedir tokens ni escribirlos como variables persistentes. Snyk usa `snyk auth` por navegador.
- Instalaciones y consultas fallidas no deben presentarse como una actualización exitosa.

Estas defensas no aíslan procesos maliciosos que ya controlan tu misma cuenta de Windows.
Una verificación de ruta seguida de una operación de archivos no es una barrera contra todas
las carreras de un atacante con los mismos permisos. No ejecutes el instalador desde una
cuenta comprometida ni habilites skills de origen desconocido.

## Si ya usaste v6.0 o anteriores

La actualización del BAT **no elimina ni revoca credenciales anteriores**. Hacelo desde la cuenta
correcta, revisando primero qué otras herramientas dependen de ellas:

1. En GitHub → Settings → Developer settings → Personal access tokens, identificá el token
   creado para el MCP anterior. Si tiene acceso amplio o pudo quedar visible en pantalla/logs,
   reemplazalo por una credencial limitada a los repositorios necesarios y revocá el anterior
   una vez verificada la migración. No publiques el token ni lo pegues en una issue.
2. En Windows → Variables de entorno de usuario, revisá `GITHUB_PERSONAL_ACCESS_TOKEN`.
   Cuando ningún consumidor la necesite, eliminá esa variable. Cerrá las terminales y apps que
   heredaron el valor; borrarla del registro no la quita de procesos ya abiertos.
3. Revisá la entrada `github` de Claude con `claude mcp get github`. Su salida puede contener
   credenciales: no la compartas completa. La Forja no reemplaza tu configuración existente.
   Si sigue usando el servidor antiguo por NPX, migrá siguiendo la
   [guía oficial de GitHub](https://github.com/github/github-mcp-server/blob/main/docs/installation-guides/install-claude.md).
   Empezá con repositorios y permisos mínimos, y [modo solo lectura](https://github.com/github/github-mcp-server/blob/main/docs/server-configuration.md#read-only-mode).
   La autenticación de `gh` no autentica automáticamente un MCP separado.
4. Si pegaste un token de Snyk en versiones anteriores, revisá dónde quedó guardado y considerá
   revocarlo desde Snyk después de comprobar `snyk auth` con OAuth. El proveedor administra
   sus credenciales; la Forja no las rota ni las borra.
5. Revisá grabaciones de terminal y logs anteriores antes de compartirlos. Las versiones viejas
   pedían tokens mediante `Read-Host` visible y pasaban el token de Snyk por argumentos de proceso.

## Límites y verificación de paquetes

WinGet utiliza ID exacto y fuente `winget`, conservando las validaciones de hash de su gestor.
npm y pip siguen instalando paquetes y dependencias publicados por terceros, que pueden ejecutar
scripts de instalación. El modo actualizar requiere confirmación y no representa una certificación
de todas las versiones descargadas. Este repositorio no tiene un árbol npm/pip propio ni un lockfile
que permita afirmar que todas las instalaciones futuras están libres de vulnerabilidades.

Las skills tienen revisiones fijas; eso vuelve repetible la descarga, pero no certifica todo el
código o instrucciones de Anthropic. Los cambios de esos SHA requieren revisión y pruebas.
Un perfil de Windows con skills en otra unidad puede impedir el movimiento final; se informa error
y la skill incompleta no se publica. Una limpieza rechazada conserva el temporal y muestra su ruta.

## Probar antes de distribuir

En una copia del repositorio:

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\tests\security.tests.ps1
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\tests\flows.tests.ps1
pwsh -NoProfile -File .\tests\security.tests.ps1
pwsh -NoProfile -File .\tests\flows.tests.ps1
```

`RemoteSigned` en ese comando afecta solo al proceso de prueba; no modifica políticas persistentes
ni prevalece sobre una política corporativa. Las pruebas usan mocks, archivos temporales propios
y un payload BAT inerte. Los recorridos del cuerpo del instalador usan herramientas simuladas
y omiten el guard de administrador solo en la fixture en memoria para poder correr en CI.
No inician sesiones, instalan paquetes ni llaman servicios reales.

Antes de una release, falta además una prueba manual en una VM descartable de Windows 10/11:
equipo sin PowerShell 7, instalación de WSL/UAC, reinicio, setup, segunda ejecución y actualización.
Probar logins con cuentas de prueba separadas. CI o mocks no demuestran que los proveedores hayan
instalado/autenticado correctamente en una máquina real.

## Reportar un problema

Revisá la pestaña Security del repositorio y usá el reporte privado si está habilitado. Si no lo está,
contactá al autor mediante [su sitio](https://ragustingarcia.com/) sin incluir secretos o datos personales.
Una issue pública puede describir un problema general, pero no debe contener credenciales,
salidas completas de autenticación ni detalles sensibles de una cuenta.
