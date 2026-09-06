const fs = require('fs');
const path = require('path');

const ROOT_DIR = path.resolve(__dirname, '..');
const SKILLS_DIR = path.join(ROOT_DIR, 'skills');

console.log('🔍 Starting Skills Suite Validation...\n');

let totalErrors = 0;
let totalChecked = 0;

if (!fs.existsSync(SKILLS_DIR)) {
  console.error('❌ Error: skills directory not found at', SKILLS_DIR);
  process.exit(1);
}

const skillFolders = fs.readdirSync(SKILLS_DIR).filter((file) => {
  return fs.statSync(path.join(SKILLS_DIR, file)).isDirectory();
});

console.log(`📦 Found ${skillFolders.length} skills in repository.\n`);

skillFolders.forEach((skillName) => {
  totalChecked++;
  const skillPath = path.join(SKILLS_DIR, skillName);
  const skillFile = path.join(skillPath, 'SKILL.md');

  console.log(`👉 Validating skill: [${skillName}]`);

  if (!fs.existsSync(skillFile)) {
    console.error(`   ❌ Missing SKILL.md in ${skillPath}`);
    totalErrors++;
    return;
  }

  const content = fs.readFileSync(skillFile, 'utf8');

  // Validate YAML Frontmatter
  const frontmatterMatch = content.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!frontmatterMatch) {
    console.error(`   ❌ Missing or malformed YAML frontmatter in ${skillName}/SKILL.md`);
    totalErrors++;
    return;
  }

  const yamlBlock = frontmatterMatch[1];
  const nameMatch = yamlBlock.match(/^name:\s*([^\r\n]+)/m);
  const descMatch = yamlBlock.match(/^description:\s*([^\r\n]+)/m);

  if (!nameMatch || !nameMatch[1].trim()) {
    console.error(`   ❌ Missing 'name' field in frontmatter of ${skillName}`);
    totalErrors++;
  } else if (nameMatch[1].trim() !== skillName) {
    console.error(`   ❌ Frontmatter name '${nameMatch[1].trim()}' does not match directory name '${skillName}'`);
    totalErrors++;
  }

  if (!descMatch || !descMatch[1].trim()) {
    console.error(`   ❌ Missing 'description' field in frontmatter of ${skillName}`);
    totalErrors++;
  }

  // Validate positional-argument placeholders.
  //
  // El runner de skills sustituye $0, $1, ... por los argumentos con que se invoca la skill.
  // Un `$0` escrito literalmente en SKILL.md (por ejemplo explicando `dirname "$0"` de un
  // script) desaparece del texto que ve el modelo y queda reemplazado por el argumento —
  // silenciosamente, y solo cuando alguien invoca la skill con argumentos. En las referencias
  // no pasa: esas se leen como archivos.
  //
  // `$@` y `$*` no se sustituyen: se pueden usar sin problema.
  const positionalMatches = [...content.matchAll(/\$\{?([0-9])\}?/g)];
  if (positionalMatches.length > 0) {
    const found = [...new Set(positionalMatches.map((m) => `$${m[1]}`))].join(', ');
    console.error(
      `   ❌ ${skillName}/SKILL.md contiene placeholders posicionales (${found}). ` +
        `El runner los reemplaza por los argumentos de invocacion. ` +
        `Reformular en prosa, o mover el ejemplo a un archivo de references/.`,
    );
    totalErrors++;
  }

  // Validate relative markdown links
  const linkMatches = [...content.matchAll(/\[([^\]]+)\]\(((\.\.?\/[^)]+))\)/g)];
  for (const match of linkMatches) {
    const rawLink = match[2].split('#')[0]; // strip anchor
    if (rawLink) {
      const resolvedTarget = path.resolve(skillPath, rawLink);
      if (!fs.existsSync(resolvedTarget)) {
        console.error(`   ❌ Broken relative link in ${skillName}/SKILL.md: ${match[2]} (Target not found: ${resolvedTarget})`);
        totalErrors++;
      }
    }
  }

  console.log(`   ✅ Skill [${skillName}] passed validation.`);
});

console.log('\n----------------------------------------');
if (totalErrors === 0) {
  console.log(`✨ All ${totalChecked} skills validated successfully with ZERO errors! 🎉\n`);
  process.exit(0);
} else {
  console.error(`🚨 Validation failed with ${totalErrors} error(s).\n`);
  process.exit(1);
}
