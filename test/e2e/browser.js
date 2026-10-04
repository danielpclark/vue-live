// Drives headless Chromium against test/e2e/server.rb and prints what it saw as JSON.
//   node test/e2e/browser.js <node-project-root-with-playwright-core> <url>
const [, , nodeRoot, url] = process.argv
const { chromium } = require(require.resolve('playwright-core', { paths: [nodeRoot, process.cwd()] }))

;(async () => {
  const launch = { args: ['--no-sandbox'] }
  if (process.env.PLAYWRIGHT_CHROMIUM) launch.executablePath = process.env.PLAYWRIGHT_CHROMIUM
  const browser = await chromium.launch(launch)
  const page = await browser.newPage()
  const errors = []
  page.on('pageerror', e => errors.push('PAGEERROR ' + e.message))
  // "Failed to load resource" console lines carry no URL, so track HTTP errors from responses instead.
  page.on('console', m => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) errors.push(m.text()) })
  page.on('response', r => { if (r.status() >= 400 && !/favicon\.ico$/.test(r.url())) errors.push(r.status() + ' ' + r.url()) })
  await page.goto(url, { waitUntil: 'networkidle' })
  await page.waitForSelector('#root h1')
  const out = {}
  out.h1 = await page.textContent('#root h1')
  out.h1Color = await page.$eval('#root h1', e => getComputedStyle(e).color)
  out.childColor = await page.$eval('#root .child', e => getComputedStyle(e).color)
  out.outsideColor = await page.$eval('#outside', e => getComputedStyle(e).color)
  out.bodyMargin = await page.$eval('body', e => getComputedStyle(e).margin)
  await page.click('#root .child'); await page.click('#root .child'); await page.click('#root .child')
  out.childText = await page.textContent('#root .child')
  out.many = await page.$eval('#root', e => !!e.querySelector('.many'))
  out.setupText = await page.textContent('#setup .setup')
  out.setupColor = await page.$eval('#setup .setup', e => getComputedStyle(e).color)
  out.errors = errors
  console.log(JSON.stringify(out))
  await browser.close()
})().catch(e => { console.error(e); process.exit(1) })
