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

## 2026-11-07: Un asistente de escritura que escribe de verdad, con el oficio de las skills dentro
La app generaba poco y genérico: `maxTokens` de 800 y un prompt de una línea ("eres un asistente de escritura creativa"). Ahora hay una pestaña Asistente con tres modos: charlar (con contexto del proyecto), escribir un capítulo largo y investigar para la historia. Cuatro decisiones:
- **Capítulos largos en varias llamadas.** Ninguna respuesta única da miles de palabras, así que `ChapterWriter` planifica las escenas (JSON) y escribe una por llamada, de unas 900 palabras, pasándole el plan y el final de lo ya escrito. Costo: más llamadas y la coherencia depende del plan y de ese contexto.
- **Las skills de escritura viven como módulos de prompt** en `assets/craft/` (26, destiladas de las skills de Claude Code por agentes y revisadas por mí). Cinco van siempre (prosa, diálogo, clichés, tics de IA, ritmo de escenas) y el resto son herramientas que el autor lanza sobre un texto. Hay un nivel "esencial" con un prompt corto para modelos pequeños o locales, porque el completo ocupa unos 14 000 caracteres.
- **Sin filtros propios.** La persona (`assets/prompts/writer_core.md`) pide escribir violencia, sexo y temas oscuros con oficio, sin avisos ni sermones, y deja que el autor fije el registro (suave, natural, crudo, sucio). Quedan tres límites fijos que no dependen del modelo: nada sexual con menores, nada sexual explícito con personas reales identificables y nada de instrucciones operativas reales presentadas como ficción. Lo que el modelo acepte lo decide el proveedor: la app no puede saltarse sus políticas, por eso hay atajos para Ollama y LM Studio.
- **Investigación como ficha de Mundo.** El modo Investigar guarda la nota como una ficha de categoría Investigación del proyecto, así el contexto de la IA la usa después. Se puede apuntar a un modelo con búsqueda web distinto del que escribe.

### Límites conocidos del asistente
- "Añadir al capítulo" crea una versión nueva sobre la más reciente. Si ese capítulo está abierto en Escribir, su próximo "Guardar versión" parte de la versión que cargó y deja el texto añadido en una rama lateral.
- "Otra vez" en un capítulo que ya se añadió al manuscrito sigue el texto del capítulo, que ya incluye lo añadido.
- Con un modelo que recorta la respuesta por su propio límite de tokens, una escena puede quedar corta; la app no avisa de ese corte.

## 2026-11-07: Dos proveedores de IA: servidor y modelo dentro del teléfono
La app puede hablar con un servidor OpenAI-compatible o correr un modelo en el propio teléfono. Se elige en Ajustes de API ("Servidor (API)" o "En este teléfono") y se lee en cada petición, así que cambiar surte efecto al instante. Cuatro decisiones:
- **`LlmClient` como interfaz.** Los servicios dependían de la clase concreta `DynamicOpenAIClient`. Ahora dependen de `LlmClient`, y `RoutingLlmClient` reparte entre el cliente remoto y `LocalLlmClient`. No hubo que tocar el asistente, el escritor de capítulos ni el editor.
- **llama.cpp con el paquete `llamadart`** (MIT, publicador verificado, 160/160 en pub.dev, binarios nativos que su build baja de GitHub). Lo elegí frente a `llama_cpp_dart` por tener binarios precompilados y estar mantenido. Costo: obligó a subir `archive` a 4.5 y `share_plus` a 10.1, el APK de depuración pesa unos 380 MB (varias arquitecturas) y el primer build baja los binarios. Es una dependencia que ejecuta código nativo, no es trivial de auditar.
- **El modelo no va en el APK.** Se descarga una vez desde Hugging Face con barra de progreso, pausa y reanudación (`Range`), y se guarda en el almacenamiento privado. El catálogo trae Gemma 3 4B y 1B sin negativas (GGUF Q4_K_M, 2,5 GB y 0,8 GB).
- **Ventana pequeña.** El modelo local se carga con 6144 tokens de contexto. Por eso usa siempre el prompt de oficio corto, guarda menos turnos de charla (4, recortados), el escritor de capítulos arrastra menos texto previo y el tope de tokens de respuesta se recorta a lo que queda de ventana tras el prompt. Antes de ese recorte la generación se quedaba en blanco sin error.

Probado: carga y responde en el emulador de Android (x86_64, 2,5 GB de RAM, muy lento: unos 4 minutos para un párrafo). La velocidad real en un teléfono arm64 sin medir.

## 2026-11-07: Oficio completo: 34 módulos, notas profundas y pasadas automáticas
La primera versión de los módulos de oficio estaba comprimida (unas 600 palabras por skill) y dejaba fuera las skills de publicar, investigar y resumir. Cambios:
- **Notas profundas.** Cada módulo tiene una sección `## Deep notes` (600 a 850 palabras: marcos paso a paso, ejemplos antes y después, umbrales, listas de fallos). Solo entran en las herramientas que lanzas tú; las reglas que acompañan a todo lo que escribe la IA siguen siendo la sección `Core rules`. Con un modelo pequeño (local) las herramientas también omiten las notas profundas.
- **`story-long-write` repartida en cinco módulos.** Sus 38 archivos de referencia se leyeron enteros y quedaron como `long-form-hooks`, `long-form-plot`, `long-form-continuity`, `long-form-style` y `long-form-genres`. `long-form-style` (manías y listas de palabras a evitar) entró entre las reglas siempre activas.
- **Tres skills nuevas:** `book-marketing` (grupo Publicar: contraportada, descripción de tienda, pitch), `research-workflow` y `summarization`.
- **Investigación profunda.** El modo Investigar planea de 3 a 5 subpreguntas, responde cada una y sintetiza (5 a 7 llamadas). Se puede quitar con el chip "Profunda"; con un modelo local va en una sola llamada.
- **Resúmenes de capítulo** con los principios de `summarization` y un prompt que pide estado de personajes (heridas, objetos, lo que sabe cada uno), promesas y cabos sueltos.
- **"Pulir al terminar cada capítulo"** (opción del perfil, apagada por defecto). Después de escribir, cada escena se reescribe una vez con las reglas de prosa, diálogo y tics de IA. Una escena pulida que quede por debajo del 60 % o por encima del 180 % del original se descarta y se conserva la original. Si el pulido falla se deja lo ya escrito. Cuesta el doble de llamadas.
Costo: las reglas siempre activas pasaron a unos 17 000 caracteres (unos 4 200 tokens) por llamada con el oficio completo; para modelos pequeños queda el nivel "esencial".

## 2026-11-08: Cómo calibré el prompt de prosa
Probé el escritor con el prompt real de la app (perfil + reglas de oficio) contra dos tipos de modelo, para dejar los parámetros fijados antes de tocar más cosas.
- **Modelo pequeño y gratuito (`gpt-5.4-mini` vía OmniRoute):** prosa correcta pero con tics. En 1 200 palabras salieron siete "como si", adjetivos inflados ("obsceno", "grotesco" sobre cosas solo raras), un "No fue X. Fue Y." repetido y escenas un 35 a 40 % más largas de lo pedido. Añadí al prompt base un presupuesto de símiles (uno cada 300 palabras), la regla de elegir adjetivos por lo que significan, no repetir objetos ya usados y un tope de longitud por escena (+15 %). Con eso bajó a tres "como si" y el desvío de longitud a un 24 %.
- **Modelo fuerte (cinco capítulos de unas 1 100 palabras con subagentes Sonnet, uno por género: terror, romance, fantasía, novela negra, ciencia ficción, registros natural, crudo y sucio):** todos entre 971 y 1 103 palabras, es decir dentro del objetivo; cero o un "como si" por capítulo, sin "no X sino Y" salvo uno. Voz distinta en cada género (presente y primera persona en el romance, frases secas en negra). Medí con un script los "como si", los "no fue / sino", la longitud media de frase y las aperturas repetidas.
Límites: cinco muestras de un solo modelo fuerte, leídas por mí; no es una evaluación con lectores. Un modelo pequeño seguirá necesitando el pulido automático. Las pruebas con subagentes no forman parte de la app.
