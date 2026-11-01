# Recuperación reversible

La migración añade funciones, un trigger específico para tareas vinculadas y un historial privado por propietario. No transforma ni elimina registros existentes. El endpoint elite_save_plan original se conserva intacto.

Para desactivar la sincronización nueva sin eliminar datos:

```sql
alter table public.elite_tasks disable trigger elite_gantt_task_sync;
revoke execute on function public.elite_save_gantt(uuid,jsonb,integer,boolean,boolean,text) from authenticated;
```

Restaurar la interfaz anterior solo después de revisar si se han creado hitos de peso cero: la versión anterior no los reconoce. Conservar la validación de hitos de esta versión o mantener la interfaz en consulta durante la recuperación. No borrar campos nuevos ni snapshots. Para reactivar: enable trigger y grant execute del mismo endpoint a authenticated.

Los snapshots de elite_plan_versions conservan fases, línea base, revisión y fecha anteriores. Recuperar mediante revisión y guardado de una nueva versión; nunca sobrescribir directamente la línea base ni el historial. Deshacer en interfaz crea una nueva revisión.
