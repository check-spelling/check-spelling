#!/usr/bin/env node
const fs = require('fs')
const { spawnSync } = require('child_process')
const spellchecker=__dirname
const temp='/tmp/spelling'
const dict=spellchecker+'/words'
const jq16='https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64'
const bin=spellchecker+'/bin'
const jq_path=bin+'/jq'
const wordlist='https://github.com/check-spelling/check-spelling/raw/dictionary/dict.txt'
const spawnArguments={stdio:[process.stdin, process.stdout, process.stderr]}

function download(url, output) {
  const curl=spawnSync('curl', ['-Ls', url, '-o', output], spawnArguments)
  if (curl.status)
    console.warn('curl exited', curl.status, 'downloading', url)
}

function mkdir(dir) {
  fs.mkdirSync(dir, {recursive: true})
}

function run() {
  process.stdout.write("cwd: "+process.cwd()+"\n")
  process.stdout.write("spellchecker: "+spellchecker+"\n")
  process.env['spellchecker'] = spellchecker;

  mkdir(temp)

  if (!fs.existsSync(dict))
    download(wordlist, dict)

  mkdir(bin)
  download(jq16, jq_path)
  fs.chmodSync(jq_path, 0755)
  process.env['PATH']=bin+':'+process.env['PATH']

  const child=spawnSync(spellchecker+"/unknown-words.sh", process.argv.slice(1), spawnArguments)
  process.exit(child.status)
}

run()
