# Política de seguridad / Security policy

[Español](#español) · [English](#english)

## Español

### Código soportado

Hasta la primera versión etiquetada, las correcciones de seguridad se aplican solo al último commit de la rama principal.

| Versión | Soportada |
|---|---|
| main | Sí |
| Commits anteriores y forks | No |

### Cómo reportar una vulnerabilidad

No publiques credenciales, detalles de explotación, rutas privadas de repositorios ni pruebas de concepto en un issue público.

Usa la pestaña *Security* del repositorio y elige **Report a vulnerability** (aviso privado de GitHub): <https://github.com/AvilaCarlosDev/repo-maintenance-bot/security/advisories/new>

Incluye:

- el commit afectado;
- sistema operativo y versión de Bash;
- una reproducción mínima;
- el comportamiento esperado y el observado;
- el impacto potencial;
- si se vieron afectadas credenciales, repositorios o remotos.

### Áreas de seguridad relevantes

Los reportes son especialmente útiles cuando implican:

- archivos inesperados añadidos al stage o al commit;
- mutación durante un dry-run;
- limpieza insegura de directorios temporales;
- inyección de comandos o de rutas;
- fuga de credenciales en los registros;
- un push no previsto;
- saltarse la validación de test/build;
- ejecución de scripts de ciclo de vida de dependencias sin opt-in.

### Divulgación

Deja tiempo para reproducir y corregir un problema confirmado antes de publicar detalles técnicos. Un reporte puede rechazarse si no se reproduce, afecta a modificaciones no soportadas o depende de salvaguardas desactivadas a propósito.

## English

### Supported code

Until the first tagged release, security fixes are applied to the latest commit on the main branch only.

| Version | Supported |
|---|---|
| main | Yes |
| Older commits and forks | No |

### Reporting a vulnerability

Do not publish credentials, exploit details, private repository paths, or proof-of-concept payloads in a public issue.

Use the repository Security tab and select **Report a vulnerability** when private vulnerability reporting is available. If that option is unavailable, open a public issue containing no sensitive details and ask the maintainer for a private reporting channel.

Include:

- affected commit;
- operating system and Bash version;
- minimal reproduction;
- expected and observed behavior;
- potential impact;
- whether credentials, repositories, or remotes were affected.

### Relevant security areas

Reports are especially useful when they involve:

- unexpected files staged or committed;
- mutation during dry-run;
- unsafe temporary-directory cleanup;
- command or path injection;
- credential leakage in logs;
- unintended push behavior;
- bypasses of test/build validation;
- execution of dependency lifecycle scripts without opt-in.

### Disclosure

Please allow time to reproduce and remediate a confirmed issue before publishing technical details. A report may be declined when it cannot be reproduced, affects unsupported modifications, or depends on explicitly disabled safeguards.
