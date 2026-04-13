import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, '..');

const DEFAULT_MANUAL_REDIRECT_DOMAINS = [
  'emby.bangumi.ca',
  'aliyundrive.com',
  'aliyundrive.net',
  'aliyuncs.com',
  'alicdn.com',
  'aliyun.com',
  'cdn.aliyundrive.com',
  'xunlei.com',
  'xlusercdn.com',
  'xycdn.com',
  'sandai.net',
  'thundercdn.com',
  '115.com',
  '115cdn.com',
  '115cdn.net',
  'anxia.com',
  '189.cn',
  'mini189.cn',
  'ctyunxs.cn',
  'cloud.189.cn',
  'tianyiyun.com',
  'telecomjs.com',
  'quark.cn',
  'quarkdrive.cn',
  'uc.cn',
  'ucdrive.cn',
  'xiaoya.pro',
  'myqcloud.com',
  'cloudfront.net',
  'akamaized.net',
  'fastly.net',
  'hwcdn.net',
  'bytecdn.cn',
  'bdcdn.net'
];

const DEFAULT_JP_COLOS = ['NRT', 'KIX', 'FUK', 'OKA'];

export const HOST = process.env.HOST || '0.0.0.0';
export const PORT = toPositiveInteger(process.env.PORT, 3000);
export const TIME_ZONE = process.env.TIME_ZONE || 'Asia/Shanghai';
export const STATS_FILE = path.resolve(projectRoot, process.env.STATS_FILE || 'data/stats.json');
export const STATS_DAILY_WINDOW = toPositiveInteger(process.env.STATS_DAILY_WINDOW, 10);
export const STATS_TOTAL_WINDOW = toPositiveInteger(process.env.STATS_TOTAL_WINDOW, 30);
export const REQUEST_TIMEOUT_MS = toPositiveInteger(process.env.REQUEST_TIMEOUT_MS, 300000);
export const TRUST_PROXY_HEADERS = process.env.TRUST_PROXY_HEADERS !== 'false';
export const MANUAL_REDIRECT_DOMAINS = parseList(
  process.env.MANUAL_REDIRECT_DOMAINS,
  DEFAULT_MANUAL_REDIRECT_DOMAINS
);
export const DOMAIN_PROXY_RULES = parseProxyRules(process.env.DOMAIN_PROXY_RULES);
export const JP_COLOS = parseList(process.env.JP_COLOS, DEFAULT_JP_COLOS).map((value) =>
  value.toUpperCase()
);
export const BODYLESS_METHODS = new Set(['GET', 'HEAD']);

function parseList(value, fallback) {
  if (!value) {
    return [...fallback];
  }

  return value
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

function parseProxyRules(value) {
  if (!value) {
    return {};
  }

  return Object.fromEntries(
    value
      .split(',')
      .map((item) => item.trim())
      .filter(Boolean)
      .map((item) => {
        const separatorIndex = item.indexOf('=');

        if (separatorIndex === -1) {
          throw new Error(`Invalid DOMAIN_PROXY_RULES entry: ${item}`);
        }

        const suffix = item.slice(0, separatorIndex).trim();
        const target = item.slice(separatorIndex + 1).trim();

        if (!suffix || !target) {
          throw new Error(`Invalid DOMAIN_PROXY_RULES entry: ${item}`);
        }

        return [suffix, target];
      })
  );
}

function toPositiveInteger(value, fallback) {
  const parsed = Number.parseInt(value || '', 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}
