# Seguridad y migraciÃ³n a v6.1.3

La Forja instala software de terceros y configura herramientas en tu cuenta de Windows.
Ejecutala con doble clic, desde una cuenta sin elevar. Los instaladores de paquetes pueden
mostrar su propio UAC. La Forja eleva explÃ­citamente solo la instalaciÃ³n de WSL y, si se acepta
la reparaciÃ³n de mongosh, `msiexec.exe` con el MSI oficial tras verificar hash y firma.
Si se inicia toda la Forja como administrador, se detiene antes del menÃº.

## QuÃ© protege esta versiÃ³n

- Arranque con Windows PowerShell 5.1 del sistema, sin depender de tener PowerShell 7 instalado.
- El BAT se lee en memoria. No crea VBS/PS1 temporales ni cambia la polÃ­tica de ejecuciÃ³n del equipo.
- ENTER, 0 o una opciÃ³n desconocida salen sin instalar. El modo 3 consulta rutas y presencia; el modo 4 muestra guías sin ejecutarlas.
- Descargas de skills por SHA de 40 caracteres y proveedor permitido. No se ejecuta su contenido.
- Temporales Ãºnicos en `%LOCALAPPDATA%\Forja\Staging`. Solo se limpian los creados durante esa ejecuciÃ³n.
- ValidaciÃ³n de junctions/enlaces en padres, origen, destino y limpieza. Las skills existentes se saltean.
- Cada skill se prepara fuera del directorio activo y se mueve al destino al completar la copia.
- Sin pedir tokens ni escribirlos como variables persistentes. Snyk usa `snyk auth` por navegador.
- Instalaciones y consultas fallidas no deben presentarse como una actualizaciÃ³n exitosa.

Estas defensas no aÃ­slan procesos maliciosos que ya controlan tu misma cuenta de Windows.
Una verificaciÃ³n de ruta seguida de una operaciÃ³n de archivos no es una barrera contra todas
las carreras de un atacante con los mismos permisos. No ejecutes el instalador desde una
cuenta comprometida ni habilites skills de origen desconocido.

## Si ya usaste v6.0 o anteriores

La actualizaciÃ³n del BAT **no elimina ni revoca credenciales anteriores**. Hacelo desde la cuenta
correcta, revisando primero quÃ© otras herramientas dependen de ellas:

1. En GitHub â†’ Settings â†’ Developer settings â†’ Personal access tokens, identificÃ¡ el token
   creado para el MCP anterior. Si tiene acceso amplio o pudo quedar visible en pantalla/logs,
   reemplazalo por una credencial limitada a los repositorios necesarios y revocÃ¡ el anterior
   una vez verificada la migraciÃ³n. No publiques el token ni lo pegues en una issue.
2. En Windows â†’ Variables de entorno de usuario, revisÃ¡ `GITHUB_PERSONAL_ACCESS_TOKEN`.
   Cuando ningÃºn consumidor la necesite, eliminÃ¡ esa variable. CerrÃ¡ las terminales y apps que
   heredaron el valor; borrarla del registro no la quita de procesos ya abiertos.
3. RevisÃ¡ la entrada `github` de Claude con `claude mcp get github`. Su salida puede contener
   credenciales: no la compartas completa. La Forja no reemplaza tu configuraciÃ³n existente.
   Si sigue usando el servidor antiguo por NPX, migrÃ¡ siguiendo la
   [guÃ­a oficial de GitHub](https://github.com/github/github-mcp-server/blob/main/docs/installation-guides/install-claude.md).
   EmpezÃ¡ con repositorios y permisos mÃ­nimos, y [modo solo lectura](https://github.com/github/github-mcp-server/blob/main/docs/server-configuration.md#read-only-mode).
   La autenticaciÃ³n de `gh` no autentica automÃ¡ticamente un MCP separado.
4. Si pegaste un token de Snyk en versiones anteriores, revisÃ¡ dÃ³nde quedÃ³ guardado y considerÃ¡
   revocarlo desde Snyk despuÃ©s de comprobar `snyk auth` con OAuth. El proveedor administra
   sus credenciales; la Forja no las rota ni las borra.
5. RevisÃ¡ grabaciones de terminal y logs anteriores antes de compartirlos. Las versiones viejas
   pedÃ­an tokens mediante `Read-Host` visible y pasaban el token de Snyk por argumentos de proceso.

## LÃ­mites y verificaciÃ³n de paquetes

Las librerÃ­as Python se instalan con el intÃ©rprete del venv de Forja, sin actualizar paquetes
del Python compartido. Antes de dar Ã©xito se verifican dependencias e imports. Los conflictos
preexistentes de otros entornos se muestran como avisos; conservarlos no significa haberlos reparado.
Un fallo MSI de mongosh se conserva como error o pendiente y no dispara cambios automÃ¡ticos de permisos.

WinGet utiliza ID exacto y fuente `winget`; la app ChatGPT/Codex usa el ID oficial de `msstore`, conservando las validaciones de hash de su gestor.
npm y pip siguen instalando paquetes y dependencias publicados por terceros, que pueden ejecutar
scripts de instalaciÃ³n. El modo actualizar requiere confirmaciÃ³n y no representa una certificaciÃ³n
de todas las versiones descargadas. Este repositorio no tiene un Ã¡rbol npm/pip propio ni un lockfile
que permita afirmar que todas las instalaciones futuras estÃ¡n libres de vulnerabilidades.

Las skills tienen revisiones fijas; eso vuelve repetible la descarga, pero no certifica todo el
cÃ³digo o instrucciones de Anthropic. Los cambios de esos SHA requieren revisiÃ³n y pruebas.
Un perfil de Windows con skills en otra unidad puede impedir el movimiento final; se informa error
y la skill incompleta no se publica. Una limpieza rechazada conserva el temporal y muestra su ruta.

## Paquetes nativos y proyectos en v6.2.0

Los ZIP del catálogo tienen URL/versiones y SHA-256 fijos. La descarga se mantiene abierta sin
compartir escritura mientras se verifica y extrae. Se rechazan traversal, rutas absolutas,
ADS, entradas duplicadas, enlaces y excesos de expansión antes de crear archivos del paquete.
La versión del ejecutable debe coincidir antes de promover el directorio nuevo; un directorio
existente sin comprobante compatible no se pisa. Esto valida el artefacto revisado, no certifica
todo el comportamiento del software del proveedor ni aísla procesos del mismo usuario.

Los launchers propios no agregan Bypass ni ejecutan el bootstrap remoto de los proveedores.
La ubicación de herramientas se muestra explícitamente, sin persistir cambios del PATH.
Las instalaciones de otros gestores no se eliminan ni se migran automáticamente.

Wrangler requiere elegir un proyecto existente y confirmar el cambio concreto en sus dependencias.
No se ejecuta npx para descargar software implícitamente, ni se recorre el disco modificando proyectos.
Las recetas de frontend y conexiones no realizan despliegues ni solicitudes de escritura a servicios.
El perfil Flask/OpenCV usa un venv distinto; el Python compartido y Conda permanecen separados.

## Transporte de descargas y progreso

El transporte usa HttpClient con lectura en streaming, límites de tamaño y tiempos de espera.
Valida HTTPS y ausencia de credenciales en cada salto, con un máximo de cinco redirecciones;
el MSI de MongoDB no permite redirecciones. No altera la validación de certificados. El destino
se crea sin sobrescribir y rechaza rutas reparse; se mantienen los controles de hash, ZIP y firma.

La barra porcentual solo representa bytes recibidos, no el éxito de la instalación. Los gestores
externos muestran actividad cuando no hay total medible. Sus procesos usan ejecutables absolutos,
argumentos nativos y el directorio del sistema. npm se lanza mediante Node y npm-cli.js, sin shell
de comandos intermedio ni cambios de allowScripts. Se conserva la salida y el código del proveedor.

## Probar antes de distribuir

En una copia del repositorio:

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\tests\security.tests.ps1
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\tests\flows.tests.ps1
pwsh -NoProfile -File .\tests\security.tests.ps1
pwsh -NoProfile -File .\tests\flows.tests.ps1
pwsh -NoProfile -File .\tests\native-tools.tests.ps1
pwsh -NoProfile -File .\tests\python-environment.tests.ps1
pwsh -NoProfile -File .\tests\msi-repair.tests.ps1
pwsh -NoProfile -File .\tests\stack.tests.ps1
pwsh -NoProfile -File .\tests\progress-individual.tests.ps1
```

`RemoteSigned` en ese comando afecta solo al proceso de prueba; no modifica polÃ­ticas persistentes
ni prevalece sobre una polÃ­tica corporativa. Las pruebas usan mocks, archivos temporales propios
y un payload BAT inerte. Los recorridos del cuerpo del instalador usan herramientas simuladas
y omiten el guard de administrador solo en la fixture en memoria para poder correr en CI.
No inician sesiones, instalan paquetes ni llaman servicios reales.

Antes de una release, falta ademÃ¡s una prueba manual en una VM descartable de Windows 10/11:
equipo sin PowerShell 7, instalaciÃ³n de WSL/UAC, reinicio, setup, segunda ejecuciÃ³n y actualizaciÃ³n.
Probar logins con cuentas de prueba separadas. CI o mocks no demuestran que los proveedores hayan
instalado/autenticado correctamente en una mÃ¡quina real.

## Reportar un problema

RevisÃ¡ la pestaÃ±a Security del repositorio y usÃ¡ el reporte privado si estÃ¡ habilitado. Si no lo estÃ¡,
contactÃ¡ al autor mediante [su sitio](https://ragustingarcia.com/) sin incluir secretos o datos personales.
Una issue pÃºblica puede describir un problema general, pero no debe contener credenciales,
salidas completas de autenticaciÃ³n ni detalles sensibles de una cuenta.
