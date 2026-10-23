# AGENTS.md — VANTA

Guía compartida para agentes de código que trabajen en este repo.

## Reglas de trabajo (ponytail activo)

Este repo tiene el plugin Ponytail activo en modo `full`. Respeta esta
escalera antes de escribir código:

1. ¿Esto necesita existir? Si no, no lo escribas (YAGNI).
2. ¿Ya existe en este repo? Reutilízalo, no lo reescribas.
3. ¿Lo hace Dart o Flutter? Úsalo antes de añadir dependencias.
4. ¿Ya hay una dependencia instalada que lo haga? Úsala.
5. ¿Una línea basta? Escribe una línea.
6. Solo entonces añade el mínimo código necesario.

La pereza nunca aplica a validación de fronteras, manejo de datos, seguridad o
accesibilidad.

## Convenciones

- Comentarios, nombres visibles y mensajes de usuario: español.
- Mantén Android con Media3 y Windows/Linux con media_kit/libmpv.
- No añadas dependencias nuevas sin una necesidad concreta.
- No edites `build/`, `.dart_tool/` ni runners generados salvo que sea necesario.
- No incluyas credenciales, URLs privadas ni archivos de configuración local.

## Verificar antes de dar por terminado

Para cambios Flutter, ejecuta:

```text
flutter analyze
flutter test
```

Si cambias UI o plataforma, ejecuta además el build correspondiente:

```text
flutter build windows --debug
flutter build apk --debug
```

Corrige los fallos encontrados antes de terminar.
