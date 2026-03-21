#!/usr/bin/env node

function parseArgs(argv) {
  const result = {
    mode: 'summary',
    maxLinks: 25,
    maxHeadings: 20,
    maxAssets: 25,
  };

  for (let index = 0; index < argv.length; index++) {
    const token = argv[index];
    if (!token.startsWith('--')) {
      continue;
    }

    const key = token.slice(2);
    const next = argv[index + 1];
    if (typeof next === 'undefined' || next.startsWith('--')) {
      result[key] = true;
      continue;
    }

    result[key] = next;
    index++;
  }

  return result;
}

function decodeHtml(text) {
  if (!text) {
    return '';
  }

  return text
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/&#x27;/gi, "'")
    .replace(/&#x2F;/gi, '/')
    .replace(/\s+/g, ' ')
    .trim();
}

function stripTags(html) {
  if (!html) {
    return '';
  }
  return decodeHtml(html.replace(/<[^>]+>/g, ' '));
}

function absoluteUrl(baseUrl, candidate) {
  if (!candidate) {
    return '';
  }

  try {
    return new URL(candidate, baseUrl).toString();
  } catch {
    return String(candidate).trim();
  }
}

function firstMatchGroup(text, pattern, groupName) {
  const match = text.match(pattern);
  if (!match || !match.groups) {
    return '';
  }
  return decodeHtml(match.groups[groupName] || '');
}

function getMetaContent(html, names) {
  for (const name of names) {
    const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const patterns = [
      new RegExp(`<meta[^>]+(?:name|property)\\s*=\\s*["']${escaped}["'][^>]+content\\s*=\\s*["'](?<content>.*?)["']`, 'is'),
      new RegExp(`<meta[^>]+content\\s*=\\s*["'](?<content>.*?)["'][^>]+(?:name|property)\\s*=\\s*["']${escaped}["']`, 'is'),
    ];
    for (const pattern of patterns) {
      const value = firstMatchGroup(html, pattern, 'content');
      if (value) {
        return value;
      }
    }
  }
  return '';
}

function getLinkHrefByRel(html, baseUrl, relValues) {
  for (const relValue of relValues) {
    const escaped = relValue.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const patterns = [
      new RegExp(`<link[^>]+rel\\s*=\\s*["'][^"']*\\b${escaped}\\b[^"']*["'][^>]+href\\s*=\\s*["'](?<href>.*?)["']`, 'gis'),
      new RegExp(`<link[^>]+href\\s*=\\s*["'](?<href>.*?)["'][^>]+rel\\s*=\\s*["'][^"']*\\b${escaped}\\b[^"']*["']`, 'gis'),
    ];
    for (const pattern of patterns) {
      const href = firstMatchGroup(html, pattern, 'href');
      if (href) {
        return absoluteUrl(baseUrl, href);
      }
    }
  }
  return '';
}

function getLinkHrefsByRel(html, baseUrl, relValues, limit = 10) {
  const items = [];
  const seen = new Set();

  for (const relValue of relValues) {
    const escaped = relValue.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const patterns = [
      new RegExp(`<link[^>]+rel\\s*=\\s*["'][^"']*\\b${escaped}\\b[^"']*["'][^>]+href\\s*=\\s*["'](?<href>.*?)["']`, 'gis'),
      new RegExp(`<link[^>]+href\\s*=\\s*["'](?<href>.*?)["'][^>]+rel\\s*=\\s*["'][^"']*\\b${escaped}\\b[^"']*["']`, 'gis'),
    ];

    for (const pattern of patterns) {
      for (const match of html.matchAll(pattern)) {
        const href = absoluteUrl(baseUrl, match.groups?.href || '');
        if (!href || seen.has(href)) {
          continue;
        }
        seen.add(href);
        items.push(href);
        if (items.length >= limit) {
          return items;
        }
      }
    }
  }

  return items;
}

function getHeadings(html, limit) {
  const matches = html.matchAll(/<(?<tag>h[1-3])[^>]*>(?<text>.*?)<\/\1>/gis);
  const items = [];
  for (const match of matches) {
    const text = stripTags(match.groups?.text || '');
    if (!text) {
      continue;
    }
    items.push({
      tag: String(match.groups?.tag || '').toLowerCase(),
      text,
    });
    if (items.length >= limit) {
      break;
    }
  }
  return items;
}

function getLinks(html, baseUrl, limit) {
  const matches = html.matchAll(/<a\b(?<attrs>[^>]*)>(?<text>.*?)<\/a>/gis);
  const items = [];
  const seen = new Set();

  for (const match of matches) {
    const attrs = match.groups?.attrs || '';
    const hrefMatch = attrs.match(/\bhref\s*=\s*["'](?<href>.*?)["']/is);
    const href = hrefMatch?.groups?.href || '';
    const finalHref = absoluteUrl(baseUrl, href);
    if (!finalHref || seen.has(finalHref)) {
      continue;
    }

    const text = stripTags(match.groups?.text || '');
    if (!text && !/^https?:/i.test(finalHref)) {
      continue;
    }

    seen.add(finalHref);
    items.push({
      text,
      url: finalHref,
    });

    if (items.length >= limit) {
      break;
    }
  }

  return items;
}

function getAssets(html, baseUrl, limit) {
  const patterns = [
    /<script\b[^>]*\bsrc\s*=\s*["'](?<url>.*?)["']/gis,
    /<link\b[^>]*\bhref\s*=\s*["'](?<url>.*?)["']/gis,
    /["'`](?<url>[^"'`\s]+?\.(?:js|json|xml|rss)(?:\?[^"'`]*)?)["'`]/gis,
    /["'`](?<url>[^"'`\s]*(?:sitemap|feed|api|data)[^"'`\s]*)["'`]/gis,
  ];
  const candidates = [];
  const seen = new Set();

  for (const pattern of patterns) {
    for (const match of html.matchAll(pattern)) {
      const finalUrl = absoluteUrl(baseUrl, match.groups?.url || '');
      if (!finalUrl || seen.has(finalUrl)) {
        continue;
      }

      if (!/\.(js|json|xml|rss)(\?|$)/i.test(finalUrl) && !/sitemap|feed|api|data/i.test(finalUrl)) {
        continue;
      }

      seen.add(finalUrl);
      candidates.push(finalUrl);
    }
  }

  return candidates
    .sort((left, right) => scoreAsset(right, baseUrl) - scoreAsset(left, baseUrl))
    .slice(0, limit);
}

function scoreAsset(url, baseUrl) {
  let score = 0;
  const lowerUrl = String(url || '').toLowerCase();
  const lowerBase = String(baseUrl || '').toLowerCase();

  if (lowerUrl.startsWith(lowerBase)) {
    score += 50;
  }
  if (/blog|post|article|news|insight/i.test(lowerUrl)) {
    score += 40;
  }
  if (/data|feed|sitemap|json/i.test(lowerUrl)) {
    score += 25;
  }
  if (/\.json(\?|$)/i.test(lowerUrl)) {
    score += 20;
  }
  if (/\.js(\?|$)/i.test(lowerUrl)) {
    score += 10;
  }

  return score;
}

function uniqueLimited(items, limit) {
  const result = [];
  const seen = new Set();

  for (const item of items) {
    const value = String(item || '').trim();
    if (!value || seen.has(value)) {
      continue;
    }
    seen.add(value);
    result.push(value);
    if (result.length >= limit) {
      break;
    }
  }

  return result;
}

function extractAssetSignals(text, baseUrl) {
  const urls = [];
  for (const match of text.matchAll(/https?:\/\/[^\s"'`)<>{}\]]+/g)) {
    urls.push(match[0]);
  }
  for (const match of text.matchAll(/["'`](?<url>\.?\/[^"'`\s]+?(?:\.(?:js|json|xml|rss)|#blog\/[^"'`\s]+)[^"'`]*)["'`]/gis)) {
    urls.push(absoluteUrl(baseUrl, match.groups?.url || ''));
  }

  const ids = [];
  for (const match of text.matchAll(/["'`](?<id>[A-Za-z0-9]+(?:[-_][A-Za-z0-9]+){1,6})["'`]/g)) {
    ids.push(match.groups?.id || '');
  }

  const dates = [];
  for (const match of text.matchAll(/\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{1,2},\s+\d{4}\b/g)) {
    dates.push(match[0]);
  }
  for (const match of text.matchAll(/\b\d{4}-\d{2}-\d{2}\b/g)) {
    dates.push(match[0]);
  }

  const titles = [];
  for (const match of text.matchAll(/\btitle\s*:\s*["'`](?<title>[^"'`]{8,180})["'`]/gi)) {
    titles.push(match.groups?.title || '');
  }

  const excerpts = [];
  const lines = text.split(/\r?\n/);
  for (const line of lines) {
    if (!/(title|date|slug|id|blog|post|article)/i.test(line)) {
      continue;
    }
    const clean = line.trim();
    if (!clean || clean.length > 220) {
      continue;
    }
    excerpts.push(clean);
    if (excerpts.length >= 20) {
      break;
    }
  }

  return {
    urls: uniqueLimited(urls, 25),
    idsOrSlugs: uniqueLimited(ids, 40),
    dates: uniqueLimited(dates, 30),
    titles: uniqueLimited(titles, 20),
    matchingLines: uniqueLimited(excerpts, 20),
  };
}

function tryParseJson(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function summarizeJsonShape(value, depth = 0) {
  if (depth >= 2) {
    return Array.isArray(value) ? '[array]' : typeof value;
  }
  if (Array.isArray(value)) {
    return {
      type: 'array',
      length: value.length,
      sample: value.length > 0 ? summarizeJsonShape(value[0], depth + 1) : null,
    };
  }
  if (value && typeof value === 'object') {
    const entries = Object.entries(value).slice(0, 20);
    const shape = {};
    for (const [key, innerValue] of entries) {
      shape[key] = summarizeJsonShape(innerValue, depth + 1);
    }
    return shape;
  }
  return typeof value;
}

function isLikelyHtml(text, contentType, url) {
  if (/html/i.test(contentType || '')) {
    return true;
  }
  if (/\.html?(\?|$)/i.test(url || '')) {
    return true;
  }
  return /<html|<head|<body|<title/i.test(text.slice(0, 2000));
}

function buildAssetOutput(text, response, requestedUrl) {
  const finalUrl = response.url || requestedUrl;
  const contentType = response.headers.get('content-type') || '';
  const parsedJson = tryParseJson(text);

  return {
    mode: 'asset',
    asset: {
      requestedUrl,
      finalUrl,
      statusCode: response.status,
      contentType,
      size: text.length,
      jsonShape: parsedJson ? summarizeJsonShape(parsedJson) : null,
      ...extractAssetSignals(text, finalUrl),
    },
  };
}

function getJsonLd(html, limit = 10) {
  const matches = html.matchAll(/<script\b[^>]*type\s*=\s*["']application\/ld\+json["'][^>]*>(?<json>.*?)<\/script>/gis);
  const items = [];
  for (const match of matches) {
    const raw = (match.groups?.json || '').trim();
    if (!raw) {
      continue;
    }
    try {
      items.push(JSON.parse(raw));
    } catch {
      items.push(raw);
    }
    if (items.length >= limit) {
      break;
    }
  }
  return items;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const url = args.url;
  if (!url) {
    throw new Error('Missing --url');
  }

  const response = await fetch(url, {
    redirect: 'follow',
    headers: {
      'user-agent': 'Mozilla/5.0 ReinikeAI-Bot/1.0',
      'accept-language': 'en-US,en;q=0.9',
    },
  });

  const html = await response.text();
  if (!isLikelyHtml(html, response.headers.get('content-type') || '', url) || String(args.mode || '').toLowerCase() === 'asset') {
    process.stdout.write(`${JSON.stringify(buildAssetOutput(html, response, url), null, 2)}\n`);
    return;
  }

  const finalUrl = response.url || url;
  const title = firstMatchGroup(html, /<title[^>]*>(?<value>.*?)<\/title>/is, 'value');
  const lang = firstMatchGroup(html, /<html[^>]+\blang\s*=\s*["'](?<value>[^"']+)["']/is, 'value');

  const metadata = {
    requestedUrl: url,
    finalUrl,
    statusCode: response.status,
    title,
    description: getMetaContent(html, ['description', 'og:description', 'twitter:description']),
    canonical: getLinkHrefByRel(html, finalUrl, ['canonical']),
    ogTitle: getMetaContent(html, ['og:title', 'twitter:title']),
    lang,
    alternateLinks: getLinkHrefsByRel(html, finalUrl, ['alternate'], 10),
    rssOrFeed: getLinkHrefsByRel(html, finalUrl, ['alternate', 'feed'], 10).filter(link => /rss|feed|xml/i.test(link)),
  };

  const headings = getHeadings(html, Number(args.maxHeadings) || 20);
  const links = getLinks(html, finalUrl, Number(args.maxLinks) || 25);
  const assets = getAssets(html, finalUrl, Number(args.maxAssets) || 25);
  const jsonLd = getJsonLd(html);

  const mode = String(args.mode || 'summary').toLowerCase();
  let output;
  switch (mode) {
    case 'metadata':
      output = { mode, metadata };
      break;
    case 'headings':
      output = { mode, metadata, headings };
      break;
    case 'links':
      output = { mode, metadata, links };
      break;
    case 'assets':
      output = { mode, metadata, assets, jsonLd };
      break;
    default:
      output = { mode: 'summary', metadata, headings, links, assets, jsonLd };
      break;
  }

  process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
}

main().catch(error => {
  console.error(`[ERROR] ${error.message}`);
  process.exit(1);
});
