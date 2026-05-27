let moduleFactoryPromise;
let jobCounter = 0;

function loadNasmFactory() {
  if (!moduleFactoryPromise) {
    importScripts('./vendor/nasm-wasm/nasm.js');
    moduleFactoryPromise = Promise.resolve().then(() => {
      const factory = globalThis.NasmModule;
      if (!factory) throw new Error('Modulo NASM WASM indisponivel.');
      return factory;
    });
  }
  return moduleFactoryPromise;
}

function collectText(lines) {
  return lines.join('\n').trim();
}

self.onmessage = async event => {
  const {id, source} = event.data;

  try {
    const factory = await loadNasmFactory();
    const stdout = [];
    const stderr = [];
    const module = await factory({
      noInitialRun: true,
      locateFile: path => `./vendor/nasm-wasm/${path}`,
      print: (...args) => stdout.push(args.join(' ')),
      printErr: (...args) => stderr.push(args.join(' ')),
    });
    const inputPath = `/job-${++jobCounter}.asm`;
    const outputPath = `/job-${jobCounter}.bin`;

    module.FS.writeFile(inputPath, source);

    try {
      module.callMain(['-f', 'bin', inputPath, '-o', outputPath]);
    } catch {}

    if (!module.FS.analyzePath(outputPath).exists) {
      throw new Error(collectText(stderr) || collectText(stdout) || 'NASM nao gerou saida.');
    }

    const bytes = module.FS.readFile(outputPath);
    module.FS.unlink(inputPath);
    module.FS.unlink(outputPath);

    self.postMessage({
      id,
      ok: true,
      bytes,
      stdout: collectText(stdout),
      stderr: collectText(stderr),
    });
  } catch (error) {
    self.postMessage({
      id,
      ok: false,
      error: error?.message || String(error),
    });
  }
};
