# Registro de cambios / Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) ·
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Sin publicar / Unreleased]

### Añadido / Added
- 6 pruebas de casos límite en `tests/run.sh` (19 en total): valores inválidos de las variables, ejecución sin argumentos, rutas con espacios, repositorio sin lockfile, directorio que no es un repositorio y ruta inexistente que no detiene a los demás. / 6 edge-case tests (19 in total).
- CI: escaneo de secretos (gitleaks) y verificación de marcas de agua. / CI: secret scanning and watermark check.
- README en español e inglés (`README.en.md`), `SECURITY` y `CONTRIBUTING` bilingües, código de conducta y plantillas de issues y PR. / Bilingual README, SECURITY and CONTRIBUTING, code of conduct, and issue/PR templates.
