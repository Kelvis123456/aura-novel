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
