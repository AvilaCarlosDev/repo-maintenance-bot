# Contribuir / Contributing

[Español](#español) · [English](#english)

## Español

Gracias por tu interés. Esta herramienta modifica repositorios reales, así que **cada garantía debe estar respaldada por una prueba de comportamiento**.

### Desarrollo

```bash
bash -n auto-commit.sh tests/run.sh scripts/demo-session.sh
shellcheck auto-commit.sh tests/run.sh scripts/demo-session.sh
tests/run.sh
```

La suite crea repositorios temporales y usa un `npm` simulado; nunca corre el bot contra tus repositorios reales.

### Principios

- Un dry-run nunca modifica el repositorio original.
- Solo se commitea el lockfile validado; cualquier otro cambio se rechaza.
- Los scripts de instalación de terceros siguen bloqueados salvo opt-in explícito.
- Todo `rm -rf` valida antes que la ruta sea del bot.
- Cambios de lógica: incluye su prueba en `tests/run.sh` y comprueba que falla sin el cambio.
- Mantén la documentación en español e inglés: si cambias una, actualiza la otra.

El CI rechaza marcas de agua de IA en archivos y mensajes de commit (por ejemplo, trailers `Co-Authored-By` de asistentes). Si usaste un asistente, menciónalo en la descripción del PR.

## English

Thanks for your interest. This tool modifies real repositories, so **every guarantee must be backed by a behavior test**.

### Development

```bash
bash -n auto-commit.sh tests/run.sh scripts/demo-session.sh
shellcheck auto-commit.sh tests/run.sh scripts/demo-session.sh
tests/run.sh
```

The suite creates temporary repositories and uses a fake `npm`; it never runs the bot against your real repositories.

### Principles

- A dry run never modifies the original repository.
- Only the validated lockfile is committed; any other change is rejected.
- Third-party install scripts stay blocked unless explicitly opted in.
- Every `rm -rf` first validates that the path belongs to the bot.
- Logic changes: include a test in `tests/run.sh` and check that it fails without the change.
- Keep documentation in Spanish and English: if you change one, update the other.

CI rejects AI watermarks in files and commit messages (for example assistant `Co-Authored-By` trailers). If you used an assistant, say so in the PR description instead.
