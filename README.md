# Elite: planificación y subcontratas

Rama candidata, todavía sin publicar. Conserva Tareas · Calendario · Obras y los avisos móviles ya comprobados por el propietario con la app cerrada.

## Incluido

- Registro personal de subcontratas y proveedores, capacidad simultánea introducida por el usuario.
- Fases principales por obra, dependencias explícitas fin-inicio en días naturales, fechas actuales y pesos físicos que suman 100 %.
- Planificación original fijada por acción expresa y protegida también en PostgreSQL; nunca se sobrescribe con las fechas actuales.
- Gantt con barra original clara, barra actual y línea HOY. Fin original frente a estimado y estado adelantado/en plazo/retrasado.
- Avance físico real a partir de mediciones fechadas y pesos; sin mediciones se muestra desconocido. La curva prevista usa interpolación dentro de cada fase ponderada, y la real mantiene la última medición registrada. No hay valores reales futuros inventados.
- Capacidad por obras distintas con las fechas actuales. Rechazo atómico en servidor y opción Habilitar igualmente con motivo y registro inmutable del conflicto.
- Obra confirmada; borradores de solicitudes preparados a partir de datos guardados, con campos faltantes visibles. Estados pendiente/solicitado/confirmado y fecha de confirmación asignada por servidor.
- Fechas actuales del Gantt sincronizadas con inicio/fin de la obra y el calendario.

## Pendiente del alcance completo

- Conexión real de ChatGPT/voz, Outlook con permiso exclusivamente de envío o alternativa WhatsApp. No se ha autorizado ni enviado ninguna comunicación externa. No hay una IA conectada en esta entrega.
- Plantilla contractual real y datos contractuales confirmados. No generar condiciones, precios ni datos de empresa inventados.
- Código/fuente de Alquileres LYMSA para integrarlo conservando su funcionamiento.
- Informes PDF, generación periódica, análisis automático por IA y detección de tareas críticas.
- Edición avanzada de varias dependencias, calendarios de trabajo y fechas reales de ejecución frente a estimaciones. El primer Gantt usa días naturales.

## Publicación

1. Conservar respaldo del main funcional.
2. Probar planning-schema.sql en el proyecto real, dentro de su transacción aditiva. No ejecutar otra vez las migraciones anteriores.
3. Verificar navegador autenticado, representación visual y guardado con datos de prueba identificados; las pruebas de CPU/PostgreSQL embebido no sustituyen esta comprobación.
4. Publicar solamente después de esa verificación.

## Pruebas

node test-planning.cjs
NODE_PATH=<dependencias> node test-planning-database.cjs

Las pruebas verifican dependencias, cuatro días inclusivos de solapamiento, varias fases en una misma obra sin ocupar slots adicionales, aislamiento entre usuarios, rechazo de conflictos, auditoría de excepciones, original inmutable y ediciones obsoletas.
