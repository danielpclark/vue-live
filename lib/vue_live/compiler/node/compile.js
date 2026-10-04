#!/usr/bin/env node
// Compiles one .vue file with @vue/compiler-sfc.  Driven by lib/vue_live/compiler/node.rb:
//
//   node compile.js <project-root>  < '{"source": "...", "filename": "App.vue", "scopeId": "data-v-…", "isProd": false}'
//
// Prints JSON: { code, css, scoped, dependencies, errors, tips }.  Style injection and the
// `.vue` -> `.vue.js` import rewrite are done on the Ruby side so both backends share them.
'use strict'

// node:module#stripTypeScriptTypes prints an ExperimentalWarning; keep stdout/stderr clean for Ruby.
process.removeAllListeners('warning')
process.on('warning', () => {})

const path = require('path')
const root = process.argv[2] || process.cwd()

function output(obj, exitCode = 0) {
  process.stdout.write(JSON.stringify(obj))
  process.exit(exitCode)
}

let sfc
try {
  sfc = require(require.resolve('@vue/compiler-sfc', { paths: [root, process.cwd(), __dirname] }))
} catch (e) {
  output({ errors: ['@vue/compiler-sfc is not installed in ' + root + ' (run `vue-live node-setup`)'] }, 1)
}

let input = ''
process.stdin.setEncoding('utf8')
process.stdin.on('data', chunk => { input += chunk })
process.stdin.on('end', () => {
  compile(JSON.parse(input)).then(
    result => output(result),
    err => output({ errors: [String(err && err.stack || err)] }, 1)
  )
})

async function compile(opts) {
  const { source, filename, scopeId, isProd } = opts
  const absolutePath = opts.absolutePath || path.join(root, filename)
  const id = scopeId.replace(/^data-v-/, '')
  const errors = []
  const tips = []
  const dependencies = []

  const { descriptor, errors: parseErrors } = sfc.parse(source, { filename: absolutePath, sourceMap: false })
  if (parseErrors.length) return { errors: parseErrors.map(formatError) }

  const hasScoped = descriptor.styles.some(s => s.scoped)
  const hasSetup = !!descriptor.scriptSetup
  const inlineTemplate = isProd && hasSetup
  let code = ''
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
    try {
      const script = sfc.compileScript(descriptor, {
        id,
        isProd,
        inlineTemplate,
        genDefaultAs: '__sfc__',
        templateOptions,
        sourceMap: false
      })
      code = script.content
      bindings = script.bindings
      // Older compiler-sfc versions ignore genDefaultAs; normalise either way.
      if (/^\s*export\s+default\b/m.test(code) && !/\bconst __sfc__\b/.test(code)) {
        code = sfc.rewriteDefault(code, '__sfc__')
      }
      if (script.warnings) script.warnings.forEach(w => tips.push(String(w)))
      const lang = (descriptor.scriptSetup && descriptor.scriptSetup.lang) || (descriptor.script && descriptor.script.lang)
      if (lang && /^tsx?$/.test(lang)) code = stripTypes(code, absolutePath, lang)
    } catch (e) {
      return { errors: [formatError(e)] }
    }
  } else {
    code = 'const __sfc__ = {}'
  }

  if (descriptor.template && !inlineTemplate) {
    const tpl = sfc.compileTemplate(Object.assign({}, templateOptions, {
      source: descriptor.template.content,
      compilerOptions: { mode: 'module', bindingMetadata: bindings }
    }))
    if (tpl.errors && tpl.errors.length) return { errors: tpl.errors.map(formatError) }
    if (tpl.tips) tpl.tips.forEach(t => tips.push(String(t)))
    code += '\n' + tpl.code.replace(/\nexport\s+(function|const)\s+render\b/, '\n$1 render')
    code += '\n__sfc__.render = render'
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

  if (hasScoped) code += `\n__sfc__.__scopeId = ${JSON.stringify(scopeId)}`
  if (Object.keys(cssModules).length) code += `\n__sfc__.__cssModules = ${JSON.stringify(cssModules)}`
  if (!isProd) code += `\n__sfc__.__file = ${JSON.stringify(filename)}`
  code += '\nexport default __sfc__\n'

  return { code, css: cssParts.join('\n'), scoped: hasScoped, dependencies, errors, tips }
}

// @vue/compiler-sfc leaves TypeScript syntax in place (bundlers strip it later), so do it here with
// whichever transpiler the project has: esbuild, typescript, @babel/core or sucrase.
function stripTypes(code, filename, lang) {
  const resolve = name => require(require.resolve(name, { paths: [root, process.cwd()] }))
  const attempts = [
    // Node.js >= 22.13 ships a type stripper (swc via amaro): no install needed.
    () => {
      const strip = require('node:module').stripTypeScriptTypes
      if (typeof strip !== 'function') throw notFound('node:module#stripTypeScriptTypes')
      try { return strip(code, { mode: 'transform' }) } catch (e) { return strip(code, { mode: 'strip' }) }
    },
    () => resolve('esbuild').transformSync(code, { loader: lang, format: 'esm', target: 'es2020', sourcefile: filename }).code,
    () => {
      const ts = resolve('typescript')
      // TypeScript 7 (the native port) exposes no transpile API from JavaScript.
      if (typeof ts.transpileModule !== 'function') throw notFound('typescript#transpileModule')
      const jsx = lang === 'tsx' ? ts.JsxEmit.Preserve : undefined
      return ts.transpileModule(code, {
        fileName: filename,
        compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2020, jsx, verbatimModuleSyntax: true }
      }).outputText
    },
    () => {
      const babel = resolve('@babel/core')
      let plugin
      try { plugin = require.resolve('@babel/plugin-transform-typescript', { paths: [root, process.cwd()] }) } catch (e) {
        plugin = require.resolve('@babel/preset-typescript', { paths: [root, process.cwd()] })
      }
      const isPreset = /preset-typescript/.test(plugin)
      return babel.transformSync(code, {
        filename, babelrc: false, configFile: false, sourceType: 'module',
        presets: isPreset ? [[plugin, { onlyRemoveTypeImports: true }]] : [],
        plugins: isPreset ? [] : [[plugin, { onlyRemoveTypeImports: true, isTSX: lang === 'tsx' }]]
      }).code
    },
    () => resolve('sucrase').transform(code, { transforms: lang === 'tsx' ? ['typescript', 'jsx'] : ['typescript'], filePath: filename }).code
  ]
  const failures = []
  for (const attempt of attempts) {
    try { return attempt() } catch (e) { failures.push(e) }
  }
  const real = failures.find(e => e && e.code !== 'MODULE_NOT_FOUND')
  if (real) throw real
  throw new Error('<script lang="ts"> needs a TypeScript transpiler: use Node.js >= 22.13, or install one of esbuild, @babel/core (+ @babel/plugin-transform-typescript), sucrase or typescript < 7 (e.g. `vue-live node-setup --with esbuild`)')
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
