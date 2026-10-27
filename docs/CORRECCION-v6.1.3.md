# v6.1.3 | reparación verificada de MongoDB Shell

## Resultado comprobado en el equipo

La reparación autorizada por el usuario terminó correctamente:

- WinGet pasó de MongoDB Shell **2.9.2** a **2.14.0**, sin actualización disponible.
- `mongosh.exe --norc --version` devolvió **2.14.0**, exit code 0.
- El entorno aislado de Forja pasó `pip check` e imports de sus cinco librerías.
- El Python compartido se conservó, según la elección previa del usuario.

El reintento normal del MSI seguía fallando con 1304/1603. La ejecución acotada del MSI oficial
mediante UAC resolvió el caso observado. Esto demuestra el resultado de esta intervención;
no identifica por sí solo todas las posibles causas del error 1304 en otros equipos.

## Qué hace ahora el BAT

Cuando la misma versión de mongosh tiene un fallo MSI 1304, ofrece una reparación diferente
del reintento normal: descarga el MSI revisado, verifica su SHA-256 y su firma, y solicita UAC
exclusivamente para `msiexec.exe`. El BAT completo sigue rechazando la ejecución como administrador.

La reparación también puede ofrecerse después de detectar un 1304 durante la pasada actual.
Si se rechaza o cancela UAC, queda pendiente y el resto de las herramientas continúa.

## Condiciones de seguridad

- Catálogo acotado a MongoDB Shell **2.14.0 para Windows x64**. Una versión distinta requiere
  revisión del catálogo antes de intentar esta reparación.
- URL permitida: `https://downloads.mongodb.com/compass/mongosh-2.14.0-x64.msi`.
- SHA-256 esperado: `0C433D1C06D0A8377997DA39775C537B0C9A4AD639DCDEA7EDF8B594872516C1`,
  contrastado con el [manifiesto oficial de WinGet](https://github.com/microsoft/winget-pkgs/blob/master/manifests/m/MongoDB/Shell/2.14.0/MongoDB.Shell.installer.yaml).
- Firma Authenticode válida y certificado de MongoDB. Se comprobó también sobre la descarga real.
- El MSI permanece abierto sin permitir escritura ni reemplazo desde la comprobación de hash
  hasta terminar Windows Installer, incluyendo la espera de UAC.
- Los archivos se preparan en una carpeta aleatoria propia bajo `Documents\Forja\Staging`,
  para que la elevación no dependa de la redirección de AppData del host.
- Se mantiene `/norestart`. Exit 3010 queda pendiente de reinicio/verificación; no se reinicia la PC.
- Se comprueba tanto la versión registrada en WinGet como la respuesta del ejecutable con `--norc`.
  La prueba de versión no carga el archivo de inicio del shell ni inicia una conexión a MongoDB.
- No se ejecutan comandos de desinstalación, cambios de ACL, cierre de procesos ajenos o cambios
  en la política de ejecución. Los cambios de archivos del programa los gestiona el MSI del proveedor.
- MSI sin hash/firma correctos no se ejecuta y se elimina el temporal propio no confiable.
  Los intentos incompletos con MSI confiable conservan sus archivos de diagnóstico.

La pertenencia de la cuenta al grupo administrador se reconoce por SID, incluso si el token UAC
marca ese grupo como `deny-only`. No se depende del nombre traducido del grupo ni se pretende
instalar para el usuario usando credenciales de otra cuenta.

## Python: evitar avisos repetidos de otros proyectos

Con el entorno de Forja ya creado, el modo normal verifica ese entorno y no vuelve a ejecutar
`pip check` sobre el Python compartido. El diagnóstico compartido se mantiene para la primera
migración o para una comprobación solicitada expresamente (`-CheckShared` en la función).
Los conflictos anteriores de Docling/Marker/Surya no se modificaron ni se presentan como reparados.

## Verificación

Las baterías cubren hash alterado, firma ausente, publicador distinto, fallo de descarga, MSI fallido,
cancelación UAC, reinicio pendiente, versión no confirmada, CLI sin respuesta, otra cuenta,
mongosh abierto y versión fuera del catálogo. La elevación se simula en esas pruebas.

Además se realizó la reparación real con el consentimiento explícito del usuario y se verificó
el ejecutable. Esa evidencia se distingue de las pruebas simuladas. La instalación completa de
las demás herramientas y los reinicios de WSL en una VM limpia siguen fuera de esta comprobación.

## Segunda pasada confirmada por el usuario

El 27 de octubre de 2026, la salida compartida por el usuario de una nueva ejecución de
**v6.1.3**, modo **[2] Solo actualizar**, confirmó el recorrido completo y su cierre normal:

- **0 actualizados, 19 al día, 0 saltados, 0 pendientes, 0 avisos y 0 errores**.
- MongoDB Shell reconocido en **2.14.0**, sin repetir la reparación.
- Librerías Python verificadas dentro del entorno aislado de Forja.
- Claude Code y WSL informaron estar al día; se alcanzó el resumen y la espera de ENTER.

El resultado de cero actualizaciones es el esperado para esta pasada: no había cambios que
aplicar. Esta evidencia confirma el recorrido de actualización observado, sin extender la
comprobación a instalaciones nuevas, conexiones de servicios o reinicios de WSL.

## Fuentes primarias

- [Opciones de Windows Installer](https://learn.microsoft.com/en-us/windows/win32/msi/standard-installer-command-line-options).
- [Información de grupos con whoami](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/whoami).
- [Verificación Authenticode](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/get-authenticodesignature?view=powershell-5.1).
