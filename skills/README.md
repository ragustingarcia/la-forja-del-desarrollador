# Skills de la Forja

Skills de Claude Code que el instalador ofrece copiar a `~/.claude/skills/`.
Una skill es una capacidad que Claude Code carga **solo cuando la necesita** —
por eso ahorran tokens frente a instrucciones permanentes en `CLAUDE.md`.

## Estructura

| Carpeta | Contenido | Autoría |
|---|---|---|
| `rodo/` | Skills desarrolladas por **Rodolfo Agustín García** ([ragustingarcia.com](https://ragustingarcia.com/)) | Propia, distribuidas con crédito |
| *(no vendorizadas)* | Skills oficiales de Anthropic (docx, pdf, xlsx, pptx, skill-creator) | El instalador las clona directo de [anthropics/skills](https://github.com/anthropics/skills) — no se redistribuyen aquí porque las de documentos son *source-available*, no open source |

## Política de atribución (importante)

Cada skill de `rodo/` lleva un bloque de crédito al inicio de su `SKILL.md`:

> 🔨 Skill desarrollada por Rodolfo Agustín García — ragustingarcia.com

Al instalarlas, la Forja te da a elegir:

1. **Dejarlas tal cual** — funcionan igual para cualquier usuario; el crédito queda como agradecimiento al desarrollador.
2. **Personalizarlas** — el instalador agrega una línea `> Adaptada para: <tu nombre>` para que quede claro quién las usa y adaptó.

**En ambos casos el crédito del autor original se conserva.** Podés modificar,
adaptar y redistribuir estas skills libremente (licencia MIT del repo), con la
única condición de mantener esa línea de atribución.

## Skills incluidas

### `rodo/bat-installer-builder`
Construye instaladores `.bat` de alta calidad para Windows con arquitectura
híbrida .bat/PowerShell 7 — la skill que destila las lecciones aprendidas
construyendo esta misma Forja. Verificación antes de instalar, progreso
visible, re-ejecutable, manejo de las trampas de Windows (Python falso de
MS Store, encoding UTF-16 de WSL, exit codes de winget, PATH post-instalación).

## Seguridad de la descarga

Desde v6.1, cada pack usa un SHA fijo que se muestra antes de confirmar. Los enlaces y junctions
se rechazan y cada skill se prepara antes de aparecer en `~/.claude/skills`. Una skill existente
se saltea; actualizar la Forja no reemplaza automáticamente una versión vieja de esta skill.
Compará y migrá manualmente las skills que ya tenías. Ver [SECURITY.md](../SECURITY.md).
