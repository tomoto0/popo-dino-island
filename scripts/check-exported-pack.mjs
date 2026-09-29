import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { basename, dirname, isAbsolute, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { runGodotCheck } from './godot-check.mjs'

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const managedVerifier = process.env.GAME_RUNTIME
  ? resolve(process.env.GAME_RUNTIME, 'scripts/verify-game.mjs')
  : resolve(projectRoot, '.manus-game-tools/scripts/verify-game.mjs')
const packArgument = process.argv.slice(2).find(argument => argument !== '--release-profile')
const managedPack = !packArgument && (process.env.GAME_RUNTIME || existsSync(managedVerifier))
  ? (await import(pathToFileURL(managedVerifier).href)).verifiedPack(projectRoot) : null
const packPath = packArgument ? resolve(projectRoot, packArgument)
  : managedPack?.path ?? resolve(projectRoot, 'dist/index.pck')
// The installed verifier validates this standalone receipt before returning its
// path. Raw/preview exports keep their developer gates; explicit release packs
// can request the stripped profile with --release-profile.
const releaseProfile = process.argv.includes('--release-profile') ||
  Boolean(managedPack && resolve(packPath) === resolve(projectRoot, 'dist/standalone/index.pck'))
const godot = process.env.GODOT_BIN || 'godot'

if (!existsSync(packPath)) {
  throw new Error(`exported pack not found: ${packPath}`)
}

const preset = readFileSync(resolve(projectRoot, 'export_presets.cfg'), 'utf8')
const filterMatch = preset.match(/^exclude_filter="([^"]*)"$/m)
if (!filterMatch) throw new Error('Web export exclude_filter not found')
const excludePatterns = filterMatch[1]
  .split(',')
  .map((pattern) => pattern.trim())
  .filter(Boolean)
const directoryPattern = /^([^*?]+)\/\*$/
const excludedDirectories = excludePatterns.map((pattern) => pattern.match(directoryPattern)?.[1]).filter(Boolean)
const unsupportedPatterns = excludePatterns.filter((pattern) => !directoryPattern.test(pattern))
if (excludedDirectories.length === 0) throw new Error('Web export has no directory exclusions')
if (unsupportedPatterns.length > 0) {
  console.warn(`[PCK_CONTENTS_WARN] patterns not verified: ${unsupportedPatterns.join(', ')}`)
}

const runDirectory = mkdtempSync(join(tmpdir(), 'game-pck-check-'))
const contentsProbe = resolve(runDirectory, 'exported_pack_contents.gd')
const requiredDirectoryLines = ['scenes', 'scripts']
  .map((directory) => `\t${JSON.stringify(`res://${directory}`)},`)
  .join('\n')
const directoryLines = excludedDirectories.map((directory) => `\t${JSON.stringify(`res://${directory}`)},`).join('\n')
writeFileSync(
  contentsProbe,
  `extends SceneTree\n\nconst REQUIRED_DIRECTORIES := [\n${requiredDirectoryLines}\n]\nconst EXCLUDED_DIRECTORIES := [\n${directoryLines}\n]\n\nfunc _initialize() -> void:\n\tfor directory in REQUIRED_DIRECTORIES:\n\t\tif not DirAccess.dir_exists_absolute(directory):\n\t\t\tpush_error("[PCK_CONTENTS_FAIL] pack not mounted or required directory missing: " + directory)\n\t\t\tquit(1)\n\t\t\treturn\n\tfor directory in EXCLUDED_DIRECTORIES:\n\t\tif DirAccess.dir_exists_absolute(directory):\n\t\t\tpush_error("[PCK_CONTENTS_FAIL] excluded directory present: " + directory)\n\t\t\tquit(1)\n\t\t\treturn\n\tprint("[PCK_CONTENTS_PASS] required directories present and excluded directories absent")\n\tquit(0)\n`,
)

const checks = [
  [contentsProbe, '[PCK_CONTENTS_PASS]'],
  [resolve(projectRoot, 'test/exported_pack_boot.gd'), '[PCK_BOOT_PASS]'],
  [resolve(projectRoot, 'test/audio_idle_regression.gd'), '[AUDIO_IDLE_PASS]'],
  [resolve(projectRoot, 'test/terrain_regression.gd'), '[TERRAIN_PASS]'],
  [resolve(projectRoot, 'test/finish_regression.gd'), '[FINISH_PASS]'],
  [resolve(projectRoot, 'test/player_grounding.gd'), '[PLAYER_GROUNDING_PASS]'],
  [resolve(projectRoot, 'test/yarn_combat.gd'), '[YARN_PASS]'],
  [resolve(projectRoot, 'test/yarn_bounce.gd'), '[YARN_BOUNCE_PASS]'],
  [resolve(projectRoot, 'test/stomp_regression.gd'), '[STOMP_PASS]'],
  [resolve(projectRoot, 'test/tweak_regression.gd'), '[TWEAK_PASS]'],
  [resolve(projectRoot, 'test/title_presentation.gd'), '[TITLE_PRESENTATION_PASS]'],
  [resolve(projectRoot, 'test/gameplay_contract.gd'), '[GAMEPLAY_CONTRACT_PASS]'],
  [resolve(projectRoot, 'test/vfx_regression.gd'), '[VFX_PASS]'],
  [resolve(projectRoot, 'test/audio_completion.gd'), '[AUDIO_COMPLETION_PASS]'],
]
let failed = false
try {
  for (const [index, [script, marker]] of checks.entries()) {
    const userDirectoryName = `PlatformerPckTests-${basename(runDirectory)}-${index}`
    const userDirectoryReceipt = join(runDirectory, `user-directory-${index}.txt`)
    const wrapper = join(runDirectory, `isolated-check-${index}.gd`)
    // SceneTree initialization runs before autoload _ready, so both startup
    // reads and test writes use isolated settings without modifying the PCK.
    writeFileSync(wrapper, `extends ${JSON.stringify(script)}\n\nfunc _initialize() -> void:\n\tProjectSettings.set_setting("application/config/use_custom_user_dir", true)\n\tProjectSettings.set_setting("application/config/custom_user_dir_name", ${JSON.stringify(userDirectoryName)})\n\tvar directory := OS.get_user_data_dir()\n\tDirAccess.make_dir_recursive_absolute(directory)\n\tvar receipt := FileAccess.open(${JSON.stringify(userDirectoryReceipt)}, FileAccess.WRITE)\n\treceipt.store_string(directory)\n\treceipt.close()\n\tsuper._initialize()\n`)
    try {
      runGodotCheck(godot, ['--headless', '--log-file', join(runDirectory, `check-${index}.log`), '--main-pack', packPath, '--script', wrapper, ...(releaseProfile ? ['--', '--release-profile'] : [])], marker, runDirectory)
    } catch (error) {
      if (error?.code === 'ENOENT') {
        console.error(`[PCK_CHECK_FAIL] Godot binary not found: ${godot}; set GODOT_BIN to override`)
      } else {
        console.error(`[PCK_CHECK_FAIL] ${script}: ${error instanceof Error ? error.message : String(error)}`)
      }
      failed = true
      break
    } finally {
      if (existsSync(userDirectoryReceipt)) {
        const directory = readFileSync(userDirectoryReceipt, 'utf8')
        if (!isAbsolute(directory) || basename(directory) !== userDirectoryName) {
          throw new Error('Unexpected isolated user directory')
        }
        rmSync(directory, { recursive: true, force: true })
      }
    }
  }
} finally {
  rmSync(runDirectory, { recursive: true, force: true })
}

if (failed) process.exitCode = 1
