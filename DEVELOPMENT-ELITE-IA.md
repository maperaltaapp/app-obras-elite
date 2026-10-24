# Élite IA: bandeja de revisión

Actualización incremental del 24-10-2026. Conserva Tareas · Calendario · Obras y usa la sesión de Elite, sus políticas RLS y las tablas existentes. No añade servicios de pago, claves privadas ni cambios de esquema.

## Incluido

- Acceso Élite IA en la cabecera y enlace directo con `#ia`.
- Interpretaciones por confirmar, aprendizajes pendientes, aprobados, rechazados y correcciones revisadas.
- Confirmar interpretación llama a `elite_ai_resolve_correction` con la versión revisada y crea una propuesta `pending`.
- Aprobar/rechazar exige seleccionar una decisión explícita después de ver la conclusión, fundamento, condiciones y fuente. PATCH condicionado a ID, versión y estado pendiente; comprueba la respuesta guardada.
- Historial completo, sin borrado ni caducidad. Contenido escapado y enlaces de origen limitados a HTTPS de ChatGPT.
- Acceso a tareas vencidas reales (excluye finalizadas, archivadas y sin fecha) y creación usando el formulario existente.
- Retirados de la cabecera los botones Avisos y Actualizar. Conserva recordatorios, notificaciones y su configuración existente.

## Comprobaciones

`node test-ai.cjs` comprueba separación de estados, decisiones expresas, confirmación sin aprobación, conflictos de versión, doble envío y protección frente a contenido HTML/enlaces peligrosos.

Regresión ejecutada con las suites actuales de tareas, interfaz, detalle de obra, avance físico y calendario semanal. Flujo de corrección, revisión y confirmación probado contra PostgreSQL como usuario autenticado dentro de una transacción revertida: ningún aprendizaje real aprobado ni datos de prueba persistidos.

## Límites

La bandeja no es un motor de conversación nuevo. Las órdenes naturales siguen dependiendo de ChatGPT y de las herramientas MCP disponibles en cada chat. El servidor MCP incluye correo y memoria, pero el cliente observado solo expone las diez herramientas de obras y tareas; hace falta refrescar la definición del conector y verificar sus funciones nuevas.

No se ha encontrado en la documentación oficial consultada un webhook general para mensajes de todos los chats nativos de un proyecto ChatGPT. Los webhooks de OpenAI documentados corresponden a eventos de la API. Mantener `automatic_chat_capture_ready=false` hasta una prueba real transversal. Las instrucciones compartidas no sustituyen un mecanismo de entrada.

Fuentes: https://developers.openai.com/plugins/build/mcp-server y https://developers.openai.com/api/docs/guides/webhooks

Quedan pendientes la captura entre chats, la comprobación autenticada completa desde la interfaz publicada en distintos dispositivos, la actualización del conector, la restauración integral de copias y la validación de las automatizaciones existentes. No se han aprobado criterios técnicos reales.

## Reversión

Restaurar `index.html` desde el commit anterior. Esta versión no requiere revertir base de datos, funciones ni configuraciones. Guardar el código anterior antes de integrar.
