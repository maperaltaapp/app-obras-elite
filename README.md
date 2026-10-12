# App Obras Elite

Gestión personal de obras, tareas y calendario. Esta rama prepara la gestión nativa en Supabase para dejar de consultar Trello, manteniendo el diseño compacto y la navegación Tareas · Calendario · Obras.

## Estado de esta rama

**Candidata: no desplegar antes de aplicar y verificar la migración.** La producción continúa en `main`; respaldo previo: `backup/elite-2026-10-12`, commit `adacac472169e9383de588f74e97f4b59e87622d`.

- Obras propias con inicio, fin, etapas, avance, archivo y enlace opcional a su chat de ChatGPT.
- Tareas con notas, inicio/vencimiento, estados, prioridades, etiquetas, checklists editables y archivo recuperable.
- Búsqueda por obra, texto y etiqueta; filtros por tipo, obra, prioridad y estado.
- Repetición diaria, semanal o mensual: la siguiente tarea se genera al completar la anterior, con casillas reiniciadas. Se conserva la hora de Madrid, incluido el cambio estacional; fin de mes se ajusta al último día válido.
- Historial de cambios desde la entrada en Elite. No se copia el registro histórico completo de actividad de Trello.
- Calendario compacto, títulos resumidos, desplegables, festivos ya existentes y hitos rojos conservados.
- Fechas y avance antiguos guardados solo en el móvil: botón «Recuperar fechas de este dispositivo» en cada obra importada. Solo rellena campos vacíos, no elimina el original local.
- Notificaciones explícitamente pendientes. No se cambia la verificación JWT de las funciones ni se promete entrega de avisos. Las tareas de ChatGPT siguen siendo independientes.
- El enlace de chat abre ChatGPT; no implementa IA de pago, micrófono ni escritura automática desde conversaciones.
- Sin adjuntos ni documentación empresarial pesada, funciones de equipos o permisos colaborativos.

## Activación

1. Confirmar el respaldo de código y mantener los tableros originales en Trello.
2. Ejecutar `native-schema.sql` **una vez** sobre el esquema existente de `tasks-schema.sql`. Es una transacción aditiva y captura las tareas existentes en una tabla privada antes de ampliar el esquema. No volver a ejecutar `tasks-schema.sql` en producción.
3. Revisar y ejecutar la importación privada preparada fuera del repositorio. Antes del corte definitivo, comprobar cambios producidos en Trello desde la exportación. Nunca publicar datos reales en este repositorio público.
4. Verificar recuentos y muestras, aislamiento con dos usuarios, creación/edición y archivo desde la app autenticada, y visualización en móvil.
5. Solo entonces integrar esta rama en `main` y verificar GitHub Pages.

El rollback del frontend consiste en restaurar el `index.html` del respaldo. No borra ni revierte las nuevas tablas ni los datos; antes de volver atrás después de uso real, conservar también las tareas nuevas y sus cambios.

## Pruebas

Con Node.js: `npm install` y `npm test`.

- `test-app.cjs`: vistas nativas, filtros, edición de checklist, calendario compacto, validación de fechas, conflictos de edición y fallos de carga sin consultar Trello.
- `test-database.cjs`: PostgreSQL embebido (PGlite), migración, aislamiento RLS, claves foráneas entre propietarios, historial protegido, repetición sin duplicados, cambio horario y final de mes.

La importación privada también se probó dos veces en una base aislada sin duplicar datos. Estas pruebas no sustituyen la comprobación final del proyecto real y del navegador autenticado.
