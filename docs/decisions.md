# Decisiones

## 2026-08-06 — Sin backend
La app habla directo con el proveedor de IA. Alternativa: un servidor propio que guarde las keys y haga de proxy. Lo descarté porque habría que mantener y pagar un servidor, y los datos de la novela se quedan en el teléfono.

## 2026-08-06 — Cliente compatible con OpenAI en vez de un SDK de un proveedor
Un solo cliente HTTP (`DynamicOpenAIClient`) que lee URL, key y modelo al momento de la llamada. Cambiar de proveedor es cambiar un ajuste, sin recompilar. Costo: solo sirve con APIs que copian el formato de OpenAI.

## 2026-08-06 — SQLite local (`sqflite`) y no archivos JSON
Hay relaciones reales (proyecto, capítulos, ramas de la historia, personajes). Con SQLite puedo consultar por proyecto o capítulo sin recorrer archivos.

## 2026-08-06 — API key en `flutter_secure_storage`
La key no va en SQLite ni en preferencias en texto plano. Usa el keystore de Android.

## 2026-08-06 — EPUB armado a mano con `archive`
Un EPUB es un zip con un `mimetype` y unos XML, así que con `archive` (que ya hacía falta) se resuelve en un solo archivo (`export_service.dart`).

## 2026-10-10: Reintentos solo antes del primer byte
El cliente reintenta (1 s y 3 s, o el `Retry-After` con tope de 10 s) cuando el servidor da 429 o 5xx, o hay un corte de red. Solo vale mientras no haya llegado nada del cuerpo: reintentar a mitad del stream duplicaría texto en el documento. Si se corta ahí, el editor conserva lo recibido y avisa.

## 2026-10-10: Resumen por capítulo en vez de mandar todo el libro
Una novela larga no cabe en el prompt. Cada capítulo guarda un resumen escrito por la IA (columna `summary`, migración a v2) y el editor manda los de los capítulos anteriores, quitando los más viejos si pasan de 3000 caracteres. Alternativa: embeddings y búsqueda semántica. La descarté porque necesita otro endpoint y la app solo asume `/chat/completions`. Costo: el resumen se pide a mano y puede quedar viejo.

## 2026-10-10: Borradores en tabla propia, no en la versión actual
El autosave no sobrescribe el nodo del capítulo porque rompería el historial de ramas. Va a una tabla `drafts` (una fila por capítulo, con el nodo del que salió). Si el nodo no coincide al abrir, el borrador se descarta.

## 2026-10-10: Restaurar copia mezcla, no reemplaza
La restauración inserta o reemplaza por id y deja lo demás. Alternativa: vaciar todo y cargar la copia. Lo descarté porque un archivo equivocado borraría trabajo. Cada base se escribe en una transacción, pero las dos juntas no, así que un fallo en el lore podría dejar los proyectos ya restaurados.

## 2026-10-10: `sqflite_common_ffi` solo para tests
Para probar migraciones y repositorios necesito SQLite real en la máquina de desarrollo. Entra como dev dependency. En CI depende de que el runner tenga `libsqlite3`.

## 2026-10-10: El tope de contexto lo elige el usuario
El bloque de lore y los resúmenes de capítulos anteriores tenían un tope fijo de 3000 caracteres. Con un modelo gratuito de ventana grande sobra espacio, y con uno pequeño o local 3000 puede ser demasiado. Pasó a ser un ajuste en Ajustes de API (500 a 20000, en pasos de 500) que vale para cada uno por separado. El valor inicial sigue en 3000 y las instalaciones que ya guardaron su config lo usan hasta que lo cambien. Alternativa: detectar la ventana del modelo. No hay forma estándar de pedírsela a un endpoint compatible con OpenAI.

