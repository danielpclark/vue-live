#!/usr/bin/env node
// Compiles .vue files with @vue/compiler-sfc.  Driven by lib/vue_live/compiler/node.rb.
//
// One-shot:   node compile.js <project-root>            < request JSON
// Worker:     node compile.js <project-root> --server   (one request JSON per stdin line,
//                                                        one response JSON per stdout line)
//
// Request:  { id?, source, filename, absolutePath?, scopeId, isProd, sourceMap? }
// Response: { id?, code, css, map?, scoped, dependencies, errors, tips }
//
// Style injection and the `.vue` -> `.vue.js` import rewrite happen on the Ruby side so both
// backends share them.
'use strict'

// node:module#stripTypeScriptTypes prints an ExperimentalWarning; keep stdout/stderr clean for Ruby.
process.removeAllListeners('warning')
process.on('warning', () => {})

const path = require('path')
const args = process.argv.slice(2)
const serverMode = args.includes('--server')
const root = args.find(a => !a.startsWith('--')) || process.cwd()

function resolveFrom(name, from) {
  return require(require.resolve(name, { paths: [from, root, process.cwd(), __dirname] }))
}

let sfc
let sfcDir
try {
  const entry = require.resolve('@vue/compiler-sfc', { paths: [root, process.cwd(), __dirname] })
  sfc = require(entry)
  sfcDir = path.dirname(entry)
} catch (e) {
  const err = { errors: ['@vue/compiler-sfc is not installed in ' + root + ' (run `vue-live node-setup`)'] }
  process.stdout.write(JSON.stringify(err) + '\n')
  process.exit(1)
}

// source-map-js is a dependency of @vue/compiler-sfc; use it to merge the script and template maps.
let sourceMapJs = null
try { sourceMapJs = resolveFrom('source-map-js', sfcDir) } catch (e) { /* source maps unavailable */ }

if (serverMode) {
  serve()
} else {
  let input = ''
  process.stdin.setEncoding('utf8')
  process.stdin.on('data', chunk => { input += chunk })
  process.stdin.on('end', () => {
    handle(JSON.parse(input)).then(
      result => { process.stdout.write(JSON.stringify(result) + '\n'); process.exit(0) },
      err => { process.stdout.write(JSON.stringify({ errors: [String(err && err.stack || err)] }) + '\n'); process.exit(1) }
    )
  })
}

// Long-lived worker: requests are processed strictly in order so Ruby can pair responses by id.
function serve() {
  const readline = require('readline')
  const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity })
  let queue = Promise.resolve()
  rl.on('line', line => {
    if (!line.trim()) return
    queue = queue.then(async () => {
      let request = {}
      let response
      try {
        request = JSON.parse(line)
        response = await handle(request)
      } catch (err) {
        response = { errors: [String(err && err.stack || err)] }
      }
      response.id = request.id
      process.stdout.write(JSON.stringify(response) + '\n')
    })
  })
  rl.on('close', () => process.exit(0))
  process.stdin.on('end', () => process.exit(0))
}

async function handle(opts) {
  try {
    return await compile(opts)
  } catch (err) {
    return { errors: [formatError(err)] }
  }
}

async function compile(opts) {
  const { source, filename, scopeId, isProd } = opts
  const wantMap = !!opts.sourceMap && !!sourceMapJs
  const absolutePath = opts.absolutePath || path.join(root, filename)
  const id = scopeId.replace(/^data-v-/, '')
  const tips = []
  const dependencies = []

  const { descriptor, errors: parseErrors } = sfc.parse(source, { filename: absolutePath, sourceMap: wantMap })
  if (parseErrors.length) return { errors: parseErrors.map(formatError) }

  const hasScoped = descriptor.styles.some(s => s.scoped)
  const hasSetup = !!descriptor.scriptSetup
  const inlineTemplate = isProd && hasSetup
  const parts = [] // { code, map? } concatenated with "\n"
  let bindings

  const templateOptions = {
    filename: absolutePath,
    id,
    scoped: hasScoped,
    slotted: descriptor.slotted,
    isProd,
    preprocessLang: descriptor.template && descriptor.template.lang,
    compilerOptions: { mode: 'module' }
  }

  if (descriptor.script || descriptor.scriptSetup) {
    const script = sfc.compileScript(descriptor, {
      id,
      isProd,
      inlineTemplate,
      genDefaultAs: '__sfc__',
      templateOptions,
      sourceMap: wantMap
    })
    let code = script.content
    let map = script.map
    bindings = script.bindings
    // Older compiler-sfc versions ignore genDefaultAs; normalise either way.
    if (/^\s*export\s+default\b/m.test(code) && !/\bconst __sfc__\b/.test(code)) {
      code = sfc.rewriteDefault(code, '__sfc__')
    }
    if (script.warnings) script.warnings.forEach(w => tips.push(String(w)))
    const lang = (descriptor.scriptSetup && descriptor.scriptSetup.lang) || (descriptor.script && descriptor.script.lang)
    if (lang && /^tsx?$/.test(lang)) {
      const stripped = stripTypes(code, absolutePath, lang)
      code = stripped.code
      if (!stripped.preservesLines) map = null
    }
    parts.push({ code, map })
  } else {
    parts.push({ code: 'const __sfc__ = {}' })
  }

  if (descriptor.template && !inlineTemplate) {
    const tpl = sfc.compileTemplate(Object.assign({}, templateOptions, {
      source: descriptor.template.content,
      inMap: wantMap ? descriptor.template.map : undefined,
      compilerOptions: { mode: 'module', bindingMetadata: bindings, sourceMap: wantMap }
    }))
    if (tpl.errors && tpl.errors.length) return { errors: tpl.errors.map(formatError) }
    if (tpl.tips) tpl.tips.forEach(t => tips.push(String(t)))
    const code = tpl.code.replace(/\nexport\s+(function|const)\s+render\b/, '\n$1 render') + '\n__sfc__.render = render'
    parts.push({ code, map: tpl.map })
  }

  const cssParts = []
  const cssModules = {}
  for (const style of descriptor.styles) {
    const result = await sfc.compileStyleAsync({
      source: style.content,
      filename: absolutePath,
      id: scopeId,
      scoped: !!style.scoped,
      modules: !!style.module,
      preprocessLang: style.lang,
      isProd
    })
    if (result.errors && result.errors.length) return { errors: result.errors.map(formatError) }
    cssParts.push(result.code)
    if (style.module) {
      const name = typeof style.module === 'string' ? style.module : '$style'
      cssModules[name] = result.modules || {}
    }
    if (result.dependencies) for (const d of result.dependencies) dependencies.push(d)
  }

  let tail = ''
  if (hasScoped) tail += `\n__sfc__.__scopeId = ${JSON.stringify(scopeId)}`
  if (Object.keys(cssModules).length) tail += `\n__sfc__.__cssModules = ${JSON.stringify(cssModules)}`
  if (!isProd) tail += `\n__sfc__.__file = ${JSON.stringify(filename)}`
  tail += '\nexport default __sfc__\n'
  parts.push({ code: tail.replace(/^\n/, '') })

  const code = parts.map(p => p.code).join('\n')
  const map = wantMap ? mergeMaps(parts, filename, source) : undefined
  return { code, css: cssParts.join('\n'), map, scoped: hasScoped, dependencies, errors: [], tips }
}

// Concatenate the per-block source maps, shifting generated lines by each block's offset.  All
// blocks map back to the single .vue file.
function mergeMaps(parts, filename, source) {
  const generator = new sourceMapJs.SourceMapGenerator({ file: filename + '.js' })
  let lineOffset = 0
  for (const part of parts) {
    if (part.map) {
      try {
        const consumer = new sourceMapJs.SourceMapConsumer(typeof part.map === 'string' ? JSON.parse(part.map) : part.map)
        consumer.eachMapping(m => {
          if (m.originalLine == null) return
          generator.addMapping({
            generated: { line: m.generatedLine + lineOffset, column: m.generatedColumn },
            original: { line: m.originalLine, column: m.originalColumn || 0 },
            source: filename,
            name: m.name || undefined
          })
        })
      } catch (e) { /* a block without a usable map is simply unmapped */ }
    }
    lineOffset += part.code.split('\n').length
  }
  generator.setSourceContent(filename, source)
  return generator.toJSON()
}

// @vue/compiler-sfc leaves TypeScript syntax in place (bundlers strip it later), so do it here with
// whichever transpiler the project has.  Returns { code, preservesLines }; a transpiler that keeps
// line numbers lets the script source map stay valid.
function stripTypes(code, filename, lang) {
  const resolve = name => require(require.resolve(name, { paths: [root, process.cwd()] }))
  const attempts = {
    // Node.js >= 22.13 ships a type stripper (swc via amaro): no install needed.  'strip' mode
    // replaces types with whitespace and keeps every line in place.
    node: () => {
      const strip = require('node:module').stripTypeScriptTypes
      if (typeof strip !== 'function') throw notFound('node:module#stripTypeScriptTypes (Node.js >= 22.13)')
      try { return { code: strip(code, { mode: 'strip' }), preservesLines: true } } catch (e) {
        return { code: strip(code, { mode: 'transform' }), preservesLines: false }
      }
    },
    sucrase: () => ({ code: resolve('sucrase').transform(code, { transforms: lang === 'tsx' ? ['typescript', 'jsx'] : ['typescript'], filePath: filename }).code, preservesLines: true }),
    esbuild: () => ({ code: resolve('esbuild').transformSync(code, { loader: lang, format: 'esm', target: 'es2020', sourcefile: filename }).code, preservesLines: false }),
    typescript: () => {
      const ts = resolve('typescript')
      // TypeScript 7 (the native port) exposes no transpile API from JavaScript.
      if (typeof ts.transpileModule !== 'function') throw notFound('typescript#transpileModule (TypeScript < 7)')
      const jsx = lang === 'tsx' ? ts.JsxEmit.Preserve : undefined
      return {
        code: ts.transpileModule(code, {
          fileName: filename,
          compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2020, jsx, verbatimModuleSyntax: true }
        }).outputText,
        preservesLines: false
      }
    },
    babel: () => {
      const babel = resolve('@babel/core')
      let plugin
      try { plugin = require.resolve('@babel/plugin-transform-typescript', { paths: [root, process.cwd()] }) } catch (e) {
        plugin = require.resolve('@babel/preset-typescript', { paths: [root, process.cwd()] })
      }
      const isPreset = /preset-typescript/.test(plugin)
      return {
        code: babel.transformSync(code, {
          filename, babelrc: false, configFile: false, sourceType: 'module', retainLines: true,
          presets: isPreset ? [[plugin, { onlyRemoveTypeImports: true }]] : [],
          plugins: isPreset ? [] : [[plugin, { onlyRemoveTypeImports: true, isTSX: lang === 'tsx' }]]
        }).code,
        preservesLines: true
      }
    }
  }

  // VUE_LIVE_TS_TRANSPILER=node|sucrase|esbuild|typescript|babel pins one; otherwise try in order.
  const forced = process.env.VUE_LIVE_TS_TRANSPILER
  const order = forced ? [forced] : Object.keys(attempts)
  const failures = []
  for (const name of order) {
    const attempt = attempts[name]
    if (!attempt) throw new Error('unknown VUE_LIVE_TS_TRANSPILER ' + JSON.stringify(forced) + '; expected one of ' + Object.keys(attempts).join(', '))
    try { return attempt() } catch (e) { failures.push(e) }
  }
  const real = failures.find(e => e && e.code !== 'MODULE_NOT_FOUND')
  if (real) throw real
  throw new Error(
    '<script lang="ts"> needs a TypeScript transpiler and none is available (Node.js ' + process.version +
    ' has no built-in one; that needs >= 22.13). Install one in the project: `vue-live node-setup --with sucrase` ' +
    '(or esbuild, @babel/core + @babel/plugin-transform-typescript, typescript < 7); for this gem\'s own tests run `rake test:setup`.'
  )
}

function notFound(what) {
  const e = new Error(what + ' is not available')
  e.code = 'MODULE_NOT_FOUND'
  return e
}

function formatError(e) {
  if (!e) return 'unknown error'
  if (typeof e === 'string') return e
  let msg = e.message || String(e)
  if (e.loc && e.loc.start) msg += ` (line ${e.loc.start.line}, column ${e.loc.start.column})`
  return msg
}
