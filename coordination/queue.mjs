import { mkdir, readFile, writeFile, rename, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { resolve, sep } from 'node:path';

const ROOT = process.env.COORDINATION_STATE_DIR ? resolve(process.env.COORDINATION_STATE_DIR) + sep : fileURLToPath(new URL('./state/', import.meta.url));
const FILE = ROOT + 'queue.json';
const LOCK = ROOT + 'mutation.lock';
export async function transaction(fn) {
  await mkdir(ROOT, { recursive: true });
  let acquired = false;
  for (let i = 0; i < 40; i++) {
    try { await mkdir(LOCK); acquired = true; break; }
    catch (e) { if (e.code !== 'EEXIST') throw e; await new Promise(r => setTimeout(r, 50)); }
  }
  if (!acquired) throw new Error('Queue mutation lock busy. Do not delete it while a worker is running.');
  try {
    let queue;
    try { queue = JSON.parse(await readFile(FILE, 'utf8')); }
    catch (e) { if (e.code !== 'ENOENT') throw e; queue = { version: 1, tasks: [] }; }
    const result = await fn(queue);
    const temp = FILE + '.' + randomUUID() + '.tmp';
    await writeFile(temp, JSON.stringify(queue, null, 2));
    await rename(temp, FILE);
    return result;
  } finally { await rm(LOCK, { recursive: true }); }
}
export async function status() { return transaction(q => q); }
export async function seed(tasks) {
  return transaction(q => { for (const task of tasks) if (!q.tasks.some(t => t.id === task.id)) q.tasks.push({ ...task, state: 'queued', evidence: [], updated: new Date().toISOString() }); return q; });
}
export async function claim(id, role) {
  if (!['claude', 'codex'].includes(role)) throw new Error('Unknown worker role');
  return transaction(q => {
    const task = q.tasks.find(t => t.id === id);
    if (!task) throw new Error('Task not found');
    const expected = role === 'claude' ? 'queued' : 'awaiting_test';
    if (task.state !== expected) throw new Error(`Task must be ${expected}, is ${task.state}`);
    const blocker = q.tasks.find(t => t.id !== id && ['editing', 'awaiting_test', 'testing', 'awaiting_review', 'blocked'].includes(t.state));
    if (blocker) throw new Error(`Project held by ${blocker.id}: ${blocker.state}. No concurrent source edits/Studio tests.`);
    task.state = role === 'claude' ? 'editing' : 'testing';
    task.owner = role; task.token = randomUUID(); task.updated = new Date().toISOString();
    return { ...task };
  });
}
export async function complete(id, token, role, evidence, passed = true) {
  return transaction(q => {
    const task = q.tasks.find(t => t.id === id);
    if (!task || task.token !== token || task.owner !== role) throw new Error('Ownership token mismatch');
    if (task.state !== (role === 'claude' ? 'editing' : 'testing')) throw new Error('Invalid completion state');
    if (!evidence?.trim()) throw new Error('Evidence is required');
    task.evidence.push({ role, passed, text: evidence, at: new Date().toISOString() });
    task.state = passed ? (role === 'claude' ? 'awaiting_test' : 'awaiting_review') : 'blocked';
    delete task.token; delete task.owner;
    task.updated = new Date().toISOString(); return task;
  });
}
export async function reviewed(id, evidence) {
  return transaction(q => {
    const task = q.tasks.find(t => t.id === id);
    if (!task || task.state !== 'awaiting_review') throw new Error('Fresh passing Studio evidence required first');
    if (!evidence?.trim()) throw new Error('Review evidence required');
    task.evidence.push({ role: 'coordinator', text: evidence, at: new Date().toISOString() });
    task.state = 'done'; task.updated = new Date().toISOString(); return task;
  });
}
export async function requeue(id, evidence) {
  return transaction(q => {
    const task = q.tasks.find(t => t.id === id);
    if (!task || !['blocked', 'awaiting_review'].includes(task.state)) throw new Error('Only blocked or reviewed-stage tasks can return to source editing');
    if (!evidence?.trim()) throw new Error('Revision evidence required');
    task.evidence.push({ role: 'coordinator', text: evidence, at: new Date().toISOString() });
    task.state = 'queued'; delete task.token; delete task.owner;
    task.updated = new Date().toISOString(); return task;
  });
}
