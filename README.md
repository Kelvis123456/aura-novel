# Aura Novel

App móvil (Flutter, Android) para escribir novelas con ayuda de una IA. Hice la app para escribir en el celular sin depender de un servicio con suscripción: tú pones tu propia API key y el modelo que quieras.

![Editor](docs/screenshots/01-home.png) ![Menú](docs/screenshots/02-menu.png)

## Qué hace

- **Editor** con contador de palabras y tiempo de lectura. El botón de continuar pide a la IA que siga la escena, y la instrucción rápida sirve para pedir ajustes ("aumenta la tensión").
- **Proyectos y capítulos** guardados en SQLite local, y cada capítulo guarda su historial como un árbol de ramas (`story_nodes`): puedes bifurcar desde cualquier punto y volver a cargar una rama en el editor.
- **Estudio de personajes y lore:** fichas de personajes y de elementos del mundo. `ContextBuilderService` detecta en el texto reciente los nombres y etiquetas que aparecen, más lo que fuerces incluir, y los manda como contexto a la IA para que no se contradiga.
- **Exportar** a TXT, PDF o EPUB y compartir el archivo.
- **Ajustes de API:** cualquier servidor compatible con `POST {baseUrl}/chat/completions` de OpenAI. La key se guarda con `flutter_secure_storage`.

## Cómo correrla

```
flutter pub get
flutter run
```

Necesitas Flutter 3 y un dispositivo o emulador Android. En Ajustes de API pon la URL base, tu key y el nombre del modelo.

## Estado

Funciona en mi Galaxy S10+. No tiene tests y solo probé Android. La respuesta de la IA llega en streaming (SSE).

Las decisiones de diseño están en [docs/decisions.md](docs/decisions.md).
