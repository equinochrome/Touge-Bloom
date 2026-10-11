import { McpServer } from 'file:///C:/Users/super/OneDrive/Documents/ChatGPT/RBLX%20Pt%202/roblox-mcp/node_modules/@modelcontextprotocol/sdk/dist/esm/server/mcp.js';
import { StdioServerTransport } from 'file:///C:/Users/super/OneDrive/Documents/ChatGPT/RBLX%20Pt%202/roblox-mcp/node_modules/@modelcontextprotocol/sdk/dist/esm/server/stdio.js';
import { createRequire } from 'node:module';
import { status, seed, claim, complete, reviewed, requeue } from './queue.mjs';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { open, mkdir } from 'node:fs/promises';
const require = createRequire(new URL('file:///C:/Users/super/OneDrive/Documents/ChatGPT/RBLX%20Pt%202/roblox-mcp/package.json', import.meta.url));
const { z } = require('zod');
const role = process.env.COORDINATION_ROLE || 'codex';
const server = new McpServer({ name: 'project-coordination', version: '1.0.0' });
const text = value => ({ content: [{ type: 'text', text: JSON.stringify(value) }] });
function tool(name, description, inputSchema, fn) { server.registerTool(name, { description, inputSchema }, async args => { try { return text(await fn(args)); } catch (e) { return { ...text({ error: e.message }), isError: true }; } }); }
tool('queue_status', 'Read the shared Claude-edit/Codex-test queue. In-flight tasks block other work.', {}, () => status());
tool('claim_task', 'Claim the next stage for this configured worker role. Receive an ownership token.', { id: z.string() }, a => claim(a.id, role));
tool('complete_stage', 'Submit evidence for your claimed stage. Failed stages block the queue for diagnosis.', { id: z.string(), token: z.string(), evidence: z.string().min(1), passed: z.boolean() }, a => complete(a.id, a.token, role, a.evidence, a.passed));
if (role === 'codex') tool('record_review', 'Coordinator records Gemini advisory review after fresh passing Studio evidence. Human instructions remain authoritative.', { id: z.string(), evidence: z.string().min(1) }, a => reviewed(a.id, a.evidence));
if (role === 'codex') {
  tool('enqueue_source', 'Create a human-authorized source task with explicit file scope. Gemini recommendations alone do not authorize work. Does not dispatch until requested.', { id: z.string().regex(/^[A-Za-z0-9_-]+$/), title: z.string().min(1), scope: z.string().min(1), sourceFiles: z.array(z.string().regex(/^src\/(server|client|shared)\/[A-Za-z0-9_./-]+\.(lua|luau)$/)).min(1) }, async a => {
    if (a.sourceFiles.some(p => p.split('/').includes('..'))) throw new Error('Source path must stay in the project');
    return seed([a]);
  });
  tool('request_revision', 'Return a failed task to Claude with specific test evidence. Does not automatically dispatch edits.', { id: z.string(), evidence: z.string().min(1) }, a => requeue(a.id, a.evidence));
  tool('dispatch_source', 'Dispatch the authorized queued task to a separate Claude Code source worker. Queue ownership prevents concurrent bridge edits. Check queue_status for the result.', { id: z.string().regex(/^[A-Za-z0-9_-]+$/) }, async a => {
    const q = await status(); const task = q.tasks.find(t => t.id === a.id);
    if (!task || task.state !== 'queued') throw new Error('Task must exist and be queued');
    if (q.tasks.some(t => ['editing', 'awaiting_test', 'testing', 'awaiting_review', 'blocked'].includes(t.state))) throw new Error('Project already held');
    const directory = fileURLToPath(new URL(`./state/${a.id}/`, import.meta.url));
    await mkdir(directory, { recursive: true });
    const log = await open(directory + 'dispatch.log', 'a');
    try {
      const child = spawn(process.execPath, [fileURLToPath(new URL('./run-claude.mjs', import.meta.url)), a.id], { windowsHide: true, detached: false, stdio: ['ignore', log.fd, log.fd] });
      await new Promise((resolve, reject) => { child.once('spawn', resolve); child.once('error', reject); });
      child.unref(); return { dispatched: a.id, pid: child.pid };
    } finally { await log.close(); }
  });
}
await server.connect(new StdioServerTransport());
