# Privacidad

Aura Novel no tiene servidor ni cuentas. Todo lo que escribes se queda en tu teléfono, salvo lo que tú mandas a la IA que conectes. Este documento dice qué sale y adónde, según lo que hace el código hoy.

## Qué se guarda en el teléfono
- **Proyectos, capítulos, versiones, borradores, línea de tiempo, mapa, conversación del asistente y estadísticas de escritura:** una base SQLite en el almacenamiento privado de la app. Ninguna otra app puede leerla.
- **Fichas de personajes y lore:** otra base SQLite, también privada.
- **Tu clave de API y la dirección del servicio:** en el almacén seguro de Android (Keystore), no en la base de datos ni en texto plano.
- **Copias de seguridad:** solo se crean cuando tú exportas el JSON, y van adonde tú lo compartas. La copia automática de Android está desactivada, para que ni los textos ni las claves viajen a una nube sin que lo decidas.

## Qué sale del teléfono
- **Hacia la IA que configures.** Cuando pides un texto, una herramienta, una investigación o un resumen, la app envía a esa dirección el mensaje, el perfil del proyecto, las fichas de Mundo relacionadas y los trozos del capítulo que hagan falta. Si usas un servicio de terceros, su política decide qué pasa con eso. Si usas un servidor propio (por ejemplo Ollama en tu PC) o el modelo del teléfono, no sale nada de tu red.
- **Descarga del modelo local.** Si eliges un modelo del teléfono, la app lo baja una vez desde Hugging Face (`huggingface.co`). Esa descarga no lleva tus textos.
- **Compartir y exportar.** TXT, PDF, EPUB, DOCX, la wiki y las copias JSON se generan en el teléfono y solo salen por el menú de compartir cuando tú lo eliges.

## Qué no hace
- No hay analíticas, publicidad, rastreadores ni informes de fallos.
- No pide ubicación, contactos, cámara ni micrófono. El único permiso es internet.
- No sube tus textos a ningún servidor de la app, porque no existe.

## Contenido
La app no filtra lo que escribes. Lo que un modelo acepte o rechace lo decide el modelo y su proveedor. Si el servicio que conectes guarda tus peticiones, eso queda fuera del control de la app.

## Borrar tus datos
Borrar un proyecto elimina sus capítulos, versiones, borradores, línea de tiempo, mapa y conversación. Sus fichas de Mundo no se borran solas: quedan en la base de lore y se quitan a mano desde Mundo, con el filtro de ver todos los proyectos. Desinstalar la app borra las bases y la clave guardada. Un modelo descargado ocupa espacio aparte y se quita desde Ajustes.

## Qué no he comprobado
Esto describe el código, no una auditoría. No he pasado la app por un análisis de tráfico de red en un teléfono real, y no es asesoramiento legal. Si la publicas en una tienda, esa tienda pedirá su propia declaración de datos y esta lista sirve de base.
