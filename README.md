# Repo Maintenance Bot

> Automatización local y transaccional para actualizar lockfiles npm, validar el árbol actualizado y crear un commit solo cuando la evidencia pasa.

[![CI](https://github.com/AvilaCarlosDev/repo-maintenance-bot/actions/workflows/ci.yml/badge.svg)](https://github.com/AvilaCarlosDev/repo-maintenance-bot/actions/workflows/ci.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/bash-5.x-4EAA25?logo=gnubash&logoColor=white)](auto-commit.sh)

## Por qué existe

Actualizar un lockfile parece una tarea pequeña, pero validar con el **node_modules** anterior produce una falsa sensación de seguridad. Modificar directamente el repositorio también puede dejar archivos generados, stages accidentales o un dry-run que no era realmente seco.

Repo Maintenance Bot trata cada actualización como una transacción aislada:

1. Rechaza repositorios con cambios locales.
2. Crea un clon temporal local.
3. Ejecuta **npm update --package-lock-only --ignore-scripts**.
4. Rechaza cualquier cambio que no sea el lockfile esperado.
5. Instala el árbol actualizado con **npm ci**.
6. Ejecuta los scripts **test** y **build**, si existen.
7. Copia al repositorio original únicamente el lockfile validado.
8. Crea un commit local. El push es opcional.

## Garantías verificadas

| Escenario | Comportamiento |
|---|---|
| Repositorio con cambios locales | Se omite sin tocarlo |
| Dry-run | Valida en el clon temporal y deja el original intacto |
| npm test falla | Rechaza la actualización aunque el build pudiera pasar |
| npm run build falla | Rechaza la actualización |
| npm cambia otro archivo | Rechaza la actualización |
| Tests/build generan archivos | No llegan al repositorio ni al commit |
| No hay cambios reales | No crea commit |
| Actualización válida | Commitea solo package-lock.json o npm-shrinkwrap.json |
| Push | Desactivado por defecto |

Estas garantías están cubiertas por [pruebas de comportamiento](tests/run.sh) y CI.

## Requisitos

- Bash 5.x
- Git
- Node.js y npm
- mktemp y cksum
- Identidad Git configurada en los repositorios donde se permita crear commits

## Uso

Clona el proyecto y prueba primero en modo dry-run:

    git clone https://github.com/AvilaCarlosDev/repo-maintenance-bot.git
    cd repo-maintenance-bot
    REPO_MAINTENANCE_DRY_RUN=1 ./auto-commit.sh ~/code/proyecto-a

Procesa varios repositorios y deja commits locales:

    ./auto-commit.sh ~/code/proyecto-a ~/code/proyecto-b

Habilita push únicamente después de revisar el comportamiento:

    REPO_MAINTENANCE_PUSH=1 ./auto-commit.sh ~/code/proyecto-a

## Configuración

| Variable | Default | Efecto |
|---|---:|---|
| REPO_MAINTENANCE_DRY_RUN | 0 | Ejecuta el flujo completo sin modificar el repositorio original |
| REPO_MAINTENANCE_PUSH | 0 | Envía el commit al remoto configurado |
| REPO_MAINTENANCE_SKIP_TESTS | 0 | Omite test/build; reduce la evidencia y no se recomienda |
| REPO_MAINTENANCE_ALLOW_INSTALL_SCRIPTS | 0 | Permite scripts de instalación durante npm ci |
| CHECKPOINT_DIR | ~/.local/state/repo-maintenance-bot/checkpoints | Directorio de checkpoints diarios |
| LOG_FILE | ~/.local/state/repo-maintenance-bot/repo-maintenance.log | Archivo de log |

Las variables antiguas STREAK_KEEPER_DRY_RUN, STREAK_KEEPER_PUSH y STREAK_KEEPER_SKIP_TESTS se aceptan temporalmente por compatibilidad, pero están deprecadas.

## Modelo de seguridad

- El clon temporal evita validar con dependencias antiguas.
- El clon copia sus objetos y elimina su remoto antes de ejecutar validaciones.
- Los scripts de instalación de terceros están bloqueados por defecto con **npm ci --ignore-scripts**.
- Solo se permite transferir un lockfile conocido al repositorio original.
- Antes de aplicar el resultado se comprueba nuevamente que HEAD y el working tree no cambiaron durante la validación.
- El directorio temporal se valida antes de eliminarlo.

### Límites

- Actualmente solo mantiene lockfiles npm.
- Los scripts test/build son código del proyecto y se ejecutan con los permisos del usuario. Usa la herramienta únicamente en repositorios confiables; el clon transaccional no es una sandbox contra código malicioso.
- Un test que no existe no puede demostrar comportamiento.
- **--ignore-scripts** puede impedir la instalación de paquetes que necesiten compilación. Habilita REPO_MAINTENANCE_ALLOW_INSTALL_SCRIPTS solo después de evaluar ese riesgo.
- La herramienta no abre PR, no hace merge y no resuelve cambios semánticos en dependencias.
- Un push habilitado usa el remoto y las credenciales Git existentes del usuario.

## Automatización

Hay ejemplos conservadores en [examples/](examples/):

- [systemd-example.service](examples/systemd-example.service)
- [systemd-example.timer](examples/systemd-example.timer)
- [cron-example](examples/cron-example)

Los ejemplos empiezan en dry-run. Ninguno habilita push por defecto.

## Desarrollo y pruebas

    bash -n auto-commit.sh tests/run.sh
    tests/run.sh

La suite crea repositorios temporales y usa un npm controlado; nunca ejecuta el bot contra tus repositorios reales.

## Sobre las rachas de contribuciones

Este proyecto nació con otro nombre orientado a mantener una racha de GitHub. Ese objetivo fue descartado.

**La actividad artificial no demuestra capacidad técnica.** Esta herramienta solo debe crear commits cuando existe mantenimiento real, validado y revisable.

## Seguridad

Consulta [SECURITY.md](SECURITY.md) para reportar vulnerabilidades sin publicar detalles sensibles.

## Licencia

MIT — ver [LICENSE](LICENSE). Creado por [Carlos Avila](https://github.com/AvilaCarlosDev).
