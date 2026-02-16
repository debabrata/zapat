#!/usr/bin/env node
// tests/check-docs.mjs
// Validates that documentation files exist and contain expected sections.
// Run: node tests/check-docs.mjs

import { readFileSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const ROOT = join(__dirname, '..');

let failures = 0;
let passes = 0;

function check(name, condition, message) {
  if (condition) {
    passes++;
  } else {
    failures++;
    console.log(`  FAIL: ${name} — ${message}`);
  }
}

function readFile(relPath) {
  return readFileSync(join(ROOT, relPath), 'utf-8');
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. INTRODUCTION.md existence and structure
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n1. INTRODUCTION.md — File Existence');

check('docs/INTRODUCTION.md exists',
  existsSync(join(ROOT, 'docs/INTRODUCTION.md')),
  'docs/INTRODUCTION.md not found');

const intro = readFile('docs/INTRODUCTION.md');

// ─────────────────────────────────────────────────────────────────────────────
// 2. Required sections
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n2. INTRODUCTION.md — Required Sections');

const requiredSections = [
  'What is Zapat',
  'The Problem',
  'How It Works',
  'Key Features',
  'Getting Started',
  'Use Cases',
  'Customization',
  'Where to Go Next',
];

for (const section of requiredSections) {
  check(`has section: "${section}"`,
    intro.includes(section),
    `Section "${section}" not found in INTRODUCTION.md`);
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. Key content checks
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n3. INTRODUCTION.md — Key Content');

check('mentions Claude Code',
  intro.includes('Claude Code'),
  'Should reference Claude Code');

check('includes pipeline diagram',
  intro.includes('Triage') && intro.includes('Implement') && intro.includes('Review') && intro.includes('Merge'),
  'Should include pipeline flow diagram');

check('documents the agent label',
  intro.includes('`agent`'),
  'Should document the agent label');

check('documents agent-work label',
  intro.includes('`agent-work`'),
  'Should document the agent-work label');

check('mentions auto-merge',
  intro.includes('auto-merge') || intro.includes('Auto-merge'),
  'Should explain auto-merge gate');

check('mentions risk classification',
  intro.includes('risk') || intro.includes('Risk'),
  'Should explain risk-based merge policy');

check('includes install instructions',
  intro.includes('plugin install') || intro.includes('git clone'),
  'Should include installation instructions');

// ─────────────────────────────────────────────────────────────────────────────
// 4. Cross-references to other docs
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n4. INTRODUCTION.md — Cross-references');

const linkedDocs = [
  'overview.md',
  'usage-guide.md',
  'customization.md',
];

for (const doc of linkedDocs) {
  check(`links to ${doc}`,
    intro.includes(doc),
    `Should link to ${doc}`);
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. Other required docs exist
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n5. Other Documentation Files');

const requiredDocs = [
  'docs/overview.md',
  'docs/usage-guide.md',
  'docs/customization.md',
  'README.md',
];

for (const doc of requiredDocs) {
  check(`${doc} exists`,
    existsSync(join(ROOT, doc)),
    `${doc} not found`);
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n' + '='.repeat(60));
console.log(`Results: ${passes} passed, ${failures} failed`);
console.log('='.repeat(60));

if (failures > 0) {
  process.exit(1);
}
