import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { runGodotCheck } from './godot-check.mjs'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
runGodotCheck(
  process.env.GODOT_BIN || 'godot',
  ['--headless', '--path', root, '--script', 'test/audio_idle_regression.gd'],
  '[AUDIO_IDLE_PASS]',
  root,
)
