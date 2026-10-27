# Corrección v6.1.2 | resumen, Python y avisos de instaladores

## Resumen que omitía errores

El BAT ejecuta el cuerpo PowerShell dentro de un scriptblock. Los contadores iniciales y algunos
incrementos estaban en ese bloque, mientras `Add-UpdResultado` incrementaba las variables de scope
`script`. El resumen leía copias distintas. Por eso una pasada con muchos paquetes y un MSI fallido
podía terminar mostrando `Actualizados: 1`, `Ya al día: 2` y ningún error.

Todos los accesos al estado del resumen usan ahora el mismo scope. Se muestran actualizados,
al día, saltados, pendientes, avisos y errores. Claude compara su versión antes y después para
contar un cambio real. Las pruebas ejecutan el cuerpo en el mismo tipo de scriptblock que el BAT
y verifican los totales: un recorrido sin cambios cuenta los **19 pasos** como al día.

## Librerías Python aisladas

El usuario eligió **aislar Forja y conservar el Python compartido**. Desde esta versión:

- Las cinco librerías se administran en `%LOCALAPPDATA%\Forja\Python\venv`.
- Crear ese entorno requiere confirmación en la primera pasada. Un entorno parcial no se borra
  ni se reemplaza automáticamente. Se rechazan enlaces/junctions y entornos con acceso a paquetes
  del sistema (`include-system-site-packages = true`).
- `pip install` se ejecuta exclusivamente con `Scripts\python.exe` del entorno de Forja.
- Después de instalar se comprueban `pip check`, presencia de los cinco paquetes e imports reales.
  Un exit 0 de pip por sí solo ya no permite informar éxito.
- Los conflictos preexistentes del Python compartido se muestran como **aviso separado**.
  No se cambian Pillow, Docling, Marker o Surya para ocultarlos.

La incompatibilidad observada sigue existiendo en el entorno compartido: Pillow 13 no satisface
los límites de esas versiones de Docling, Marker y Surya. El pdfplumber actual usado por Forja
requiere Pillow >=12.2, mientras Marker/Surya instalados requieren Pillow <11; mantener esas
versiones en un único entorno no permite resolver todo con una sola versión de Pillow.
Separar los entornos evita que las actualizaciones de Forja agraven ese conflicto.

## Avisos npm y comprobación de CLIs

Las versiones observadas respondieron correctamente a su comando de versión:

| Paquete | Versión observada |
|---|---|
| netlify-cli | 27.14.3 |
| vercel | 65.4.0 |
| snyk | 1.1308.3 |
| supabase | 2.122.0 |

Los avisos `npm warn deprecated` pertenecen a dependencias del proveedor: no se parchea su árbol
`node_modules` desde Forja. La advertencia de `allowScripts` tampoco prueba por sí sola un bloqueo:
en la versión npm observada, `strict-allow-scripts` es false por defecto y las entradas no revisadas
pueden ejecutarse con un aviso. Las denegaciones explícitas sí se respetan. Fuente:
[configuración oficial de npm](https://docs.npmjs.com/cli/v11/using-npm/config/#strict-allow-scripts).

Forja no modifica esa política ni agrega una aprobación global. Verifica la versión de la CLI
además de la versión registrada por npm. Un paquete que figura instalado pero cuyo comando falla
se cuenta como error. Una actualización verificada que emitió avisos se cuenta como actualizada
y también en “Con avisos”. La comprobación de versión no sustituye pruebas de deploy/autenticación.

## MongoDB Shell: causa visible y pendiente real

El log del usuario y un reintento puntual mediante WinGet conservaron la versión 2.9.2 e informaron
MSI **1304** al escribir `mongosh.exe` y `.sbom.json`; Windows Installer finalizó con **1603**.
El HRESULT de WinGet `-1978335226` era el envoltorio del fallo, no su explicación completa.

Se consultaron permisos y procesos: en ese momento el usuario y SYSTEM tenían FullControl y no
había un proceso llamado mongosh abierto. Esas observaciones no identifican por sí solas la razón
del rechazo de escritura. No se forzaron ACLs, se cerraron procesos ajenos ni se desinstaló la versión anterior.

La nueva versión detecta mongosh abierto antes de actualizar y lee el log MSI únicamente desde el
directorio oficial de logs de WinGet. Si la misma versión ya dejó un fallo 1304, pide confirmación
para reintentar y permite dejarla pendiente. El fallo no se pierde del resumen.

**Pendiente:** reparar el instalador de MongoDB Shell en el contexto de Windows donde se vaya a
usar. No se afirma que la actualización 2.14.0 haya quedado instalada.

## Evidencia y límites

- Pruebas aisladas en PowerShell 5.1 y 7: seguridad, flujos completos, ejecución CMD bajo Restricted
  y diez escenarios del entorno Python (compatibilidad, imports, aislamiento, copia parcial y cancelación).
- Instalación real de las cinco librerías en un entorno de prueba bajo `work/`: `pip check`,
  presencia de paquetes e imports aprobados.
- También se creó y comprobó el entorno solicitado bajo `%LOCALAPPDATA%`. Windows informó que
  esta sesión redirige físicamente esa ruta al caché del host. El BAT ejecutado desde el Explorador
  comprueba o crea la ubicación correspondiente a ese contexto. No se confirmó una relación causal
  entre esa redirección y el fallo MSI de MongoDB.
- El Python compartido se conservó. No se efectuaron logins, deploys ni cambios de política de scripts.
- Instalación completa de las demás herramientas, UAC/WSL y reinicios en VM siguen pendientes.

[`pip check`](https://pip.pypa.io/en/stable/cli/pip_check/) comprueba compatibilidad de dependencias;
los imports añadidos cubren además el caso en que los metadatos sean correctos pero una librería
no pueda cargarse, por ejemplo por un error de DLL.
