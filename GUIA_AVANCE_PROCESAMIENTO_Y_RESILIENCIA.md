# Guia del avance: procesamiento y resiliencia

Esta guia describe el siguiente avance tecnico del Gestor Inteligente de Documentos. El objetivo es mejorar la calidad de extraccion, conservar la estructura de documentos nativos y procesar las solicitudes pesadas de IA de forma controlada.

La guia esta pensada para completarse durante la implementacion. No contiene una implementacion cerrada: define el orden, los archivos esperados, decisiones, pruebas y criterios para validar cada rama. 

## Objetivos del avance

- Reducir errores de lectura en imagenes y documentos escaneados.
- Evitar aplicar OCR a archivos que ya tienen texto digital.
- Conservar tablas, montos, fechas y estructura relevante antes de enviar el contenido a la IA.
- Evitar que varias peticiones saturen Ollama.
- Reintentar trabajos temporales, especialmente procesamiento IA y envio de correos.
- Mantener trazabilidad de estados y errores.

## Orden recomendado

Implementar e integrar las ramas en este orden:

```text
feature/preprocesamiento-ocr
        |
        v
feature/parsers-documentos-nativos
        |
        v
feature/cola-procesamiento-ollama
        |
        v
develop
        |
        v
main
```

Si el equipo prefiere una sola rama para todo el avance, usar:

```bash
git checkout -b feature/mejoras-procesamiento-resiliencia
```

La alternativa recomendada es mantener tres ramas separadas porque cada una resuelve un problema diferente y puede probarse de forma independiente.

## Reglas de trabajo

- No hacer push directo a `main` ni a `develop`.
- Crear un Pull Request por rama.
- Integrar primero en `develop`.
- Llevar a `main` solamente despues de validar la integracion.
- No mezclar cambios de infraestructura con cambios de extraccion sin necesidad.
- No subir `.env`, claves SSH, documentos sensibles ni modelos de Ollama.

Commits sugeridos:

```text
feat(ocr): mejorar preprocesamiento de imagenes
feat(parser): extraer estructura de documentos nativos
feat(queue): procesar IA y correos con cola
```

## Plantilla de PR por rama

Usar esta plantilla al abrir el Pull Request de cada rama. Marcar solamente las opciones que correspondan al trabajo realmente realizado.

```md
## ¿Qué se hizo?
- [ ]

## ¿Cómo probarlo?
- [ ]

## ¿Afecta al Frontend/Backend?
- [ ] Sí
- [ ] No
```

No abrir el PR con casillas vacias. Completar el contenido segun la rama.

### PR de `feature/preprocesamiento-ocr`

```md
## ¿Qué se hizo?
- [x] Se mejoro el preprocesamiento de imagenes antes de Tesseract OCR.
- [x] Se aplicaron filtros de escala de grises, contraste, binarizacion o reduccion de ruido segun la calidad.
- [x] Se validaron documentos PNG, JPG y JPEG con diferentes calidades.
- [x] Se conservaron los flujos de PDF digital y DOCX sin aplicarles OCR innecesariamente.

## ¿Cómo probarlo?
- [x] Ejecutar `npm run typecheck`.
- [x] Ejecutar `npm run build`.
- [x] Probar una imagen clara y una imagen escaneada de baja calidad.
- [x] Verificar RUC, fechas, montos, periodos y nombres extraidos.
- [x] Comparar el resultado antes y despues del preprocesamiento.

## ¿Afecta al Frontend/Backend?
- [x] Backend
- [ ] Frontend
```

Commit sugerido:

```text
feat(ocr): mejorar preprocesamiento de imagenes
```

### PR de `feature/parsers-documentos-nativos`

```md
## ¿Qué se hizo?
- [x] Se separo el procesamiento segun el formato del archivo.
- [x] DOCX se procesa con un parser nativo y no mediante OCR.
- [x] XLSX se procesa con un parser nativo conservando tablas, numeros y fechas.
- [x] PDF digital usa extraccion de texto.
- [x] PDF escaneado usa OCR como respaldo cuando no tiene texto suficiente.
- [x] Se normalizo la salida para enviarla a la IA.

## ¿Cómo probarlo?
- [x] Ejecutar `npm run typecheck`.
- [x] Ejecutar `npm run build`.
- [x] Probar DOCX con parrafos y tablas.
- [x] Probar XLSX con montos y fechas.
- [x] Probar PDF digital y PDF escaneado.
- [x] Verificar que no se pierdan decimales, fechas, RUC ni estructura de tablas.
- [x] Confirmar que `/upload` conserve la respuesta esperada.

## ¿Afecta al Frontend/Backend?
- [x] Backend
- [ ] Frontend
```

Commit sugerido:

```text
feat(parser): extraer estructura de documentos nativos
```

### PR de `feature/cola-procesamiento-ollama`

```md
## ¿Qué se hizo?
- [x] Se implemento una cola para controlar el procesamiento de documentos.
- [x] Se limitaron las ejecuciones simultaneas de Ollama.
- [x] Se agregaron estados de trabajo: `pending`, `processing`, `completed`, `failed` y `retrying`.
- [x] Se agregaron reintentos con backoff para errores temporales.
- [x] El envio de correo se proceso como trabajo independiente.
- [x] Se actualizo el frontend para consultar el estado mediante `jobId`, si corresponde.

## ¿Cómo probarlo?
- [x] Ejecutar Redis.
- [x] Ejecutar el worker.
- [x] Ejecutar `npm run typecheck` y `npm run build`.
- [x] Enviar varias peticiones simultaneas.
- [x] Verificar que Ollama respete el limite de concurrencia.
- [x] Simular un timeout y comprobar los reintentos.
- [x] Simular un fallo de correo y comprobar que no se repita el procesamiento IA.
- [x] Verificar que el frontend muestre el estado correcto del trabajo.

## ¿Afecta al Frontend/Backend?
- [x] Sí: Backend y Frontend
- [ ] No
```

Commit sugerido:

```text
feat(queue): procesar IA y correos con cola
```

### PR de integracion a `develop`

Despues de aprobar las tres ramas, abrir un PR de integracion con esta estructura:

```md
## ¿Qué se hizo?
- [x] Se integraron las mejoras de preprocesamiento OCR.
- [x] Se integraron los parsers nativos para documentos DOCX/XLSX.
- [x] Se integro el procesamiento mediante cola y los reintentos.
- [x] Se validaron los flujos de extraccion, clasificacion, resumen ejecutivo y derivacion.

## ¿Cómo probarlo?
- [x] Ejecutar las pruebas individuales de cada rama.
- [x] Ejecutar pruebas de integracion con PDF, DOCX, XLSX, PNG y JPG.
- [x] Verificar `/health` y `/upload`.
- [x] Verificar los estados de los trabajos y los reintentos.
- [x] Verificar el resultado mostrado en el frontend.
- [x] Ejecutar `npm run typecheck`, `npm run build` y las pruebas disponibles.

## ¿Afecta al Frontend/Backend?
- [x] Sí: Frontend y Backend
- [ ] No
```

Commit de integracion sugerido:

```text
feat: integrar mejoras de procesamiento y resiliencia
```

El PR de `develop` hacia `main` debe abrirse solamente despues de completar esta validacion de integracion.

---

# Rama 1: `feature/preprocesamiento-ocr`

## Objetivo

Mejorar la calidad de imagen antes de ejecutar Tesseract OCR. Esta rama debe afectar solamente archivos de imagen y documentos escaneados, sin cambiar el flujo de DOCX o PDF digitales.

## Archivos principales

### Modificar

```text
src/services/extractor.ts
```

Responsabilidades actuales de este archivo:

- Detectar MIME type.
- Seleccionar extractor.
- Preprocesar imagenes con Sharp.
- Ejecutar Tesseract.js en espanol.

### Posibles archivos nuevos

```text
src/services/ocr/preprocess.ts
src/services/ocr/quality.ts
```

Crear estos archivos solo si el procesamiento empieza a ser demasiado grande para `extractor.ts`.

### Pruebas recomendadas

```text
test/ocr/preprocess.test.ts
test/ocr/extractor-images.test.ts
```

Si el proyecto todavia no tiene framework de pruebas, documentar primero los casos y usar archivos de prueba controlados antes de elegir Jest, Vitest u otra herramienta.

## Mejoras sugeridas

Evaluar, de forma gradual:

- Escala de grises.
- Normalizacion de contraste.
- Binarizacion.
- Reduccion de ruido.
- Nitidez.
- Redimensionamiento para texto pequeno.
- Rotacion u orientacion.
---

# Requisitos transversales para un proyecto real

Esta seccion enumera lo que todavia falta despues de completar las tres ramas de procesamiento. El objetivo no es implementar todo de una vez, sino usarlo como lista de trabajo para pasar de prototipo funcional a sistema operable.

## Estado actual conocido

Antes de integrar nuevas funcionalidades, registrar el estado real:

- [ ] El backend tiene pruebas automatizadas reales.
- [ ] El frontend tiene pruebas automatizadas reales.
- [ ] `npm test` deja de ser un comando placeholder.
- [ ] Existe validacion de entrada con esquemas.
- [ ] Existe autenticacion y autorizacion.
- [ ] Existe persistencia centralizada.
- [ ] Existe almacenamiento seguro de documentos.
- [ ] Existe control de tamano, extension y contenido real del archivo.
- [ ] Existe rate limiting para `/upload`.
- [ ] Existe observabilidad de errores y tiempos.
- [ ] Existe documentacion OpenAPI actualizada.
- [ ] Existe politica de limpieza y retencion de documentos.
- [ ] Existe estrategia de backup y recuperacion.
- [ ] Existe prueba de despliegue en un ambiente de staging.

No marcar una casilla solo porque el codigo compila. Debe existir una prueba o evidencia reproducible.

## Rama recomendada para calidad base

Despues de las tres ramas principales, crear una rama separada:

```bash
git checkout develop
- Recorte de bordes.

```

Si el alcance es grande, dividirla posteriormente en:

```text
feature/backend-testing
feature/supabase-persistence
feature/api-security-validation
feature/observability-documentation
```

---

# 1. Pruebas automatizadas

## Situacion actual

El backend tiene actualmente un script equivalente a:

```text
test: echo "No hay pruebas configuradas todavía"
```

Eso no valida comportamiento. Para un proyecto real, `npm test` debe fallar cuando una funcionalidad se rompe.

## Framework recomendado

Usar:

- **Vitest** para pruebas unitarias y de integracion.
- **Supertest** para probar endpoints Express.
- **Playwright** para un flujo E2E del frontend, como etapa posterior.

## Archivos sugeridos

Backend:

```text
tests/unit/extractor.test.ts
tests/unit/ia.test.ts
tests/integration/upload.test.ts
tests/fixtures/
vitest.config.ts
```

Frontend:

```text
src/**/*.test.jsx
src/services/api.test.js
e2e/upload-flow.spec.js
playwright.config.js
```

## Casos minimos

Backend:

- PDF digital extrae texto.
- DOCX extrae texto.
- Imagen ejecuta OCR.
- MIME no soportado devuelve `400`.
- Archivo ausente devuelve `400`.
- Archivo demasiado grande es rechazado.
- Ollama devuelve un JSON valido.
- Ollama devuelve JSON invalido y se activa el fallback.
- Ollama no responde y el error queda controlado.
- `/health` devuelve `200`.
- `/upload` devuelve el contrato esperado.

Frontend:

- El usuario puede seleccionar archivo.
- Se muestra estado de procesamiento.
- Se muestra resultado de IA.
- Se muestra error del backend.
- El historial agrega el documento procesado.
- El historial conserva el informe ejecutivo.

## Criterio de aceptacion

```text
npm test -> exit code 0
```

Ademas, el CI debe ejecutar pruebas en cada Pull Request hacia `develop` y `main`.

---

# 2. Persistencia con Supabase

Supabase puede cubrir inicialmente tres necesidades:

1. PostgreSQL para datos estructurados.
2. Storage para archivos originales.
3. Auth para usuarios y sesiones.

No conviene guardar el historial solo en `localStorage` para un sistema real: se pierde por navegador, no es compartido entre funcionarios y no permite auditoria centralizada.

## Arquitectura recomendada con Supabase

```text
Frontend
  -> Backend Express
      -> Supabase Auth / PostgreSQL / Storage
      -> Ollama
```

El frontend no deberia conectarse directamente a tablas sensibles. El backend debe controlar las operaciones y usar una clave de servidor protegida.

## Tablas iniciales sugeridas

### `documents`

```text
id uuid primary key
original_name text
mime_type text
storage_path text
status text
created_by uuid
created_at timestamptz
updated_at timestamptz
```

### `document_extractions`

```text
id uuid primary key
No aplicar todos los filtros indiscriminadamente. Un filtro agresivo puede eliminar puntos decimales, firmas o caracteres pequenos.
text_content text
structured_data jsonb
extractor text
confidence numeric
created_at timestamptz
```

### `document_classifications`

```text
id uuid primary key

document_type text
area text
confidence numeric
fields jsonb
executive_report jsonb
summary text
model text
created_at timestamptz
```

### `processing_jobs`

```text
id uuid primary key
Flujo esperado:
status text
attempts integer
error text
started_at timestamptz
finished_at timestamptz
created_at timestamptz
```

### `audit_events`

```text
id uuid primary key
document_id uuid references documents(id)
user_id uuid
event_type text
metadata jsonb
created_at timestamptz
```

## Reglas de Supabase

- Activar Row Level Security.
- Definir politicas por usuario y rol.
- No usar `service_role` en el frontend.
- Guardar solo la URL o ruta del archivo, no duplicar binarios innecesariamente en PostgreSQL.
- Usar Storage privado para documentos tributarios.
- Generar URLs firmadas con tiempo de expiracion.
- Crear indices para RUC, tipo, estado y fechas.
- Definir retencion y borrado de documentos.
- Activar backups y comprobar una restauracion.

## Archivos sugeridos

```text
src/config/supabase.ts
src/repositories/documents.repository.ts
src/repositories/classifications.repository.ts
src/repositories/jobs.repository.ts
src/middleware/auth.ts
src/domain/database.ts
supabase/migrations/
```

Variables esperadas, solo en `.env` o secretos:

```text
SUPABASE_URL
SUPABASE_SERVICE_ROLE_KEY
SUPABASE_ANON_KEY
```

La `SUPABASE_SERVICE_ROLE_KEY` nunca debe enviarse al navegador ni aparecer en logs.

---

# 3. Validacion y contrato de API

El backend debe validar tanto la entrada como la salida.

## Entrada

Validar:

- Tamano maximo.
- MIME declarado.
- Extension.
- Firma real del archivo, no solo el nombre.
- Cantidad de paginas o dimensiones.
- Texto minimo extraible.
- Limites de tiempo.

Evaluar una libreria de esquemas como Zod para validar configuracion y respuestas internas.

## Salida

Definir una respuesta versionada y estable:

```text
POST /api/v1/documents
GET /api/v1/documents/:id
GET /api/v1/jobs/:id
```

Mantener compatibilidad temporal con `/upload` mientras el frontend migra.

La respuesta debe distinguir:

- `400`: entrada invalida.
- `401`: no autenticado.
- `403`: sin permisos.
- `413`: archivo demasiado grande.
- `422`: archivo valido pero imposible de interpretar.
- `429`: demasiadas solicitudes.
- `500`: error interno.
- `503`: servicio IA o cola no disponible.

Documentar la API con OpenAPI y mantener un ejemplo de respuesta por cada tipo documental.

---

# 4. Seguridad

Antes de uso real, implementar:

- Autenticacion mediante Supabase Auth.
- Roles: administrador, operador, revisor y auditor.
- Autorizacion por documento y area.
- Rate limiting para subida y consultas.
- Limites de concurrencia para Ollama.
- Validacion de MIME y firma binaria.
- Sanitizacion de nombres de archivos.
- Almacenamiento privado.
- URLs firmadas de corta duracion.
- CORS limitado a dominios conocidos.
- Headers de seguridad en Nginx.
- No imprimir texto completo de documentos en logs.
- No imprimir claves, tokens ni contenido de `.env`.
- Antivirus o analisis de archivos si el entorno lo requiere.
- Politica de eliminacion de informacion sensible.

La informacion tributaria debe tratarse como sensible aunque los documentos actuales sean ficticios.

---

# 5. Observabilidad y operacion

Agregar logs estructurados con:

```text
requestId
documentId
jobId
event
durationMs
status
errorCode
```

No guardar el texto completo del documento en cada log.

Medir:

- Latencia de subida.
- Tiempo de extraccion.
- Tiempo de OCR.
- Tiempo de Ollama.
- Tasa de errores.
- Reintentos.
- Jobs pendientes.
- Uso de memoria y CPU.
- Tiempo de respuesta de Supabase y Redis.

Mantener:

- Logs de PM2 con rotacion.
- Alertas cuando el backend cae.
- Alertas cuando la cola acumula trabajos.
- Health check de backend.
- Health check de Ollama.
- Health check de Redis, si se incorpora.
- Health check de Supabase, si corresponde.

---

# 6. Correo y derivacion

La derivacion actual es un mapeo de tipo documental a correo. Para un sistema real se necesita:

- Registrar el envio en la base de datos.
- Usar un identificador de mensaje.
- Evitar duplicados.
- Reintentar solo errores temporales.
- Marcar `pending`, `sent`, `failed`.
- Guardar fecha del ultimo intento.
- No guardar credenciales SMTP en el repositorio.
- Validar que el destinatario corresponda al area.

El correo debe ser un job separado de la clasificacion para que una falla SMTP no repita OCR ni Ollama.

---

# 7. Frontend necesario para proyecto real

Aunque el avance se centre en backend, el frontend deberia incorporar:

- Login y cierre de sesion.
- Manejo de token o sesion.
- Historial consultado desde Supabase mediante backend.
- Paginacion real.
- Filtros por estado, tipo, RUC y fecha.
- Estado de procesamiento asincrono.
- Reintento de trabajos fallidos.
- Mensajes de error accionables.
- Validacion de tamano y formato antes de subir.
- Indicador de progreso.
- Vista de auditoria segun rol.
- Pruebas de componentes y E2E.

`localStorage` puede conservar preferencias de interfaz, pero no debe ser la fuente oficial del historial.

---

# 8. CI/CD y ambientes

Separar ambientes:

```text
develop -> staging
main -> production
```

El CI debe ejecutar:

- Instalacion reproducible con `npm ci`.
- Typecheck.
- Lint real.
- Pruebas unitarias.
- Pruebas de integracion.
- Build.
- Auditoria de dependencias.

El CD debe:

- Desplegar solo desde `main` a produccion.
- Usar secretos separados por ambiente.
- Ejecutar migraciones Supabase de forma controlada.
- Mantener backup antes de migraciones destructivas.
- Verificar health check despues del despliegue.
- Permitir rollback a la version anterior.
- No borrar `.env` de la VM.
- Registrar commit desplegado.

Considerar Docker cuando existan varios servicios, staging/production diferentes o necesidad de rollback reproducible.

---

# 9. Documentacion minima

Mantener documentado:

- Arquitectura.
- Flujo de procesamiento.
- Variables de entorno.
- Contratos API.
- Esquema Supabase.
- Politicas de seguridad.
- Operacion de Redis y workers.
- Comandos de desarrollo.
- Comandos de despliegue.
- Procedimiento de rollback.
- Procedimiento de restauracion de backup.
- Casos conocidos y limitaciones.
- Matriz de documentos soportados.

---

# Orden global recomendado para un proyecto real

1. Completar preprocesamiento OCR.
2. Completar parsers nativos DOCX/XLSX y PDF con fallback OCR.
3. Incorporar Vitest, Supertest y pruebas del frontend.
4. Definir contrato API y validacion con esquemas.
5. Incorporar Supabase Auth, PostgreSQL y Storage.
6. Persistir documentos, trabajos, clasificaciones y auditoria.
7. Incorporar Redis y BullMQ.
8. Separar workers de extraccion, IA y correo.
9. Agregar seguridad, rate limiting y control de roles.
10. Agregar logs estructurados, metricas y alertas.
11. Separar staging y production.
12. Añadir rollback, backups y pruebas de recuperacion.
13. Evaluar Docker y escalamiento solamente cuando el volumen lo justifique.

## Definicion de listo para la siguiente etapa

No pasar a la siguiente etapa hasta que la anterior tenga:

- Codigo integrado mediante PR.
- Pruebas automatizadas o evidencia manual documentada.
- Variables de entorno documentadas.
- Criterios de aceptacion cumplidos.
- Build reproducible.
- Sin secretos en Git.
- Validacion en staging.
- Rollback conocido.


## Continuacion de `feature/preprocesamiento-ocr`

La seccion anterior de esta rama define el objetivo y las mejoras. Completar aqui sus decisiones, criterios y pruebas antes de abrir el PR.

```text
Imagen original
  -> detectar tipo y calidad
  -> aplicar perfil de preprocesamiento
  -> Tesseract en espanol
  -> limpiar texto
  -> validar longitud y calidad
```

## Decisiones que se deben documentar

- Que filtros se aplican siempre.
- Que filtros se aplican solo si la imagen tiene baja calidad.
- Como se detecta una imagen vacia o ilegible.
- Que ocurre si OCR devuelve menos de 20 caracteres.
- Si se conserva la imagen original para auditoria.

## Criterios de aceptacion

- PNG, JPG y JPEG siguen siendo aceptados.
- El texto OCR mejora en documentos con bajo contraste.
- No se altera el flujo de PDF digital ni DOCX.
- Se detectan errores cuando el texto extraido es insuficiente.
- Se registran tiempo y resultado del OCR.
- El backend mantiene `npm run typecheck` y `npm run build` exitosos.

## Pruebas manuales

Probar al menos:

- Imagen clara.
- Imagen oscura.
- Imagen inclinada.
- Imagen con ruido.
- Imagen con montos y decimales.
- Imagen con RUC y fechas.

Comparar antes y despues estos campos:

```text
RUC, montos, fechas, nombres, periodo, saldo y numero de cuotas
```

---

# Rama 2: `feature/parsers-documentos-nativos`

## Objetivo

Usar el extractor correcto segun el tipo de archivo. No usar OCR para todo.

```text
DOCX nativo -> parser DOCX
XLSX nativo -> parser XLSX
PDF con texto -> parser PDF
PDF escaneado -> OCR
PNG/JPG -> OCR
```

## Archivos principales

### Modificar

```text
src/services/extractor.ts
package.json
package-lock.json
src/routes/upload.ts
```

### Posibles archivos nuevos

```text
src/services/parsers/docx.ts
src/services/parsers/xlsx.ts
src/services/parsers/pdf.ts
src/services/parsers/types.ts
```

Separar parsers es recomendable cuando `extractor.ts` empiece a tener demasiadas condiciones.

## DOCX

Actualmente se utiliza Mammoth para extraer texto. Mantenerlo para DOCX sencillos y evaluar un parser adicional si se necesita conservar:

- Tablas.
- Celdas.
- Orden de lectura.
- Encabezados.
- Secciones.
- Metadatos.

El resultado deberia normalizarse a un formato comun, por ejemplo:

```text
{
  text,
  blocks,
  tables,
  metadata,
  mimeType
}
```

No enviar directamente estructuras imposibles de validar a Ollama. Primero normalizar.

## XLSX

Agregar soporte nativo para XLSX mediante una libreria especializada, por ejemplo SheetJS o ExcelJS.

Extraer como minimo:

- Nombre de hoja.
- Rango utilizado.
- Filas y columnas.
- Encabezados.
- Valores numericos sin perder decimales.
- Fechas normalizadas.
- Tablas relevantes.

No convertir una hoja de calculo a imagen salvo que no exista otra forma de leerla.

## PDF

Usar dos rutas:

```text
PDF con capa de texto -> pdf-parse u otro parser
PDF sin texto suficiente -> convertir a imagen y aplicar OCR
```

La deteccion debe basarse en la cantidad y calidad del texto extraido, no solo en la extension `.pdf`.

## Compatibilidad del endpoint

`src/routes/upload.ts` debe continuar devolviendo al frontend:

```text
tipoDocumento
area
confianza
campos
informeEjecutivo
resumenEjecutivo
derivacion
```

Si se agrega estructura de tablas, hacerlo sin romper esos campos existentes.

## Criterios de aceptacion

- DOCX nativo no pasa por OCR.
- XLSX se procesa sin perder numeros ni fechas.
- PDF digital usa parser de texto.
- PDF escaneado utiliza OCR como respaldo.
- Los datos llegan a la IA en un formato claro.
- Los documentos anteriores de `test-docs` siguen clasificandose correctamente.
- Se prueba al menos un documento por cada formato.

## Pruebas recomendadas

Crear una matriz por formato:

```text
DOCX con parrafos
DOCX con tablas
XLSX con montos
XLSX con fechas
PDF digital
PDF escaneado
PNG
JPG
```

Verificar especialmente:

- RUC.
- Periodo.
- Fechas.
- Totales.
- Decimales.
- Numero de cuotas.
- Saldo a pagar.

---

# Rama 3: `feature/cola-procesamiento-ollama`

## Objetivo

Desacoplar la peticion HTTP del procesamiento pesado de IA y controlar concurrencia, reintentos y errores.

Actualmente el flujo es sincrono:

```text
POST /upload
  -> extraer texto
  -> llamar Ollama
  -> generar resumen
  -> responder
```

El flujo objetivo es asincrono:

```text
POST /upload
  -> validar y registrar trabajo
  -> encolar job
  -> responder jobId

Worker
  -> extraer o recibir texto
  -> llamar Ollama
  -> reintentar si falla
  -> guardar resultado
  -> marcar estado
```

## Dependencias y servicios

BullMQ necesita Redis. Antes de implementar, definir:

- Donde se ejecutara Redis.
- Si tendra persistencia.
- Como se protegera el acceso.
- Que ocurre si Redis se reinicia.
- Que limite de memoria tendra.

Para la VM actual, comenzar con concurrencia `1` para Ollama en CPU.

## Archivos sugeridos

### Modificar

```text
src/routes/upload.ts
src/services/extractor.ts
src/services/ia.ts
src/index.ts
package.json
package-lock.json
```

### Crear

```text
src/queues/connection.ts
src/queues/document.queue.ts
src/workers/document.worker.ts
src/services/job-status.ts
src/domain/jobs.ts
```

Si el correo se incorpora en este avance:

```text
src/queues/email.queue.ts
src/workers/email.worker.ts
src/services/mailer.ts
```

## Estados del trabajo

Definir estados explicitos:

```text
pending
processing
completed
failed
retrying
```

Cada trabajo deberia tener como minimo:

```text
jobId
fileName
mimeType
createdAt
updatedAt
attempts
status
error
```

## Reintentos

Configurar reintentos solo para errores temporales:

- Ollama no responde.
- Timeout temporal.
- Redis pierde conexion momentaneamente.
- SMTP no responde.

No reintentar indefinidamente:

- Archivo invalido.
- MIME no soportado.
- Credenciales SMTP invalidas.
- JSON permanentemente invalido.

Usar backoff progresivo y un numero maximo de intentos.

## Correos con Nodemailer

El correo debe ser un trabajo independiente:

```text
Procesamiento IA completado
  -> crear job de correo
  -> intentar envio
  -> marcar sent o failed
```

Un fallo del correo no deberia repetir la extraccion ni la clasificacion.

## Cambios esperados en el frontend

El frontend ya no deberia esperar indefinidamente el `POST /upload`.

Archivos posibles:

```text
src/services/api.js
src/App.jsx
src/pages/UploadPage.jsx
src/pages/ResultsPage.jsx
src/components/ProcessingModal.jsx
```

Flujo objetivo:

```text
Subir archivo
  -> recibir jobId
  -> consultar estado
  -> mostrar progreso
  -> cargar resultado cuando completed
```

Alternativas futuras a polling:

- Server-Sent Events.
- WebSocket.
- Notificacion push.

Comenzar con polling simple si el volumen todavia es bajo.

## Criterios de aceptacion

- Una subida devuelve un `jobId`.
- El frontend puede consultar el estado.
- Ollama no recibe mas trabajos simultaneos que el limite definido.
- Los fallos temporales se reintentan.
- Los trabajos fallidos quedan visibles y explican el error.
- El correo tiene sus propios reintentos.
- Reiniciar el worker no pierde trabajos pendientes si Redis tiene persistencia.
- El backend no queda bloqueado durante toda la inferencia.

---

# Validacion entre ramas

## Validacion individual

En el backend:

```bash
npm ci
npm run typecheck
npm run build
npm test
```

En el frontend:

```bash
npm ci
npm run build
```

Si no existen pruebas automatizadas, documentar la prueba manual realizada y crear pruebas antes de integrar la funcionalidad.

## Validacion de integracion

Probar el flujo completo:

```text
Archivo -> endpoint -> extraccion -> IA -> resumen -> frontend
```

Comprobar que no se rompan:

- `/health`
- `/upload`
- Clasificacion documental.
- Campos extraidos.
- Informe ejecutivo.
- Derivacion.
- Historial del frontend.

## Metricas recomendadas

Registrar antes y despues:

- Tiempo de extraccion.
- Tiempo de OCR.
- Tiempo de Ollama.
- Tiempo total.
- Porcentaje de campos correctos.
- Porcentaje de jobs fallidos.
- Numero de reintentos.
- Uso de CPU y memoria.

---

# Despliegue de cada avance

No desplegar una rama `feature` directamente a produccion.

Flujo:

```text
feature/*
  -> Pull Request a develop
  -> pruebas de integracion
  -> Pull Request de develop a main
  -> CD hacia Azure
```

En Azure verificar despues de cada despliegue:

```text
PM2 online
GET /health = 200
GET /api/health = 200
Nginx valido
Ollama accesible
Redis accesible, si aplica
```

Para cambios en colas, comprobar ademas:

- Worker activo.
- Jobs pendientes visibles.
- Reintentos funcionando.
- No hay duplicados.
- El frontend recibe estados correctos.

---

# Riesgos y decisiones pendientes

Completar durante la implementacion:

- [ ] Elegir parser nativo para XLSX.
- [ ] Definir formato normalizado de tablas.
- [ ] Definir umbral de calidad OCR.
- [ ] Decidir si se guarda la imagen original.
- [ ] Elegir Redis local o administrado.
- [ ] Definir concurrencia maxima de Ollama.
- [ ] Definir cantidad y backoff de reintentos.
- [ ] Definir politica de limpieza de jobs.
- [ ] Definir formato de progreso para el frontend.
- [ ] Agregar pruebas automatizadas.
- [ ] Medir resultados antes y despues.
- [ ] Documentar variables de entorno nuevas.

# Resultado esperado

Al finalizar este avance, el sistema deberia:

1. Leer imagenes de baja calidad con menos errores.
2. Extraer DOCX y XLSX nativos sin depender de OCR.
3. Procesar PDF digitales y escaneados por rutas diferentes.
4. Controlar las peticiones a Ollama mediante una cola.
5. Reintentar errores temporales de IA y correo.
6. Mantener estados claros y trazables.
7. Conservar compatibilidad con el frontend y los informes ejecutivos actuales.
