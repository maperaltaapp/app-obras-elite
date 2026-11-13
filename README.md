# TU CONTROLAS

Aplicación web para gestión de obras. La versión publicada se sirve desde GitHub Pages:
https://maperaltaapp.github.io/tu-controlas-app/

## Cambios de esta entrega

- Navegación inferior fija con Tareas, Panel de Control, Gantt, Checklist y Partes; tema blanco y calendario superior.
- Tareas de hoy unificadas; prioridad urgente señalada en rojo. Edición rápida al mantener pulsada una tarea y controles para reordenar.
- Checklist por obra con Preparación, Subcontratas y Proveedores, Ejecución y Cierre. Los elementos con fecha se muestran en Tareas desde su mismo registro.
- Gantt con edición manual, flechas de dependencias, predecesoras y sucesoras, confirmación de reprogramaciones, tareas vinculadas y progreso sincronizado.
- Partes con botón destacado «+ Parte» e historial compacto, conservando el formulario y los registros existentes.
- Panel de Control conserva su diseño anterior.

## Estado y límites comprobados

- El esquema de Checklist y la sincronización de porcentaje del Gantt se aplicaron a Supabase como cambios aditivos; no se editaron ni borraron registros de obra existentes.
- La página pública sirve el título TU CONTROLAS y carga la pantalla de acceso. La verificación de operaciones con datos requiere una sesión autenticada.
- La jerarquía tiene un campo de nivel y fases/grupos; el modelo padre-hijo completo para fase, tarea y subtarea aún requiere desarrollo.
- El asistente conserva dictado y órdenes disponibles en la aplicación; no incorpora IA generativa conectada a ChatGPT. Las órdenes de voz múltiples no equivalen a una conversación de IA.

## Verificaciones locales

- `node test-planning.cjs` pasó para dependencias y programación.
- La sintaxis del JavaScript embebido se comprobó con `node --check`.
- La interfaz autenticada, la escritura real de tareas y la persistencia al volver a abrir aún deben verificarse con una cuenta en una sesión de prueba.
