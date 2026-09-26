# Gestor Inteligente de Documentos

Resumen del proyecto, decisiones tecnicas, cambios realizados durante esta sesion y estado actual de los repositorios.

## 1. Descripcion del proyecto

El proyecto es un prototipo funcional de un sistema web inteligente para gestion documental orientado a documentos tributarios de SUNAT.

Flujo principal:

```text
Usuario sube documento
    -> Backend recibe archivo
    -> Extraccion de texto
    -> OCR si corresponde
    -> Clasificacion con Ollama
    -> Extraccion de campos
    -> Resumen e informe ejecutivo
    -> Derivacion al area correspondiente
    -> Historial en el frontend
```

El backend esta desarrollado con Node.js y TypeScript. El frontend usa React y Vite.

## 2. Equipo y responsabilidades

| Integrante | Rol | Responsabilidades |
| --- | --- | --- |
| Juan Aldair Ramirez | Backend / IA | Express, TypeScript, extraccion, OCR, Ollama, prompts e integracion backend |
| Luis Fernando Flores | Frontend / UI | React, Vite, carga de archivos, dashboard, resultados e historial |
| Edu Andre Perez | Automatizaciones / RPA / BD | Nodemailer, PostgreSQL, RPA, n8n y flujos automatizados |
| Alexander Valenzuela | DevOps / QA / documentacion | GitHub, GitHub Actions, ramas, pruebas, despliegue y documentacion |

## 3. Reglas Git

- `main`: codigo estable para sustentacion.
- `develop`: integracion.
- `feature/*`: nuevas funcionalidades.
- `fix/*`: correcciones.
- `docs/*`: documentacion.
- No hacer push directo a `main` ni `develop`.
- Todo cambio debe pasar por Pull Request.
- Flujo esperado: `feature/* -> develop -> main`.
- Commits permitidos: `feat:`, `fix:`, `docs:` y `chore:`.

## 4. Estructura actual

### Backend

Ruta: `Gestor-Inteligente-de-Documentos/`

```text
src/
  app.ts
  index.ts
  domain/jobs.ts
  domain/sunat/areas.ts
  prompts/classifier.ts
  queues/connection.ts
  queues/document.queue.ts
  routes/upload.ts
  services/document-processing.ts
  services/extractor.ts
  services/ia.ts
  services/ocr/preprocess.ts
  services/ocr/quality.ts
  services/parsers/docx.ts
  services/parsers/types.ts
  services/parsers/xlsx.ts
  workers/document.worker.ts
  utils/env.ts
tests/
  unit/extractor.test.ts
  unit/ia.test.ts
  integration/upload.test.ts
vitest.config.mts
```

### Frontend

Ruta: `Gestor-Inteligente-de-Documentos-Frontend/`

Archivos relacionados con estos cambios:

```text
src/App.jsx
src/components/Dropzone.jsx
src/services/api.js
e2e/upload-flow.spec.js
playwright.config.js
```

### Graphify

Se revisaron los archivos generados por Graphify:

```text
graphify-out/graph.html
graphify-out/graph.json
graphify-out/GRAPH_REPORT.md
```

El grafo se utilizo para inspeccionar la estructura y relaciones del proyecto existente. No representa una tercera aplicacion ni debe confundirse con el backend o el frontend. Los archivos generados por Graphify deben tratarse como artefactos de analisis y no incluirse en commits salvo que el equipo los necesite expresamente.

## 5. Funcionalidad existente

El backend ya tenia:

- Express con TypeScript.
- `GET /health`.
- `POST /upload`.
- Multer con limite de 10 MB.
- Extraccion PDF mediante `pdf-parse`.
- Extraccion DOCX mediante `mammoth`.
- OCR para imagenes mediante `tesseract.js` en espanol.
- Preprocesamiento inicial con `sharp`.
- Clasificacion local con Ollama.
- Modelo configurable mediante `OLLAMA_MODEL`.
- Respuesta con tipo documental, confianza, campos, resumen, informe y derivacion.
- Fallback local por palabras clave si Ollama no responde.

El frontend ya tenia:

- React + Vite.
- Drag and drop.
- Pantalla de procesamiento.
- Resultados de clasificacion.
- Historial local.
- Vista de error.
- Consumo del endpoint `/upload`.

## 6. Tipos de documentos SUNAT

La clasificacion contempla 15 tipos:

1. `SOLICITUD_INSCRIPCION_RUC`
2. `ACTUALIZACION_RUC`
3. `DECLARACION_JURADA_MENSUAL`
4. `DECLARACION_JURADA_ANUAL`
5. `RESOLUCION_FRACCIONAMIENTO`
6. `RESOLUCION_APLAZAMIENTO`
7. `ORDEN_PAGO_OP`
8. `RESOLUCION_DETERMINACION_RD`
9. `RESOLUCION_MULTA_RM`
10. `REQUERIMIENTO_FISCALIZACION`
11. `AUDITORIA_LIBROS`
12. `CARTA_PRESENTACION`
13. `NOTIFICACION_ELECTRONICA`
14. `SOLICITUD_APLAZAMIENTO`
15. `RESOLUCION_APLAZAMIENTO_FRACCIONAMIENTO`

Areas principales:

- Recaudacion y Control Masivo.
- Fiscalizacion.
- Juridica / Reclamaciones.

## 7. Prompt de clasificacion

El prompt esta en [classifier.ts](Gestor-Inteligente-de-Documentos/src/prompts/classifier.ts).

Su contrato solicita un JSON con:

- `tipoDocumento`.
- `confianza`.
- `campos`.
- `resumenEjecutivo`.
- `informeEjecutivo`.

Observaciones realizadas:

- Habia reglas duplicadas para `ORDEN_PAGO_OP`.
- El texto indicaba un maximo de 2500 caracteres, pero la funcion recortaba a 12000.
- La confianza se limita posteriormente entre 0 y 1.
- El backend cuenta con fallback por palabras clave.
- La extraccion local de campos complementa la respuesta de Ollama.

## 8. Recomendaciones del Avance 2

La guia del avance recomienda este orden:

```text
1. Preprocesamiento OCR
2. Parsers nativos DOCX/XLSX
3. Cola de procesamiento para Ollama
4. Pruebas automatizadas
5. Persistencia y seguridad
```

Objetivos:

- Reducir errores OCR en imagenes de baja calidad.
- No aplicar OCR a documentos que ya tienen texto digital.
- Conservar tablas, numeros y fechas.
- Evitar saturar Ollama.
- Reintentar errores temporales.
- Mantener trazabilidad de los trabajos.

## 9. Cambios implementados en el backend

### 9.1 Preprocesamiento OCR

Se creo [preprocess.ts](Gestor-Inteligente-de-Documentos/src/services/ocr/preprocess.ts).

El flujo aplica:

```text
Imagen
  -> rotacion automatica
  -> redimensionamiento
  -> escala de grises
  -> normalizacion de contraste
  -> nitidez
  -> binarizacion por umbral
  -> PNG para Tesseract
```

Esto se aplica unicamente a imagenes que pasan por OCR.

### 9.2 Parsers nativos

Se creo una salida comun en [types.ts](Gestor-Inteligente-de-Documentos/src/services/parsers/types.ts):

```text
text
blocks
tables
metadata
```

DOCX:

- [docx.ts](Gestor-Inteligente-de-Documentos/src/services/parsers/docx.ts).
- Usa Mammoth.
- Extrae texto y tablas.

XLSX:

- [xlsx.ts](Gestor-Inteligente-de-Documentos/src/services/parsers/xlsx.ts).
- Usa SheetJS mediante el paquete `xlsx`.
- Conserva hojas, filas, encabezados, valores, montos y fechas como texto normalizado.

Rutas del extractor:

```text
DOCX -> parser DOCX
XLSX -> parser XLSX
PDF -> pdf-parse
Imagen -> Sharp + Tesseract
```

Tambien se acepta XLSX cuando el navegador envia `application/octet-stream`, siempre que la extension sea valida.

### 9.3 Cola BullMQ y Redis

Se agregaron:

- [connection.ts](Gestor-Inteligente-de-Documentos/src/queues/connection.ts).
- [document.queue.ts](Gestor-Inteligente-de-Documentos/src/queues/document.queue.ts).
- [jobs.ts](Gestor-Inteligente-de-Documentos/src/domain/jobs.ts).
- [document-processing.ts](Gestor-Inteligente-de-Documentos/src/services/document-processing.ts).
- [document.worker.ts](Gestor-Inteligente-de-Documentos/src/workers/document.worker.ts).

Estados funcionales:

```text
pending
processing
completed
failed
retrying
```

`POST /upload` mantiene dos modos:

- `QUEUE_ENABLED=false`: procesamiento sincrono compatible con el frontend anterior.
- `QUEUE_ENABLED=true`: devuelve `202` y un `jobId`.

Consulta de estado:

```text
GET /upload/status/:jobId
```

Configuracion:

```env
QUEUE_ENABLED=false
REDIS_URL=redis://127.0.0.1:6379
QUEUE_ATTEMPTS=3
QUEUE_BACKOFF_MS=2000
OLLAMA_CONCURRENCY=1
```

Worker:

```bash
npm run worker
```

La cola de correo Nodemailer todavia no se implemento porque el backend no tenia un servicio real de correo integrado. La cola documental deja preparada la separacion para agregarlo como trabajo independiente.

## 10. Cambios implementados en el frontend

Se modifico [api.js](Gestor-Inteligente-de-Documentos-Frontend/src/services/api.js) para agregar `waitForDocument`.

Se modifico [App.jsx](Gestor-Inteligente-de-Documentos-Frontend/src/App.jsx) para:

- Detectar si `/upload` devuelve `jobId`.
- Consultar periodicamente el estado.
- Mostrar documento en cola.
- Mostrar procesamiento con IA.
- Mostrar reintentos.
- Mantener compatibilidad con respuestas sincrónicas.

Se modifico [Dropzone.jsx](Gestor-Inteligente-de-Documentos-Frontend/src/components/Dropzone.jsx) para permitir `.xlsx`.

## 11. Pruebas automatizadas

### Backend

Se incorporo Vitest mediante [vitest.config.mts](Gestor-Inteligente-de-Documentos/vitest.config.mts).

Se incorporo Supertest separando la aplicacion Express en [app.ts](Gestor-Inteligente-de-Documentos/src/app.ts). `src/index.ts` ahora inicia el servidor, mientras `app.ts` permite probarlo sin abrir un puerto real.

Pruebas actuales:

- `/health` responde 200.
- `/upload` sin archivo responde 400.
- XLSX extrae tablas y valores sin OCR.
- Tipos no soportados son rechazados.
- El prompt incluye el texto y aplica truncamiento.

Comandos:

```bash
npm test
npm run test:watch
npm run typecheck
npm run build
```

Resultado validado:

```text
Test Files: 3 passed
Tests: 5 passed
```

### Frontend

Se incorporo Playwright en [playwright.config.js](Gestor-Inteligente-de-Documentos-Frontend/playwright.config.js).

Flujo E2E actual en `e2e/upload-flow.spec.js`:

- Abre la aplicacion.
- Verifica el titulo.
- Verifica la visibilidad del boton de subida.

Comandos:

```bash
npm run build
npm run test:e2e
```

Resultado validado:

```text
1 passed
```

Los resultados temporales de Playwright se excluyen mediante `.gitignore`.

## 12. Problema del despliegue CD en Azure

El CD fallo despues de reiniciar PM2 con:

```text
Backend did not become healthy in time
```

La VM usaba:

```text
Node v18.20.8
```

Pero varias dependencias requerian versiones superiores:

- `ioredis`: Node >= 20.
- `sharp`: Node >= 20.9.
- `vite`: Node >= 20.19 o >= 22.12.
- `vitest`: Node >= 22.12.

Ademas, el codigo tenia este error:

```ts
const PORT = Number(process.env.PORT) ?? 3000;
```

`Number(undefined)` produce `NaN`, por lo que `?? 3000` no se activa.

## 13. Correccion del CD y Node en Azure

Se creo la rama:

```text
fix/cd-azure-node-runtime
```

Commit actual:

```text
9fc8702 fix: corregir despliegue Azure y health check
```

Cambios en [CD.yml](Gestor-Inteligente-de-Documentos/.github/workflows/CD.yml):

- Carga `nvm` en la VM.
- Instala y usa Node `22.12.0`.
- Muestra las versiones de Node y npm.
- Elimina el proceso PM2 anterior para garantizar el interprete correcto.
- Inicia PM2 usando el Node seleccionado por nvm.
- Lee el puerto configurado en `.env`.
- Espera hasta 30 segundos por el health check.
- Muestra estado y logs de PM2 si falla.

Correccion en [index.ts](Gestor-Inteligente-de-Documentos/src/index.ts):

```ts
const parsedPort = Number.parseInt(process.env.PORT ?? '3000', 10);
const PORT = Number.isFinite(parsedPort) ? parsedPort : 3000;
```

En la VM se instalo correctamente:

```text
nvm v0.40.3
Node v22.12.0
npm v10.9.0
```

## 14. Estado de ramas y commits

### Backend

Rama actual:

```text
fix/cd-azure-node-runtime
```

Commits relevantes:

```text
9fc8702 fix: corregir despliegue Azure y health check
f5a05cd feat: mejorar procesamiento documental y agregar cola Ollama
```

### Frontend

Rama actual:

```text
main
```

Commit relevante:

```text
6cac6cc feat: consumir estados de procesamiento documental
```

## 15. Validaciones realizadas

Backend:

```text
npm test              correcto
npm run typecheck     correcto
npm run build         correcto
git diff --check      correcto
```

Frontend:

```text
npm run build         correcto
npm run test:e2e      correcto
git diff --check      correcto
```

## 16. Variables de entorno importantes

Backend minimo:

```env
PORT=3000
FRONTEND_URL=http://localhost:5173
OLLAMA_HOST=http://localhost:11434
OLLAMA_MODEL=phi3
OLLAMA_TIMEOUT_MS=180000
```

Cola:

```env
QUEUE_ENABLED=false
REDIS_URL=redis://127.0.0.1:6379
QUEUE_ATTEMPTS=3
QUEUE_BACKOFF_MS=2000
OLLAMA_CONCURRENCY=1
```

El archivo `.env` nunca debe subirse a GitHub. Solo debe existir en la VM o como secreto del entorno.

## 17. Pendientes

### Prioridad inmediata

- Abrir PR de `fix/cd-azure-node-runtime` hacia `develop`.
- Integrar `develop` hacia `main` despues de validar CI.
- Ejecutar nuevamente el CD en Azure.
- Confirmar `GET /health` desde la VM y desde el dominio publico.
- Confirmar que PM2 mantiene el proceso despues de reiniciar la VM.

### Avance 2

- Agregar pruebas de imagen clara, oscura, inclinada y con ruido.
- Agregar prueba de PDF digital.
- Agregar fallback PDF escaneado hacia OCR.
- Agregar pruebas DOCX con tablas.
- Agregar pruebas XLSX con fechas, decimales y montos.
- Levantar Redis y probar trabajos concurrentes.
- Probar timeout de Ollama y backoff.
- Separar el envio de correo en una cola propia.

### Proyecto real

- Implementar Nodemailer real como job independiente.
- Agregar persistencia centralizada.
- Incorporar PostgreSQL o Supabase.
- Guardar estados e historial.
- Agregar validacion de esquema con Zod.
- Validar firma real del archivo y MIME.
- Incorporar rate limiting.
- Agregar autenticacion y roles.
- Agregar logs estructurados y metricas.
- Documentar OpenAPI.
- Separar staging y produccion.
- Configurar backups y rollback.
- Añadir CI completo para typecheck, lint, pruebas y build.

## 18. Comandos frecuentes

Backend:

```bash
cd ~/Proyectos/HerramientasTic-proyecto/Gestor-Inteligente-de-Documentos
npm ci
npm run dev
npm test
npm run typecheck
npm run build
npm run worker
```

Frontend:

```bash
cd ~/Proyectos/HerramientasTic-proyecto/Gestor-Inteligente-de-Documentos-Frontend
npm ci
npm run dev
npm run build
npm run test:e2e
```

Git para la correccion de Azure:

```bash
git switch fix/cd-azure-node-runtime
git push -u origin fix/cd-azure-node-runtime
```

## 19. Criterio de finalizacion del avance

El avance puede considerarse listo cuando:

- Cada cambio esta integrado mediante PR.
- El backend compila.
- Las pruebas automatizadas pasan.
- El frontend compila.
- El E2E pasa.
- Redis y el worker fueron probados si la cola esta activada.
- Ollama respeta la concurrencia configurada.
- Los errores temporales se reintentan.
- Azure responde correctamente en `/health`.
- No existen secretos en Git.
- Existe un procedimiento de rollback.
