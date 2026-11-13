// Adds nested phase → task → subtask support without counting parent rows twice.
(function (root) {
  'use strict';
  const base = root.ElitePlanning;
  if (!base) throw new Error('Falta cargar el motor de planificación.');

  const childrenOf = rows => {
    const map = new Map(rows.map(row => [row.id, []]));
    for (const row of rows) if (row.parent_id) map.get(row.parent_id)?.push(row);
    return map;
  };
  const leavesUnder = (row, children, out = []) => {
    const childrenRows = children.get(row.id) || [];
    if (!childrenRows.length) out.push(row);
    else childrenRows.forEach(child => leavesUnder(child, children, out));
    return out;
  };

  function derive(rows) {
    const copy = structuredClone(rows);
    const children = childrenOf(copy);
    for (let level = 3; level >= 1; level--) {
      for (const row of copy.filter(item => Number(item.level || 1) === level)) {
        const nested = children.get(row.id) || [];
        if (!nested.length) continue;
        row.is_group = true;
        row.weight = 0;
        row.milestone = false;
        row.task_id = null;
        row.contractor_id = null;
        row.observations = [];
        row.economic_observations = [];
        row.budget = null;
        row.actual_start = null;
        row.actual_end = null;
        row.activity_status = 'pending';
        row.request_status = 'pending';
        row.contractor_confirmed_at = null;
        row.scope = '';
        row.contact_days = null;
        row.start = nested.reduce((min, child) => child.start < min ? child.start : min, nested[0].start);
        row.end = nested.reduce((max, child) => child.end > max ? child.end : max, nested[0].end);
      }
    }
    return copy;
  }

  function validate(rows) {
    if (!Array.isArray(rows) || rows.length > 100) throw new Error('Máximo 100 actividades.');
    const byId = new Map(rows.map(row => [row.id, row]));
    if (byId.size !== rows.length) throw new Error('Identificador repetido.');
    const children = childrenOf(rows);
    for (const row of rows) {
      const level = Number(row.level || 1);
      if (!Number.isInteger(level) || level < 1 || level > 3) throw new Error('El nivel debe ser fase, tarea o subtarea.');
      const parent = row.parent_id ? byId.get(row.parent_id) : null;
      if (row.parent_id && (!parent || Number(parent.level || 1) !== level - 1)) throw new Error('El elemento debe vincularse a una fase o tarea del nivel anterior.');
      const nested = children.get(row.id) || [];
      if (nested.length) {
        if (!row.is_group || Number(row.weight) !== 0 || row.milestone || row.task_id || (row.observations || []).length || row.depends_on?.length) {
          throw new Error('Una fase o tarea contenedora no lleva peso, medición, vínculo Gantt ni dependencia propia.');
        }
        const start = nested.reduce((min, child) => child.start < min ? child.start : min, nested[0].start);
        const end = nested.reduce((max, child) => child.end > max ? child.end : max, nested[0].end);
        if (row.start !== start || row.end !== end) throw new Error('Las fechas de una fase contenedora se calculan con sus elementos incluidos.');
      } else if (row.is_group) {
        throw new Error('Añade una tarea o subtarea a la fase contenedora antes de guardarla.');
      }
    }
    const leaves = rows.filter(row => !(children.get(row.id) || []).length);
    base.validate(leaves);
    for (const row of rows) {
      if ((children.get(row.id) || []).length && row.parent_id && !byId.has(row.parent_id)) throw new Error('Fase superior inexistente.');
    }
    return rows;
  }

  function observation(row, on) {
    return (row.observations || []).filter(item => item.date <= on).sort((a, b) => a.date.localeCompare(b.date)).at(-1)?.percent ?? 0;
  }
  function progress(rows, on, planned = false, onlyId = null) {
    base.day(on);
    const children = childrenOf(rows);
    const selected = onlyId ? rows.find(row => row.id === onlyId) : null;
    if (onlyId && !selected) return null;
    let leaves = selected ? leavesUnder(selected, children) : rows.filter(row => !(children.get(row.id) || []).length);
    if (!leaves.length) return null;
    if (!planned && !leaves.some(row => (row.observations || []).some(item => item.date <= on))) return null;
    const totalWeight = leaves.reduce((sum, row) => sum + Number(row.weight || 0), 0);
    if (totalWeight <= 0) return null;
    return leaves.reduce((sum, row) => {
      const value = planned
        ? Math.max(0, Math.min(1, (base.day(on) - base.day(row.start) + 1) / (base.day(row.end) - base.day(row.start) + 1))) * 100
        : observation(row, on);
      return sum + Number(row.weight || 0) * value / totalWeight;
    }, 0);
  }
  function summary(plan, today) {
    const current = plan.phases || [], baseline = plan.baseline || [];
    validate(current);
    if (baseline.length) validate(baseline);
    const originalEnd = baseline.length ? baseline.reduce((max, row) => row.end > max ? row.end : max, '') : null;
    const currentEnd = current.length ? current.reduce((max, row) => row.end > max ? row.end : max, '') : null;
    const delta = originalEnd && currentEnd ? base.day(currentEnd) - base.day(originalEnd) : null;
    const planned = baseline.length ? progress(baseline, today, true) : null;
    const actual = current.length ? progress(current, today) : null;
    return { originalEnd, currentEnd, delta, planned, actual, deviation: planned === null || actual === null ? null : actual - planned,
      status: delta === null ? 'Sin planificación original' : delta > 0 ? delta + ' días de retraso' : delta < 0 ? -delta + ' días adelantada' : 'En plazo' };
  }
  function curve(plan, today) {
    const baseline = plan.baseline || [], phases = plan.phases || [];
    if (!phases.length) return [];
    const dates = [...baseline, ...phases].flatMap(row => [base.day(row.start), base.day(row.end)]);
    const first = Math.min(...dates);
    const days = new Set([base.date(first - 1), today, ...baseline.flatMap(row => [base.date(base.day(row.start) - 1), row.end]), ...phases.flatMap(row => (row.observations || []).filter(item => item.date <= today).map(item => item.date))]);
    return [...days].sort().map(date => ({ date, planned: baseline.length ? progress(baseline, date, true) : null, actual: date <= today ? progress(phases, date) : null }));
  }
  function propagate(rows) {
    validate(rows);
    const children = childrenOf(rows);
    const leaves = rows.filter(row => !(children.get(row.id) || []).length);
    const scheduledLeaves = base.propagate(leaves);
    const byId = new Map(scheduledLeaves.map(row => [row.id, row]));
    return derive(rows.map(row => byId.get(row.id) || row));
  }

  function requests(plan, work, contractors, today) {
    const children = childrenOf(plan.phases || []);
    const leaves = (plan.phases || []).filter(row => !(children.get(row.id) || []).length);
    return base.requests({ ...plan, phases: leaves }, work, contractors, today);
  }

  root.ElitePlanning = { ...base, derive, validate, progress, summary, curve, propagate, requests, leavesUnder };
})(typeof window === 'undefined' ? globalThis : window);
