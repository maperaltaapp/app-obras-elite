# TU CONTROLAS

Aplicación web para gestión de obras. La versión publicada se sirve desde GitHub Pages:
https://maperaltaapp.github.io/tu-controlas-app/

## Cambios de esta entrega

- Navegación inferior fija con Tareas, Panel de Control, Gantt, Checklist y Partes; tema blanco y calendario superior.
- Tareas de hoy unificadas; prioridad urgente señalada en rojo. Edición rápida al mantener pulsada una tarea y controles para reordenar.
- Checklist por obra con Preparación, Subcontratas y Proveedores, Ejecución y Cierre. Los elementos con fecha se muestran en Tareas desde su mismo registro.
- Gantt con edición manual, jerarquía Fase → Tarea → Subtarea, flechas de dependencias, confirmación de reprogramaciones, tareas vinculadas y avance calculado solo con actividades finales.
- Partes con botón destacado «+ Parte» e historial compacto, conservando el formulario y los registros existentes.
- Panel de Control conserva su diseño anterior.

## Estado y límites comprobados

- El esquema de Checklist y la sincronización de porcentaje del Gantt se aplicaron a Supabase como cambios aditivos; no se editaron ni borraron registros de obra existentes.
- La página pública sirve el título TU CONTROLAS y carga la pantalla de acceso. La verificación de operaciones con datos requiere una sesión autenticada.
- La validación padre-hijo y la reprogramación de fechas de fases contenedoras ya están activas en la aplicación y en Supabase. Las funciones de guardado siguen protegidas por el usuario propietario y no se cambiaron registros existentes.
- El asistente conserva dictado y órdenes disponibles en la aplicación; no incorpora IA generativa conectada a ChatGPT. Las órdenes de voz múltiples no equivalen a una conversación de IA.

## Verificaciones locales

- `node test-database.cjs`, `node test-planning.cjs` y `node test-planning-database.cjs` pasaron.
- `npm test` aún tropieza con una expectativa antigua de `test-app.cjs` (`dated`), que no coincide con el filtro actual (`all`). La sintaxis del JavaScript se comprobó por separado.
- La sintaxis del JavaScript embebido se comprobó con `node --check`.
- La interfaz autenticada, la escritura real de tareas y la persistencia al volver a abrir aún deben verificarse con una cuenta en una sesión de prueba.
