#!/usr/bin/env node
const fs = require('fs')
const { spawnSync } = require('child_process')
const spellchecker=__dirname
const temp='/tmp/spelling'
const spawnArguments={stdio:[process.stdin, process.stdout, process.stderr]}

function mkdir(dir) {
  fs.mkdirSync(dir, {recursive: true})
}

function run() {
  process.stdout.write("cwd: "+process.cwd()+"\n")
  process.stdout.write("spellchecker: "+spellchecker+"\n")
  process.env['spellchecker'] = spellchecker;

  mkdir(temp)

  const child=spawnSync(spellchecker+"/unknown-words.sh", process.argv.slice(1), spawnArguments)
  process.exit(child.status)
}

run()
