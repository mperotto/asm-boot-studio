import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import {extname} from 'node:path';
const PORT = Number(process.env.PORT || 3000);
const ROOT = new URL('.', import.meta.url);

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
};

async function serveStatic(req, res) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const pathname = url.pathname === '/' ? '/index.html' : url.pathname;
  const safePath = pathname.replace(/^\/+/, '');

  if (safePath.includes('..')) {
    res.writeHead(403);
    res.end('Forbidden');
    return;
  }

  const fileUrl = new URL(safePath, ROOT);
  const type = MIME[extname(safePath)] || 'application/octet-stream';
  try {
    const body = await readFile(fileUrl);
    res.writeHead(200, {'content-type': type, 'content-length': body.length});
    res.end(body);
  } catch {
    res.writeHead(404);
    res.end('Not found');
  }
}

const server = createServer(async (req, res) => {
  try {
    if (req.method === 'GET') {
      await serveStatic(req, res);
      return;
    }

    res.writeHead(405, {'allow': 'GET'});
    res.end('Method not allowed');
  } catch (error) {
    res.writeHead(500, {'content-type': 'text/plain; charset=utf-8'});
    res.end(error.message || 'Erro interno.');
  }
});

server.listen(PORT, () => {
  console.log(`ASM Boot Studio em http://localhost:${PORT}`);
});
