import { createServer } from 'node:http';
import { createConnection as createTcpConnection } from 'node:net';
import { connect as createTlsConnection } from 'node:tls';
import { Readable } from 'node:stream';

import {
  BODYLESS_METHODS,
  DOMAIN_PROXY_RULES,
  HOST,
  JP_COLOS,
  MANUAL_REDIRECT_DOMAINS,
  PORT,
  REQUEST_TIMEOUT_MS,
  STATS_DAILY_WINDOW,
  STATS_FILE,
  STATS_TOTAL_WINDOW,
  TIME_ZONE,
  TRUST_PROXY_HEADERS
} from './src/config.js';
import { renderFrontendHtml } from './src/frontend.js';
import { StatsStore } from './src/stats-store.js';

const homepageHtml = renderFrontendHtml({
  statsDailyWindow: STATS_DAILY_WINDOW,
  statsTotalWindow: STATS_TOTAL_WINDOW
});

const statsStore = new StatsStore({
  filePath: STATS_FILE,
  timeZone: TIME_ZONE
});

await statsStore.ready();

const server = createServer((req, res) => {
  handleHttpRequest(req, res).catch((error) => {
    console.error('Unhandled HTTP error:', error);

    if (res.headersSent) {
      res.destroy(error);
      return;
    }

    const statusCode = error.statusCode || 502;
    sendJson(res, statusCode, {
      error: statusCode >= 500 ? '代理请求失败' : error.message,
      detail: statusCode >= 500 ? error.message : undefined
    });
  });
});

server.on('upgrade', (req, socket, head) => {
  handleWebSocketUpgrade(req, socket, head).catch((error) => {
    console.error('WebSocket proxy error:', error);
    sendUpgradeError(socket, error.statusCode || 502, error.statusCode ? error.message : 'Bad Gateway');
  });
});

server.keepAliveTimeout = 65_000;
server.headersTimeout = 66_000;

server.listen(PORT, HOST, () => {
  console.log(`Emby server proxy listening on http://${HOST}:${PORT}`);
  console.log(`Stats file: ${STATS_FILE}`);
});

async function handleHttpRequest(req, res) {
  const requestOrigin = getRequestOrigin(req);
  const requestUrl = new URL(req.url || '/', requestOrigin);

  if (req.method === 'OPTIONS') {
    sendEmpty(res, 204);
    return;
  }

  if (requestUrl.pathname === '/') {
    sendHtml(res, 200, homepageHtml);
    return;
  }

  if (requestUrl.pathname === '/favicon.ico') {
    sendEmpty(res, 204, { 'Content-Type': 'image/x-icon' });
    return;
  }

  if (requestUrl.pathname === '/health') {
    sendJson(res, 200, {
      status: 'ok',
      time: new Date().toISOString()
    });
    return;
  }

  if (requestUrl.pathname === '/stats') {
    const stats = await statsStore.getStats({
      dailyWindow: STATS_DAILY_WINDOW,
      totalWindow: STATS_TOTAL_WINDOW
    });

    sendJson(res, 200, {
      error: null,
      data: stats
    });
    return;
  }

  if (requestUrl.pathname.startsWith('/cdn-cgi/')) {
    sendText(res, 404, 'Not Found');
    return;
  }

  const upstreamUrl = parseUpstreamUrl(requestUrl);
  applyDomainProxyRule(req, upstreamUrl);
  recordStatsIfNeeded(upstreamUrl.pathname);

  await proxyHttpRequest({
    req,
    res,
    requestOrigin,
    upstreamUrl,
    redirectDepth: 0
  });
}

async function proxyHttpRequest({ req, res, requestOrigin, upstreamUrl, redirectDepth }) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  req.on('aborted', () => controller.abort());

  try {
    const requestOptions = {
      method: req.method,
      headers: buildUpstreamRequestHeaders(req, upstreamUrl),
      redirect: 'manual',
      signal: controller.signal
    };

    if (!BODYLESS_METHODS.has(req.method || 'GET')) {
      requestOptions.body = req;
      requestOptions.duplex = 'half';
    }

    const upstreamResponse = await fetch(upstreamUrl, requestOptions);

    if (isRedirectResponse(upstreamResponse)) {
      await handleRedirectResponse({
        req,
        res,
        requestOrigin,
        upstreamUrl,
        upstreamResponse,
        redirectDepth
      });
      return;
    }

    writeUpstreamResponse(res, upstreamResponse);
  } finally {
    clearTimeout(timer);
  }
}

async function handleRedirectResponse({
  req,
  res,
  requestOrigin,
  upstreamUrl,
  upstreamResponse,
  redirectDepth
}) {
  const location = upstreamResponse.headers.get('location');

  if (!location) {
    writeUpstreamResponse(res, upstreamResponse);
    return;
  }

  let redirectUrl;

  try {
    redirectUrl = new URL(location, upstreamUrl);
  } catch {
    writeUpstreamResponse(res, upstreamResponse);
    return;
  }

  if (isManualRedirect(redirectUrl.hostname)) {
    writeUpstreamResponse(res, upstreamResponse, {
      location: redirectUrl.toString()
    });
    return;
  }

  if (redirectDepth < 5 && BODYLESS_METHODS.has(req.method || 'GET')) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

    try {
      const followResponse = await fetch(redirectUrl, {
        method: req.method,
        headers: buildUpstreamRequestHeaders(req, redirectUrl),
        redirect: 'manual',
        signal: controller.signal
      });

      if (isRedirectResponse(followResponse)) {
        await handleRedirectResponse({
          req,
          res,
          requestOrigin,
          upstreamUrl: redirectUrl,
          upstreamResponse: followResponse,
          redirectDepth: redirectDepth + 1
        });
        return;
      }

      writeUpstreamResponse(res, followResponse);
      return;
    } finally {
      clearTimeout(timer);
    }
  }

  writeUpstreamResponse(res, upstreamResponse, {
    location: buildProxyUrl(requestOrigin, redirectUrl)
  });
}

async function handleWebSocketUpgrade(req, socket, head) {
  const requestOrigin = getRequestOrigin(req);
  const requestUrl = new URL(req.url || '/', requestOrigin);
  const upstreamUrl = parseUpstreamUrl(requestUrl);

  applyDomainProxyRule(req, upstreamUrl);

  const connect =
    upstreamUrl.protocol === 'https:'
      ? () =>
          createTlsConnection({
            host: upstreamUrl.hostname,
            port: Number(upstreamUrl.port || 443),
            servername: upstreamUrl.hostname
          })
      : () =>
          createTcpConnection({
            host: upstreamUrl.hostname,
            port: Number(upstreamUrl.port || 80)
          });

  const upstreamSocket = connect();

  upstreamSocket.once('connect', () => {
    const requestLines = [];
    const forwardedHeaders = buildWebSocketRequestHeaders(req, upstreamUrl, requestOrigin);

    requestLines.push(`GET ${upstreamUrl.pathname}${upstreamUrl.search} HTTP/${req.httpVersion}`);

    for (const [name, value] of forwardedHeaders) {
      requestLines.push(`${name}: ${value}`);
    }

    requestLines.push('', '');

    upstreamSocket.write(requestLines.join('\r\n'));

    if (head && head.length > 0) {
      upstreamSocket.write(head);
    }

    socket.pipe(upstreamSocket);
    upstreamSocket.pipe(socket);
  });

  const closeBoth = () => {
    if (!socket.destroyed) {
      socket.destroy();
    }

    if (!upstreamSocket.destroyed) {
      upstreamSocket.destroy();
    }
  };

  upstreamSocket.on('error', closeBoth);
  socket.on('error', closeBoth);
  upstreamSocket.on('end', closeBoth);
  socket.on('end', closeBoth);
}

function parseUpstreamUrl(requestUrl) {
  let proxyPath = requestUrl.pathname.slice(1);

  if (!proxyPath || proxyPath.startsWith('/')) {
    throw createHttpError(400, 'Invalid proxy format. Please use: https://your-domain/your-emby-server:port');
  }

  if (
    proxyPath === 'Sessions/Playing' ||
    proxyPath.startsWith('Sessions/Playing/') ||
    proxyPath === 'PlaybackInfo' ||
    proxyPath.startsWith('PlaybackInfo/')
  ) {
    throw createHttpError(400, 'Invalid proxy format. Please use: https://your-domain/your-emby-server:port');
  }

  proxyPath = proxyPath.replace(/^(https?)\/(?!\/)/, '$1://');

  if (!proxyPath.startsWith('http://') && !proxyPath.startsWith('https://')) {
    proxyPath = `https://${proxyPath}`;
  }

  let upstreamUrl;

  try {
    upstreamUrl = new URL(proxyPath);
  } catch {
    throw createHttpError(400, 'Invalid URL format. Please use: https://your-domain/your-emby-server:port');
  }

  if (!upstreamUrl.hostname || upstreamUrl.hostname === 'Sessions' || upstreamUrl.hostname === 'PlaybackInfo') {
    throw createHttpError(400, 'Invalid proxy format. Please use: https://your-domain/your-emby-server:port');
  }

  upstreamUrl.search = requestUrl.search;
  return upstreamUrl;
}

function applyDomainProxyRule(req, upstreamUrl) {
  const currentEdgeColo = getEdgeColo(req);

  if (!currentEdgeColo || !JP_COLOS.includes(currentEdgeColo)) {
    return;
  }

  for (const [domainSuffix, targetHost] of Object.entries(DOMAIN_PROXY_RULES)) {
    if (!upstreamUrl.hostname.endsWith(domainSuffix)) {
      continue;
    }

    const targetUrl = new URL(
      targetHost.startsWith('http://') || targetHost.startsWith('https://')
        ? targetHost
        : `${upstreamUrl.protocol}//${targetHost}`
    );

    upstreamUrl.host = targetUrl.host;
    return;
  }
}

function recordStatsIfNeeded(pathname) {
  if (pathname.endsWith('/Sessions/Playing')) {
    statsStore.increment('playing').catch((error) => {
      console.error('Failed to record playing stats:', error);
    });
    return;
  }

  if (pathname.includes('/PlaybackInfo')) {
    statsStore.increment('playback_info').catch((error) => {
      console.error('Failed to record playback stats:', error);
    });
  }
}

function buildUpstreamRequestHeaders(req, upstreamUrl) {
  const headers = new Headers();

  for (const [name, rawValue] of Object.entries(req.headers)) {
    if (rawValue == null) {
      continue;
    }

    const lowerName = name.toLowerCase();

    if (
      lowerName === 'host' ||
      lowerName === 'connection' ||
      lowerName === 'transfer-encoding' ||
      lowerName === 'proxy-connection' ||
      lowerName === 'upgrade' ||
      lowerName === 'referer'
    ) {
      continue;
    }

    if (Array.isArray(rawValue)) {
      for (const value of rawValue) {
        headers.append(name, value);
      }
      continue;
    }

    headers.set(name, rawValue);
  }

  headers.set('Host', upstreamUrl.host);

  const clientIp = getClientIp(req);
  if (clientIp) {
    headers.set('X-Forwarded-For', clientIp);
    headers.set('X-Real-IP', clientIp);
  }

  const originalHost = req.headers.host;
  if (originalHost) {
    headers.set('X-Forwarded-Host', originalHost);
  }

  headers.set('X-Forwarded-Proto', getForwardedProto(req));

  return headers;
}

function buildWebSocketRequestHeaders(req, upstreamUrl, requestOrigin) {
  const filteredHeaders = [];

  for (let index = 0; index < req.rawHeaders.length; index += 2) {
    const name = req.rawHeaders[index];
    const value = req.rawHeaders[index + 1];
    const lowerName = name.toLowerCase();

    if (
      lowerName === 'host' ||
      lowerName === 'proxy-connection' ||
      lowerName === 'x-forwarded-for' ||
      lowerName === 'x-real-ip' ||
      lowerName === 'x-forwarded-proto' ||
      lowerName === 'x-forwarded-host'
    ) {
      continue;
    }

    filteredHeaders.push([name, value]);
  }

  filteredHeaders.push(['Host', upstreamUrl.host]);

  const clientIp = getClientIp(req);
  if (clientIp) {
    filteredHeaders.push(['X-Forwarded-For', clientIp]);
    filteredHeaders.push(['X-Real-IP', clientIp]);
  }

  filteredHeaders.push(['X-Forwarded-Proto', getForwardedProto(req)]);

  const forwardedHost = req.headers.host || new URL(requestOrigin).host;
  filteredHeaders.push(['X-Forwarded-Host', forwardedHost]);

  return filteredHeaders;
}

function writeUpstreamResponse(res, upstreamResponse, overrides = {}) {
  const responseHeaders = {};
  const setCookies =
    typeof upstreamResponse.headers.getSetCookie === 'function'
      ? upstreamResponse.headers.getSetCookie()
      : [];

  upstreamResponse.headers.forEach((value, name) => {
    const lowerName = name.toLowerCase();

    if (
      lowerName === 'connection' ||
      lowerName === 'transfer-encoding' ||
      lowerName === 'content-security-policy' ||
      lowerName === 'x-frame-options'
    ) {
      return;
    }

    responseHeaders[name] = value;
  });

  for (const [name, value] of Object.entries(overrides)) {
    responseHeaders[name] = value;
  }

  applyCorsHeaders(responseHeaders);

  if (setCookies.length > 0) {
    responseHeaders['set-cookie'] = setCookies;
  }

  res.writeHead(upstreamResponse.status, upstreamResponse.statusText, responseHeaders);

  if (!upstreamResponse.body) {
    res.end();
    return;
  }

  const bodyStream = Readable.fromWeb(upstreamResponse.body);
  bodyStream.on('error', (error) => {
    console.error('Proxy response stream error:', error);
    res.destroy(error);
  });
  bodyStream.pipe(res);
}

function applyCorsHeaders(headers) {
  headers['Access-Control-Allow-Origin'] = '*';
  headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS';
  headers['Access-Control-Allow-Headers'] = '*';
}

function getClientIp(req) {
  if (TRUST_PROXY_HEADERS) {
    const cfIp = req.headers['cf-connecting-ip'];
    if (typeof cfIp === 'string' && cfIp) {
      return cfIp;
    }

    const forwardedFor = req.headers['x-forwarded-for'];
    if (typeof forwardedFor === 'string' && forwardedFor) {
      return forwardedFor.split(',')[0].trim();
    }
  }

  return req.socket.remoteAddress || '';
}

function getForwardedProto(req) {
  if (TRUST_PROXY_HEADERS) {
    const forwardedProto = req.headers['x-forwarded-proto'];
    if (typeof forwardedProto === 'string' && forwardedProto) {
      return forwardedProto.split(',')[0].trim();
    }
  }

  return req.socket.encrypted ? 'https' : 'http';
}

function getRequestOrigin(req) {
  const proto = getForwardedProto(req);

  let host = req.headers.host;
  if (TRUST_PROXY_HEADERS) {
    const forwardedHost = req.headers['x-forwarded-host'];
    if (typeof forwardedHost === 'string' && forwardedHost) {
      host = forwardedHost.split(',')[0].trim();
    }
  }

  host = host || `${HOST}:${PORT}`;
  return `${proto}://${host}`;
}

function getEdgeColo(req) {
  if (!TRUST_PROXY_HEADERS) {
    return '';
  }

  const explicitColo = req.headers['x-cf-colo'];
  if (typeof explicitColo === 'string' && explicitColo) {
    return explicitColo.trim().toUpperCase();
  }

  const cfRay = req.headers['cf-ray'];
  if (typeof cfRay === 'string' && cfRay.includes('-')) {
    return cfRay.split('-').at(-1).trim().toUpperCase();
  }

  return '';
}

function buildProxyUrl(requestOrigin, targetUrl) {
  return `${requestOrigin.replace(/\/$/, '')}/${targetUrl.toString()}`;
}

function isManualRedirect(hostname) {
  return MANUAL_REDIRECT_DOMAINS.some((domain) => hostname.endsWith(domain));
}

function isRedirectResponse(response) {
  return response.status >= 300 && response.status < 400;
}

function sendHtml(res, statusCode, html) {
  sendBuffer(res, statusCode, Buffer.from(html, 'utf8'), {
    'Content-Type': 'text/html; charset=utf-8'
  });
}

function sendJson(res, statusCode, data) {
  const payload = JSON.stringify(data, null, 2);
  sendBuffer(res, statusCode, Buffer.from(payload, 'utf8'), {
    'Content-Type': 'application/json; charset=utf-8'
  });
}

function sendText(res, statusCode, text) {
  sendBuffer(res, statusCode, Buffer.from(text, 'utf8'), {
    'Content-Type': 'text/plain; charset=utf-8'
  });
}

function sendEmpty(res, statusCode, extraHeaders = {}) {
  const headers = { ...extraHeaders };
  applyCorsHeaders(headers);
  res.writeHead(statusCode, headers);
  res.end();
}

function sendBuffer(res, statusCode, buffer, extraHeaders = {}) {
  const headers = {
    'Content-Length': buffer.byteLength,
    ...extraHeaders
  };

  applyCorsHeaders(headers);
  res.writeHead(statusCode, headers);
  res.end(buffer);
}

function sendUpgradeError(socket, statusCode, statusText) {
  if (socket.destroyed) {
    return;
  }

  socket.write(`HTTP/1.1 ${statusCode} ${statusText}\r\nConnection: close\r\n\r\n`);
  socket.destroy();
}

function createHttpError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}
