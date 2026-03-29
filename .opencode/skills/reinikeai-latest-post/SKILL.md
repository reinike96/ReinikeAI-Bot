---
name: reinikeai-latest-post
description: Get the latest blog post from www.reinikeai.com. Use when you need to retrieve the most recent article for social media posting or content sharing.
allowed-tools: WebFetch(*), Bash(curl:*), Read(*)
category: content
---

# ReinikeAI Latest Post Extractor

## When to Use

- When the user asks for the latest post from reinikeai.com
- When preparing social media content from the blog
- When you need to extract article data for sharing

## Important: Site Structure

ReinikeAI.com is a **Single Page Application (SPA)** that loads blog posts dynamically via JavaScript. This means:

- `/blog` returns 404 (not a real page)
- Posts are loaded from `./js/blog-data.js` file
- URLs use hash navigation: `#blog/post-slug`
- **RSS feed does NOT exist** (returns 404)

## Method 1: Direct blog-data.js (Recommended)

The most reliable method is to fetch the blog data file directly:

```bash
# Fetch the blog data file
curl -s "https://reinikeai.com/js/blog-data.js"
```

Or use webfetch:
```
webfetch url: https://reinikeai.com/js/blog-data.js
format: text
```

### Parsing the Response

The file is a JavaScript ES module export. The structure is:

```javascript
export const blogPosts = {
  'post-slug': {
    category: 'Category Name',
    date: 'Mar 29, 2026',
    arxivId: '2603.25728',  // Only for research papers
    en: {
      title: 'Post Title',
      excerpt: 'Post excerpt...',
      content: '<html>Full content...</html>'
    },
    es: { ... },  // Spanish translation
    de: { ... },  // German translation
    audio: {
      en: 'https://reinikeai.com/audio/audio-xxx-en.mp3',
      es: 'https://reinikeai.com/audio/audio-xxx-es.mp3',
      de: 'https://reinikeai.com/audio/audio-xxx-de.mp3'
    }
  },
  // More posts...
}
```

### Extracting the Latest Post

1. **The first post in the object is the latest** (posts are ordered by date, newest first)
2. Extract the first key (post ID/slug)
3. Get the title, excerpt, and URL

**URL Format**: `https://reinikeai.com/#blog/{post-slug}`

## Method 2: Sitemap.xml (Fallback)

If blog-data.js is unavailable, use the sitemap:

```bash
curl -s "https://reinikeai.com/sitemap.xml"
```

Look for entries with `#blog/` in the URL. The first blog entry is the latest.

## Complete Workflow

### Step 1: Fetch blog data
```
webfetch url: https://reinikeai.com/js/blog-data.js
format: text
```

### Step 2: Parse the response
- Find the first post ID (the key after `export const blogPosts = {`)
- Extract: title, excerpt, date, category
- Build the URL: `https://reinikeai.com/#blog/{post-id}`

### Step 3: Return structured data
```
Latest Post Found:
- Title: [title in requested language]
- Excerpt: [excerpt]
- Date: [date]
- Category: [category]
- URL: https://reinikeai.com/#blog/[post-id]
- Audio: [audio URL if available]
```

## Language Support

The blog supports 3 languages:
- `en` - English (default)
- `es` - Spanish
- `de` - German

Always check if the requested language is available. Fall back to English if not.

## Example Output

```
Latest ReinikeAI Post:

Title: PixelSmile: Achieving Precision and Realism in AI-Powered Facial Expression Editing
Excerpt: Researchers have developed PixelSmile, a breakthrough diffusion framework...
Date: Mar 29, 2026
Category: Research Paper
URL: https://reinikeai.com/#blog/paper-2603-25728
Audio: https://reinikeai.com/audio/audio-2603-25728-en.mp3
```

## Common Pitfalls

| Don't | Do |
|-------|-----|
| Try to fetch `/blog` page | Fetch `blog-data.js` directly |
| Look for RSS feed | Use blog-data.js or sitemap.xml |
| Assume HTML parsing works | Parse JavaScript object |
| Ignore language parameter | Return content in requested language |

## Quick Reference

| Resource | URL | Purpose |
|----------|-----|---------|
| Blog Data | `https://reinikeai.com/js/blog-data.js` | All posts with full content |
| Sitemap | `https://reinikeai.com/sitemap.xml` | Post URLs and dates |
| Main Site | `https://reinikeai.com` | Homepage (SPA) |
