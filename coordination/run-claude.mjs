import { spawn } from 'node:child_process';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { claim, complete } from './queue.mjs';

const id = process.argv[2];
if (!id) throw new Error('Usage: node coordination/run-claude.mjs TASK_ID');
const repo = 'C:\\Users\\super\\OneDrive\\Documents\\Car Game';
const cli = 'C:\\Users\\super\\.vscode\\extensions\\anthropic.claude-code-2.1.296-win32-x64\\resources\\native-binary\\claude.exe';
const task = await claim(id, 'claude');
const evidenceDir = fileURLToPath(new URL(`./state/${id}/`, import.meta.url));
await mkdir(evidenceDir, { recursive: true });
try {
  const hashes = {};
  for (const path of task.sourceFiles) {
    let data;
    try { data = await readFile(repo + '\\' + path); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    if (data !== undefined) await writeFile(evidenceDir + path.split('/').pop() + '.before', data);
    hashes[path] = data === undefined ? null : createHash('sha256').update(data).digest('hex');
  }
  const prompt = `User-authorized source-edit handoff ${id}. You are Claude Code, exclusive source editor; Codex will perform Studio tests afterward. Read project instructions before editing. Scope: ${task.scope}\nPrior test/revision evidence: ${JSON.stringify(task.evidence)}\nAllowed source files: ${task.sourceFiles.join(', ')}. Backups already exist. Do not run Studio, shell commands, install software, commit, publish, modify reports, or dispatch other agents. No need to call Gemini: coordinator already obtained its plan. Finish with concrete changes and risks. Do not claim runtime tests. If unavailable or blocked, state that clearly.`;
  const child = spawn(cli, ['-p', '--output-format', 'json', '--permission-mode', 'acceptEdits', '--tools', 'Read,Edit,Write,Glob,Grep', '--allowedTools', 'Read,Edit,Write,Glob,Grep', '--strict-mcp-config', '--mcp-config', '{"mcpServers":{}}', '--max-turns', '20', prompt], { cwd: repo, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
  let output = '', errors = '';
  child.stdout.on('data', b => { output += b; }); child.stderr.on('data', b => { errors += b; });
  const code = await new Promise((resolve, reject) => { child.on('error', reject); child.on('close', resolve); });
  await writeFile(evidenceDir + 'claude-output.json', output);
  await writeFile(evidenceDir + 'claude-stderr.txt', errors);
  if (code !== 0) throw new Error(`Claude exited ${code}; inspect saved logs`);
  let result; try { result = JSON.parse(output); } catch { throw new Error('Claude did not return valid JSON'); }
  if (result.is_error) throw new Error('Claude reported a failed task; inspect saved output');
  const after = {};
  for (const path of task.sourceFiles) after[path] = createHash('sha256').update(await readFile(repo + '\\' + path)).digest('hex');
  if (!result.result?.trim()) throw new Error('Claude returned no reviewable handoff summary');
  const evidence = JSON.stringify({ summary: result.result, changed: task.sourceFiles.some(path => hashes[path] !== after[path]), before: hashes, after, backupDir: evidenceDir });
  await complete(id, task.token, 'claude', evidence, true);
  console.log(JSON.stringify({ id, state: 'awaiting_test', evidenceDir, summary: result.result }));
} catch (error) {
  await complete(id, task.token, 'claude', error.message, false);
  console.error(error.message); process.exitCode = 1;
}
