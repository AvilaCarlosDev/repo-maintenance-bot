# repo-maintenance-bot

> Bot local de mantenimiento para varios repositorios: actualiza lockfiles, valida, y **solo commitea si el cambio es real y los tests pasan**.

[![MIT License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/bash-5.x-4EAA25?logo=gnubash&logoColor=white)](auto-commit.sh)

## El problema

Cuando mantienes varios repos a la vez, las tareas pequenas se acumulan: lockfiles desactualizados, dependencias que se quedan atras, chequeos que nunca corres. Automatizarlo es tentador, pero un script que commitea a ciegas es peor que no tener nada: mete cambios sin validar en repos que creias estables.

Este script automatiza el mantenimiento **sin asumir que su propio cambio es correcto**.

## Como se comporta

| Situacion | Que hace |
|---|---|
| El repo tiene cambios locales sin commitear | **Se salta el repo.** No toca trabajo tuyo a medio hacer. |
| Hay lockfile npm | `npm update --package-lock-only --ignore-scripts` (sin ejecutar scripts de terceros) |
| Hay `package.json` pero no lockfile | No modifica nada: no hay forma segura de acotar el cambio |
| El mantenimiento no produjo diff | No commitea |
| `npm test` o `npm run build` fallan | **`git restore` y aborta ese repo.** No deja el repo roto |
| Todo paso | Commitea con mensaje convencional (`build:` o `chore:`) |
| Ya corrio hoy en ese repo | Se salta por checkpoint diario |

El push **no** es automatico: es opt-in con `STREAK_KEEPER_PUSH=1`.

## Uso

```bash
./auto-commit.sh ~/code/proyecto-a ~/code/proyecto-b
```

Primero en seco, para ver que haria sin tocar nada:

```bash
STREAK_KEEPER_DRY_RUN=1 ./auto-commit.sh ~/code/proyecto-a
```

## Variables

| Variable | Default | Efecto |
|---|---|---|
| `STREAK_KEEPER_DRY_RUN` | `0` | Muestra el plan y revierte el stage, sin commitear |
| `STREAK_KEEPER_PUSH` | `0` | Hace `git push` despues de un commit exitoso |
| `STREAK_KEEPER_SKIP_TESTS` | `0` | Omite test y build (no recomendado) |
| `CHECKPOINT_DIR` | `/tmp/streak-keeper` | Donde se guardan los checkpoints diarios |
| `LOG_FILE` | `/tmp/streak-keeper.log` | Archivo de log |

## Programarlo

Con systemd (ver [`examples/`](examples/)):

```bash
cp examples/systemd-example.service ~/.config/systemd/user/repo-maintenance.service
cp examples/systemd-example.timer   ~/.config/systemd/user/repo-maintenance.timer
systemctl --user enable --now repo-maintenance.timer
```

O con cron, usando [`examples/cron-example`](examples/cron-example).

## Sobre las rachas de contribuciones

Este repo se llamaba `github-streak-keeper`. El nombre daba a entender lo contrario de lo que hace el script, asi que cambio.

**Generar actividad artificial en GitHub no sirve de nada.** Quien revisa tu perfil mira el contenido de los commits, no el color de los cuadritos. Si el mantenimiento real de tus repos produce commits, bienvenidos sean; si no hay nada que mantener, este script no commitea, y asi debe ser.

## Alcance

Hoy solo automatiza mantenimiento de **lockfiles npm**. La funcion `apply_maintenance()` esta preparada para sumar mas mantenedores seguros (requirements de Python, lockfile de Composer, pinning de GitHub Actions, lint/format del propio proyecto).

## Licencia

MIT — ver [LICENSE](LICENSE). Hecho por [Carlos Avila](https://github.com/AvilaCarlosDev).
