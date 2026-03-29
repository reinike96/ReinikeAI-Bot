#!/usr/bin/env node
/**
 * X Post Character Validator
 * Validates that a post fits within X's 280 character limit
 * 
 * Usage:
 *   node validate-chars.js "Your post content here"
 *   node validate-chars.js --file path/to/post.txt
 */

const fs = require('fs');
const path = require('path');

const MAX_CHARS = 280;

function validatePost(content) {
    const charCount = content.length;
    const isValid = charCount <= MAX_CHARS;
    const remaining = MAX_CHARS - charCount;
    
    console.log('\n' + '='.repeat(50));
    console.log('X POST VALIDATION');
    console.log('='.repeat(50));
    console.log('\nPost Content:');
    console.log('-'.repeat(50));
    console.log(content);
    console.log('-'.repeat(50));
    console.log('\nValidation Results:');
    console.log(`  Characters: ${charCount} / ${MAX_CHARS}`);
    console.log(`  Remaining:  ${remaining >= 0 ? remaining : 0}`);
    console.log(`  Status:     ${isValid ? '✅ VALID' : '❌ TOO LONG'}`);
    
    if (!isValid) {
        console.log(`\n  ⚠️  Post exceeds limit by ${Math.abs(remaining)} characters`);
        console.log('  Please shorten the post before publishing.');
    }
    
    // Emoji count
    const emojiRegex = /[\p{Emoji_Presentation}\p{Extended_Pictographic}]/gu;
    const emojis = content.match(emojiRegex) || [];
    console.log(`\n  Emojis: ${emojis.length} ${emojis.length > 4 ? '⚠️  Consider reducing' : '✅'}`);
    
    // Hashtag count
    const hashtags = content.match(/#\w+/g) || [];
    console.log(`  Hashtags: ${hashtags.length} ${hashtags.length >= 2 && hashtags.length <= 4 ? '✅' : hashtags.length < 2 ? '⚠️  Add more hashtags' : '⚠️  Too many hashtags'}`);
    
    console.log('\n' + '='.repeat(50) + '\n');
    
    return isValid;
}

// Main execution
const args = process.argv.slice(2);

if (args.length === 0) {
    console.log('Usage:');
    console.log('  node validate-chars.js "Your post content"');
    console.log('  node validate-chars.js --file path/to/post.txt');
    process.exit(1);
}

let content = '';

if (args[0] === '--file') {
    const filePath = args[1];
    if (!filePath || !fs.existsSync(filePath)) {
        console.error(`Error: File not found: ${filePath}`);
        process.exit(1);
    }
    content = fs.readFileSync(filePath, 'utf8').trim();
} else {
    content = args.join(' ');
}

const isValid = validatePost(content);
process.exit(isValid ? 0 : 1);
