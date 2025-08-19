import { execSync } from 'child_process';
import fs from 'fs'

async function main() {
  const publishResult = JSON.parse(
    execSync('sui client publish --json').toString()
  );

  const packageId = publishResult.effects.created.find(
    (o: any) => o.owner === 'Immutable'
  ).reference.objectId;
  const effects = publishResult.effects
  if (!effects.created) {
    throw new Error('No created objects in publish result')
  }

  // Save publish result to deployments folder
  const timestamp = new Date().toISOString()
  const path = './deployments'
  if (!fs.existsSync(path)) {
    fs.mkdirSync(path)
  }
  fs.writeFileSync(`${path}/${timestamp}.json`, JSON.stringify(publishResult, null, 2), { flag: 'w' })

  console.log('Deployed packageId:', packageId);
}

main().catch(console.error);