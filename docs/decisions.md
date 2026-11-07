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


## 2026-11-06: Revisión de coherencia como botón, no automática
Cada capítulo tiene un botón que le pide a la IA comparar el texto con las fichas de lore y los resúmenes anteriores (`ConsistencyService`). Reutiliza `ContextBuilderService` y `ChapterSummaryService`. No corre sola al guardar porque cada revisión gasta tokens de la key del usuario. Costo: el resultado no se guarda, hay que volver a pedirlo. Y una IA puede inventar o pasar por alto contradicciones, así que es una ayuda y no una garantía.

## 2026-11-06: Fechas del mundo como texto, con el calendario solo para formatear
Los eventos de la línea de tiempo guardan la fecha como texto libre y el orden lo da `position` (arrastrar). El calendario inventado (era + meses con sus días) solo ayuda a escribir la fecha ("12 de Brumario, Era del Sol 312") y valida que el día exista en el mes. Alternativa: fechas numéricas con ordenamiento automático. La descarté porque obliga a definir años bisiestos, semanas, etc. para algo que el autor suele querer ordenar a mano. Se guarda como JSON en `projects.calendar`; si el JSON se corrompe se ignora y el proyecto abre igual.

## 2026-11-06: Wiki pública estática con visibilidad por capítulo
`WikiExportService` genera HTML plano (un zip) desde las fichas, sin servidor. Cada ficha tiene "visible desde el capítulo N" y al exportar se elige hasta qué capítulo mostrar, para no soltar spoilers. Los secretos y límites del personaje nunca se publican, ni con "todo el libro". Los eventos sin capítulo solo salen al publicar todo el libro, porque no tienen un punto donde volverse públicos. Alternativa: una wiki viva en un servidor. Descartada por lo mismo que el backend (ver la primera decisión).

## 2026-11-06: El mapa es una imagen que el autor elige, con pines en fracciones
No hay editor de mapas. Se elige una imagen (de Azgaar, Inkarnate o un dibujo) y se marcan pines con posición como fracción del ancho y alto, para que no se muevan al cambiar de pantalla. La imagen se copia a la carpeta de la app con nombre nuevo cada vez (Flutter cachea por ruta). La imagen no entra en la copia de seguridad JSON, solo los pines: al restaurar en otro teléfono hay que volver a elegirla.

## 2026-11-06: Restaurar una copia vieja pisa calendario y mapa
La restauración reemplaza la fila del proyecto por id. Una copia hecha antes del calendario o del mapa no trae esas columnas y las deja vacías. Es la misma regla de "reemplaza por id" de la decisión anterior; no lo resolví aparte.

## 2026-11-06: Las fichas de lore son por proyecto, con "universo compartido" opcional
Antes personajes y lore eran globales: la IA, la revisión de coherencia, la wiki y el mapa veían todo. Con dos novelas se mezclaban y la wiki de una publicaba el mundo de la otra. Ahora cada ficha tiene un `project_id` opcional: con proyecto solo se ve en ese libro, sin proyecto (NULL) es del universo compartido y se ve en todos, para quien escribe varios libros en un mismo mundo. La migración (lore v3) deja todas las fichas existentes como compartidas, así que nada desaparece. El editor sin proyecto (borrador suelto) solo ve las compartidas. En el Studio se ve lo del proyecto desde el que se abrió más lo compartido, con un botón para ver todo. Alternativa: una base de lore por proyecto. La descarté porque obliga a duplicar fichas cuando el mundo es el mismo.

## 2026-11-06: Identidad "tinta y papel" con un solo acento
Rediseño de la imagen de la app. Dos temas: tinta (oscuro cálido, `#110C09`) y papel (claro, `#F6F3EC`), un acento de lacre rojo apagado en vez del carmesí `#dc143c` sobre negro puro. Los grises llevan tinte cálido (OKLCH, matiz 60 a 85) y los contrastes están medidos, no a ojo: el texto blanco sobre el lacre claro da 3,0:1 y no llega a 4,5, así que los botones del tema oscuro llevan texto tinta. Logo: una punta de pluma sobre un libro abierto con un aro de luz detrás (la aura). La primera versión era solo la pluma en un aro, pero no decía de qué iba la app; el libro lo resuelve. También probé una A con halo, que se leía como una A con macrón, y una A con orbe, que quedaba genérica. Tipografía propuesta: Newsreader para el manuscrito y los títulos, Instrument Sans para la interfaz. Los iconos de Android salen de `design/logo/*.svg` con `resvg`. La hoja de marca está en `design/brand.html`.

## 2026-11-06: Tres pestañas abajo en lugar del menú lateral
El menú lateral escondía lo más importante (el mundo y los proyectos) detrás de un icono. Ahora hay tres pestañas: Escribir, Mundo (lore, con todas las fichas visibles) y Proyectos. Las pantallas viven en un `IndexedStack`, así que al cambiar de pestaña no se pierde lo que estabas escribiendo. El editor de un capítulo se abre por encima de las pestañas, con flecha para volver y un botón para ver el mundo de ese proyecto. Los colores de todas las pantallas salen ahora del tema (`AuraColors`, tinta y papel según el sistema) y no de valores sueltos. Alternativa: pestañas con la navegación de cada una anidada. La descarté porque duplica el estado de navegación para una app de tres pantallas.
