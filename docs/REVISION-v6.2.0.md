# Revisión integral de Forja v6.2.0

La revisión cubre instalación, actualización, selección individual, conexiones, descargas,
aislamiento Python y publicación. El objetivo es que una persona pueda preparar su stack
para crear con agentes de IA y volver a actualizarlo entendiendo cada resultado.

## Defectos corregidos

| Caso | Causa y corrección |
|---|---|
| Espera tras cerrar el navegador | El asistente ejecutaba logins dentro del setup. Ahora solo consulta el estado con entrada cerrada y timeout por servicio; muestra el comando para completar el login aparte. T47 permite repetir la comprobación sin instalar. |
| Netlify aparecía desconectado | La CLI devuelve un error de proyecto sin vincular aunque la cuenta esté conectada. Se interpreta el JSON y se acepta exclusivamente la combinación `loggedIn: true`, `NOT_LINKED` y código 1, además de la respuesta válida de código 0. |
| Supabase sin proyectos | Una lista vacía es válida; ya no se buscan encabezados de una tabla para decidir si hay sesión. |
| Posible duplicación de Claude | El setup dependía de npm/PATH antes de comprobar la copia nativa. Ahora busca `.local/bin/claude.exe` primero y comprueba su versión. Si existe pero falla, queda pendiente sin agregar otra copia. |
| Solo actualizar ofrecía crear el venv | Un entorno ausente se salta con el código T para prepararlo. Un entorno existente puede gestionarse sin depender del Python global en PATH. T32/T34 sí permiten prepararlo individualmente. |
| Error de inventario confundido con ausencia | Se distingue una consulta npm fallida de una lista vacía. WinGet no inicia una instalación si no pudo consultar su inventario; después comprueba el registro antes de informar éxito. |
| Posible descenso de versión npm | Una versión local superior a `latest` o un canal especial queda pendiente con explicación; no se cambia automáticamente de canal. |
| JSON mezclado con avisos | El ejecutor conserva stdout y stderr separados. Las consultas usan stdout para el formato estructurado, sin publicar respuestas crudas de cuentas. |

Las descargas conservan HTTPS, validación SHA-256 para archivos nativos revisados, controles
de extracción y barra de bytes reales. Los gestores muestran actividad cuando no proporcionan
un total. No se modificaron las políticas de ejecución, la elevación limitada de WSL/MSI,
los paquetes del Python compartido ni la configuración de los agentes.

## Evidencia

- 367 casos por shell en Windows PowerShell 5.1 y PowerShell 7, distribuidos en diez suites.
- Los flujos completos usan proveedores simulados; comprueban estados finales, contadores y
  llamadas. T47 se recorre con los seis servicios pendientes y no dispara instalaciones.
- Las pruebas de procesos reales usan hijos inertes para verificar EOF, timeout, preservación
  de procesos ajenos, separación de salida y argumentos con caracteres especiales.
- Una consulta real de solo lectura confirmó Netlify conectado fuera de un proyecto; Vercel
  retornó pendiente sin abrir login ni bloquear la consola. No se guardaron datos de cuenta.
- Las tres descargas nativas del catálogo conservaron las verificaciones previas de SHA-256 y
  respuesta de versión realizadas bajo un directorio de trabajo, sin instalación global.

## Límites

La suite no sustituye un recorrido de todos los instaladores en una VM Windows recién
formateada, con UAC, reinicios, políticas corporativas, autenticaciones y workloads. La prueba
real de conexión tampoco certifica permisos de deploy ni funcionamiento de proyectos.

La app Store se actualiza desde Store. Rust/JDK de otros gestores se preservan y muestran
pasos manuales. Las CLI nativas con hash fijo requieren una nueva revisión del catálogo para
ofrecer otra versión. Los servicios cloud se vinculan según el proyecto; Forja no crea bases,
publica sitios ni envía correos durante la preparación.

## Referencias

- [Netlify status y JSON](https://cli.netlify.com/commands/status/).
- [Código oficial del comando Netlify](https://github.com/netlify/cli/blob/main/src/commands/status/status.ts); también se revisó la implementación instalada 27.15.0.
- [Vercel whoami](https://vercel.com/docs/cli/whoami) y [modo no interactivo](https://vercel.com/docs/cli/global-options#non-interactive).
- [GitHub auth status](https://cli.github.com/manual/gh_auth_status).
- [Supabase projects list](https://supabase.com/docs/reference/cli/supabase-projects-list).
