export function renderFrontendHtml({ statsDailyWindow, statsTotalWindow }) {
  return `<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Emby 服务器反代 | 使用说明</title>
  <style>
    :root {
      --bg: #101621;
      --panel: #182233;
      --panel-soft: rgba(24, 34, 51, 0.88);
      --line: rgba(126, 167, 255, 0.18);
      --text: #eef4ff;
      --muted: #b5c2d8;
      --accent: #54a3ff;
      --accent-soft: rgba(84, 163, 255, 0.12);
      --warn: #ff9671;
      --ok: #62d2a2;
    }

    * {
      box-sizing: border-box;
    }

    body {
      margin: 0;
      min-height: 100vh;
      font-family: "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif;
      color: var(--text);
      background:
        radial-gradient(circle at top left, rgba(84, 163, 255, 0.22), transparent 30%),
        radial-gradient(circle at bottom right, rgba(98, 210, 162, 0.16), transparent 28%),
        linear-gradient(180deg, #0c1220 0%, #101621 42%, #0f1725 100%);
    }

    .shell {
      width: min(1040px, calc(100% - 32px));
      margin: 0 auto;
      padding: 28px 0 40px;
    }

    .hero,
    .panel {
      backdrop-filter: blur(12px);
      background: var(--panel-soft);
      border: 1px solid var(--line);
      border-radius: 22px;
      box-shadow: 0 20px 60px rgba(0, 0, 0, 0.28);
    }

    .hero {
      padding: 28px;
      margin-bottom: 20px;
    }

    .eyebrow {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 6px 12px;
      border-radius: 999px;
      font-size: 13px;
      letter-spacing: 0.06em;
      text-transform: uppercase;
      background: var(--accent-soft);
      color: var(--accent);
      border: 1px solid rgba(84, 163, 255, 0.25);
    }

    h1,
    h2,
    h3,
    p {
      margin: 0;
    }

    .hero h1 {
      margin-top: 14px;
      font-size: clamp(32px, 6vw, 52px);
      line-height: 1.05;
    }

    .hero p {
      margin-top: 14px;
      max-width: 760px;
      color: var(--muted);
      font-size: 16px;
    }

    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 16px;
      margin-top: 24px;
    }

    .feature {
      padding: 18px;
      border-radius: 18px;
      background: rgba(255, 255, 255, 0.03);
      border: 1px solid rgba(255, 255, 255, 0.06);
    }

    .feature strong {
      display: block;
      margin-bottom: 8px;
      color: var(--text);
    }

    .feature span {
      color: var(--muted);
      font-size: 14px;
    }

    .layout {
      display: grid;
      grid-template-columns: 1.25fr 0.95fr;
      gap: 20px;
      align-items: start;
    }

    .panel {
      padding: 24px;
    }

    .panel h2 {
      font-size: 22px;
      margin-bottom: 16px;
    }

    .stack {
      display: grid;
      gap: 14px;
    }

    .code-box,
    code {
      font-family: Consolas, "Courier New", monospace;
    }

    .code-box {
      padding: 14px 16px;
      border-radius: 16px;
      font-size: 14px;
      line-height: 1.65;
      color: #cfe4ff;
      background: rgba(84, 163, 255, 0.08);
      border: 1px solid rgba(84, 163, 255, 0.18);
      overflow-x: auto;
    }

    .note {
      color: var(--muted);
      font-size: 14px;
      line-height: 1.7;
    }

    .warn {
      margin-top: 18px;
      padding: 16px 18px;
      border-radius: 18px;
      background: rgba(255, 150, 113, 0.08);
      border: 1px solid rgba(255, 150, 113, 0.24);
      color: #ffd7c9;
      line-height: 1.7;
    }

    .stats-wrap {
      display: grid;
      gap: 16px;
    }

    .stats-summary {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 14px;
    }

    .stats-card {
      padding: 18px;
      border-radius: 18px;
      background: rgba(98, 210, 162, 0.08);
      border: 1px solid rgba(98, 210, 162, 0.18);
    }

    .stats-card small {
      color: var(--muted);
      display: block;
      margin-bottom: 8px;
    }

    .stats-card strong {
      font-size: clamp(24px, 4vw, 36px);
      color: var(--ok);
    }

    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 14px;
    }

    th,
    td {
      padding: 12px 10px;
      text-align: left;
      border-bottom: 1px solid rgba(255, 255, 255, 0.07);
    }

    th {
      color: var(--accent);
      font-weight: 600;
    }

    .footer {
      margin-top: 18px;
      color: var(--muted);
      font-size: 13px;
      line-height: 1.7;
    }

    a {
      color: var(--accent);
      text-decoration: none;
    }

    @media (max-width: 860px) {
      .layout {
        grid-template-columns: 1fr;
      }

      .stats-summary {
        grid-template-columns: 1fr;
      }

      .hero,
      .panel {
        padding: 20px;
      }
    }
  </style>
</head>
<body>
  <main class="shell">
    <section class="hero">
      <span class="eyebrow">Self-hosted Emby Proxy</span>
      <h1>把原来的 Worker 反代，改成可直接部署到服务器的版本。</h1>
      <p>当前服务可直接跑在 Linux 服务器上，再由 nginx 或 Caddy 做 HTTPS 和反向代理。请求格式与原项目保持一致，不需要改 Emby 客户端的接入习惯。</p>

      <div class="grid">
        <div class="feature">
          <strong>保留原有用法</strong>
          <span>继续使用 <code>/https://目标地址</code> 这种路径格式。</span>
        </div>
        <div class="feature">
          <strong>支持 WebSocket</strong>
          <span>适配 Emby 常见实时连接场景，不依赖 Cloudflare Workers。</span>
        </div>
        <div class="feature">
          <strong>本地持久化统计</strong>
          <span>统计数据写入服务器本地文件，不再依赖 D1 数据库。</span>
        </div>
      </div>
    </section>

    <section class="layout">
      <article class="panel">
        <h2>使用方式</h2>
        <div class="stack">
          <div class="code-box">https://你的服务域名/你的域名:端口</div>
          <div class="code-box">https://你的服务域名/http://emby.example.com:8096</div>
          <div class="code-box">https://你的服务域名/https://emby.example.com</div>
        </div>

        <p class="note">如果路径里没有显式写 <code>http://</code> 或 <code>https://</code>，服务会默认按 <code>https://</code> 处理。</p>

        <div class="warn">
          添加到客户端之前，建议先手动访问一次目标地址确认链路正常。服务器版同样支持重定向和常见网盘直连白名单，但首次部署后最好先做小流量验证。
        </div>

        <div class="footer">
          <div>统计接口：<a href="/stats" target="_blank" rel="noreferrer">/stats</a></div>
          <div>健康检查：<a href="/health" target="_blank" rel="noreferrer">/health</a></div>
        </div>
      </article>

      <aside class="panel">
        <h2>最近统计</h2>
        <div id="stats-loading" class="note">正在加载统计数据...</div>
        <div id="stats-error" class="warn" style="display:none;"></div>
        <div id="stats-content" class="stats-wrap" style="display:none;">
          <div class="stats-summary">
            <div class="stats-card">
              <small>最近 ${statsTotalWindow} 天播放次数</small>
              <strong id="total-playing">0</strong>
            </div>
            <div class="stats-card">
              <small>最近 ${statsTotalWindow} 天获取链接次数</small>
              <strong id="total-playback-info">0</strong>
            </div>
          </div>

          <div style="overflow-x:auto;">
            <table>
              <thead>
                <tr>
                  <th>日期</th>
                  <th>播放次数</th>
                  <th>获取链接次数</th>
                </tr>
              </thead>
              <tbody id="daily-stats-body"></tbody>
            </table>
          </div>

          <div class="footer">
            <div>展示最近 ${statsDailyWindow} 天明细</div>
            <div>更新时间：<span id="last-updated">--</span></div>
          </div>
        </div>
      </aside>
    </section>
  </main>

  <script>
    async function fetchStats() {
      const loading = document.getElementById('stats-loading');
      const error = document.getElementById('stats-error');
      const content = document.getElementById('stats-content');

      try {
        const response = await fetch('/stats', { cache: 'no-store' });
        const payload = await response.json();

        if (payload.error) {
          throw new Error(payload.error);
        }

        const stats = payload.data;
        document.getElementById('total-playing').textContent = stats.total.playing;
        document.getElementById('total-playback-info').textContent = stats.total.playbackInfo;
        document.getElementById('last-updated').textContent = stats.lastUpdated;

        const tableBody = document.getElementById('daily-stats-body');
        tableBody.innerHTML = '';

        if (!stats.dailyStats.length) {
          tableBody.innerHTML = '<tr><td colspan="3">暂无统计数据</td></tr>';
        } else {
          for (const row of stats.dailyStats) {
            const tr = document.createElement('tr');
            tr.innerHTML = '<td>' + row.date + '</td><td>' + row.playing_count + '</td><td>' + row.playback_info_count + '</td>';
            tableBody.appendChild(tr);
          }
        }

        loading.style.display = 'none';
        error.style.display = 'none';
        content.style.display = 'grid';
      } catch (fetchError) {
        loading.style.display = 'none';
        content.style.display = 'none';
        error.style.display = 'block';
        error.textContent = '获取统计数据失败：' + fetchError.message;
      }
    }

    fetchStats();
    setInterval(fetchStats, 3600000);
  </script>
</body>
</html>`;
}
