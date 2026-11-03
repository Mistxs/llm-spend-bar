(() => {
  "use strict";

  const state = {
    snapshot: null,
    period: "month",
    chartMode: "tool",
    breakdownTab: "tools",
  };

  const palette = ["#60a5fa", "#a78bfa", "#34d399", "#fbbf24", "#f472b6", "#22d3ee", "#f87171", "#94a3b8"];

  const $ = (selector) => document.querySelector(selector);
  const $$ = (selector) => Array.from(document.querySelectorAll(selector));

  function post(action, payload = {}) {
    try {
      window.webkit?.messageHandlers?.llmSpend?.postMessage({ action, ...payload });
    } catch (_) {
      /* Preview in a normal browser: ignore. */
    }
  }

  function esc(value) {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;");
  }

  function usd(value) {
    const n = Number(value) || 0;
    if (n <= 0) return "$0.00";
    if (n >= 0.1) return `$${n.toFixed(2)}`;
    if (n >= 0.001) return `$${n.toFixed(3)}`;
    if (n >= 0.00001) return `$${n.toFixed(5)}`;
    return `$${n.toFixed(6)}`;
  }

  function tokens(value) {
    const n = Number(value) || 0;
    if (n >= 1e9) return `${(n / 1e9).toFixed(2)}B`;
    if (n >= 1e6) return `${(n / 1e6).toFixed(n >= 1e7 ? 1 : 2)}M`;
    if (n >= 1e3) return `${(n / 1e3).toFixed(n >= 1e4 ? 0 : 1)}k`;
    return String(Math.round(n));
  }

  function pct(value) {
    const n = Number(value) || 0;
    return `${Math.round(Math.max(0, Math.min(1, n)) * 100)}%`;
  }

  function dateLabel(value) {
    if (!value) return "";
    const date = new Date(`${value}T12:00:00`);
    if (Number.isNaN(date.getTime())) return value;
    return new Intl.DateTimeFormat("ru-RU", { day: "numeric", month: "short" }).format(date);
  }

  function relative(epochSeconds) {
    if (!epochSeconds) return "";
    const seconds = Math.max(0, Date.now() / 1000 - Number(epochSeconds));
    if (seconds < 60) return "только что";
    if (seconds < 3600) return `${Math.round(seconds / 60)} мин назад`;
    if (seconds < 86400) return `${Math.round(seconds / 3600)} ч назад`;
    return `${Math.round(seconds / 86400)} дн назад`;
  }

  function sum(obj) {
    return Object.values(obj || {}).reduce((total, value) => total + (Number(value) || 0), 0);
  }

  function maxBy(array, key) {
    return array.reduce((best, item) => (Number(item[key]) > Number(best[key]) ? item : best), array[0] || {});
  }

  function showTooltip(event, html) {
    const tooltip = $("#tooltip");
    tooltip.innerHTML = html;
    tooltip.classList.remove("hidden");
    const pad = 14;
    const rect = tooltip.getBoundingClientRect();
    let x = event.clientX + pad;
    let y = event.clientY + pad;
    if (x + rect.width > window.innerWidth - 8) x = event.clientX - rect.width - pad;
    if (y + rect.height > window.innerHeight - 8) y = event.clientY - rect.height - pad;
    tooltip.style.left = `${Math.max(8, x)}px`;
    tooltip.style.top = `${Math.max(8, y)}px`;
  }

  function hideTooltip() {
    $("#tooltip").classList.add("hidden");
  }

  function renderKPIs() {
    const data = state.snapshot;
    const totals = data?.totals || {};
    const cacheShare = Number(totals.cacheRead) > 0
      ? Number(totals.cacheRead) / Math.max(1, Number(totals.cacheRead) + Number(totals.input))
      : 0;
    const items = [
      { label: "Расход", value: usd(totals.spend), sub: "оценка по прайсу моделей", accent: "var(--green)" },
      { label: "Токены", value: tokens(totals.tokens), sub: `${tokens(totals.cacheRead)} из кэша`, accent: "var(--blue)" },
      { label: "Запросы", value: String(totals.requests || 0), sub: "billable turns", accent: "var(--purple)" },
      { label: "Кэш", value: pct(cacheShare), sub: `${tokens(totals.cacheRead)} cache read`, accent: "var(--cyan)" },
    ];
    $("#kpis").innerHTML = items.map((item) => `
      <article class="kpi" style="--accent:${item.accent}">
        <div class="kpi-label">${esc(item.label)}</div>
        <div class="kpi-value">${esc(item.value)}</div>
        <div class="kpi-sub">${esc(item.sub)}</div>
      </article>
    `).join("");
  }

  function renderBudgets() {
    const data = state.snapshot;
    const budgets = data?.budgets || {};
    const rows = [
      { name: "День", spent: budgets.todaySpend, budget: budgets.daily },
      { name: "Неделя", spent: budgets.weekSpend, budget: budgets.weekly },
      { name: "Месяц", spent: budgets.monthSpend, budget: budgets.monthly },
    ];
    $("#budgets").innerHTML = rows.map((row) => {
      const fraction = Number(row.budget) > 0 ? Number(row.spent) / Number(row.budget) : 0;
      const cls = fraction >= 0.8 ? "bad" : fraction >= 0.5 ? "warn" : "";
      return `
        <div class="budget">
          <div class="budget-top">
            <span class="budget-name">${esc(row.name)}</span>
            <span class="budget-value">${usd(row.spent)} / ${usd(row.budget)}</span>
          </div>
          <div class="budget-bar"><div class="budget-fill ${cls}" style="width:${Math.min(100, fraction * 100).toFixed(1)}%"></div></div>
          <div class="budget-sub"><span>${pct(fraction)}</span><span>${Number(row.budget) > 0 ? `осталось ${usd(Math.max(0, row.budget - row.spent))}` : "бюджет не задан"}</span></div>
        </div>
      `;
    }).join("");
    const today = Number(budgets.todaySpend) || 0;
    $("#budgetMeta").textContent = today > 0 ? `сегодня ${usd(today)}` : "";
  }

  function subscriptionName(tool) {
    const names = { opencode: "OpenCode Go", claude: "Claude", codex: "Codex" };
    return names[tool] || tool;
  }

  function renderSubscriptions() {
    const rows = Array.isArray(state.snapshot?.subscriptions) ? state.snapshot.subscriptions : [];
    if (!rows.length) {
      $("#subscriptionsPanel").classList.add("hidden");
      return;
    }
    $("#subscriptionsPanel").classList.remove("hidden");
    const total = rows.reduce((acc, row) => acc + (Number(row.monthSpend) || 0), 0);
    $("#subscriptionsMeta").textContent = `API-эквивалент за месяц: ${usd(total)}`;
    $("#subscriptions").innerHTML = rows.map((row) => {
      const price = Number(row.price) || 0;
      const spend = Number(row.monthSpend) || 0;
      const ratio = price > 0 ? spend / price : 0;
      const cls = ratio >= 1 ? "good" : ratio >= 0.5 ? "" : "warn";
      const fill = price > 0 ? Math.min(100, ratio * 100) : 0;
      return `
        <div class="subscription">
          <div class="subscription-top">
            <span class="subscription-name">${esc(subscriptionName(row.tool))}</span>
            <span class="subscription-price">${price > 0 ? `${usd(price)} / мес` : "цена не задана"}</span>
          </div>
          <div class="subscription-values">
            <span>${usd(spend)} <span class="dim">API-экв.</span></span>
            <strong>${price > 0 ? pct(ratio) : "—"}</strong>
          </div>
          <div class="subscription-bar"><div class="subscription-fill ${cls}" style="width:${fill.toFixed(1)}%"></div></div>
          <div class="subscription-sub">
            <span>${tokens(row.tokens)} токенов · ${Number(row.requests) || 0} запросов</span>
            <span>${price > 0 ? (ratio >= 1 ? "окупилась" : "не окупилась") : "задайте в настройках"}</span>
          </div>
        </div>
      `;
    }).join("");
  }

  function renderChart() {
    const container = $("#activityChart");
    const data = state.snapshot;
    const series = data?.series || [];
    if (!series.length) {
      container.innerHTML = `<div class="empty">Нет данных за период</div>`;
      return;
    }
    const width = Math.max(620, container.clientWidth || 900);
    const height = 250;
    const margin = { left: 46, right: 14, top: 10, bottom: 26 };
    const innerW = width - margin.left - margin.right;
    const innerH = height - margin.top - margin.bottom;
    const sourceKey = state.chartMode === "model" ? "byModel" : "byTool";
    const totals = series.map((day) => sum(day[sourceKey] || {}));
    const maxTotal = Math.max(1, ...totals);
    const keys = new Set();
    series.forEach((day) => Object.keys(day[sourceKey] || {}).forEach((key) => keys.add(key)));
    const keyTotals = Array.from(keys).map((key) => ({
      key,
      total: series.reduce((acc, day) => acc + (Number(day[sourceKey]?.[key]) || 0), 0),
    })).sort((a, b) => b.total - a.total);
    const topKeys = keyTotals.slice(0, 7).map((entry) => entry.key);
    const colorFor = (key) => {
      const index = Math.max(0, topKeys.indexOf(key));
      return palette[index % palette.length];
    };

    const band = innerW / Math.max(1, series.length);
    const barW = Math.max(2, Math.min(16, band * 0.62));
    const y = (value) => margin.top + innerH - (value / maxTotal) * innerH;

    const grid = [0, 0.25, 0.5, 0.75, 1].map((fraction) => {
      const yy = margin.top + innerH - fraction * innerH;
      return `<line class="grid-line" x1="${margin.left}" y1="${yy}" x2="${width - margin.right}" y2="${yy}"></line>
        <text class="axis-label" x="${margin.left - 8}" y="${yy + 3}" text-anchor="end">${tokens(maxTotal * fraction)}</text>`;
    }).join("");

    const bars = series.map((day, index) => {
      const x = margin.left + index * band + (band - barW) / 2;
      let cursor = margin.top + innerH;
      const entries = Object.entries(day[sourceKey] || {})
        .filter(([, value]) => Number(value) > 0)
        .sort((a, b) => Number(b[1]) - Number(a[1]));
      const segments = entries.map(([key, value]) => {
        const h = (Number(value) / maxTotal) * innerH;
        cursor -= h;
        return `<rect class="bar" x="${x}" y="${cursor}" width="${barW}" height="${Math.max(0.6, h)}" rx="2" fill="${colorFor(key)}" opacity="0.92"></rect>`;
      }).join("");
      const tip = `<strong>${esc(dateLabel(day.date))}</strong><br>${tokens(day.tokens)} токенов · ${usd(day.spend)}<br>${esc(entries.slice(0, 4).map(([key, value]) => `${key}: ${tokens(value)}`).join(" · "))}`;
      return `<g data-tip="${esc(tip)}">${segments}<rect x="${margin.left + index * band}" y="${margin.top}" width="${band}" height="${innerH}" fill="transparent"></rect></g>`;
    }).join("");

    const labelStep = Math.max(1, Math.ceil(series.length / 7));
    const labels = series.map((day, index) => {
      if (index % labelStep !== 0 && index !== series.length - 1) return "";
      return `<text class="axis-label" x="${margin.left + index * band + band / 2}" y="${height - 8}" text-anchor="middle">${esc(dateLabel(day.date))}</text>`;
    }).join("");

    const legend = topKeys.map((key) => `
      <span class="legend-item"><span class="dot" style="background:${colorFor(key)}"></span>${esc(key)}</span>
    `).join("");

    container.innerHTML = `
      <svg viewBox="0 0 ${width} ${height}" preserveAspectRatio="none">
        ${grid}
        ${bars}
        ${labels}
      </svg>
      <div class="legend">${legend}</div>
    `;

    container.querySelectorAll("g[data-tip]").forEach((node) => {
      node.addEventListener("mousemove", (event) => showTooltip(event, node.dataset.tip));
      node.addEventListener("mouseleave", hideTooltip);
    });
  }

  function renderHeatmap() {
    const container = $("#heatmap");
    const data = state.snapshot;
    const days = data?.heatmap || [];
    if (!days.length) {
      container.innerHTML = `<div class="empty">Нет данных</div>`;
      return;
    }
    const values = days.map((day) => Number(day.tokens) || 0);
    const max = Math.max(1, ...values);
    const first = new Date(`${days[0].date}T12:00:00`);
    const startPad = Number.isNaN(first.getTime()) ? 0 : first.getDay();
    const cells = [];
    for (let i = 0; i < startPad; i++) cells.push(`<div class="heat-cell" style="opacity:0"></div>`);
    days.forEach((day) => {
      const value = Number(day.tokens) || 0;
      const alpha = value <= 0 ? 0 : 0.12 + 0.82 * Math.sqrt(value / max);
      const color = value <= 0 ? "rgba(255,255,255,0.045)" : `rgba(52, 211, 153, ${alpha.toFixed(3)})`;
      const tip = `<strong>${esc(dateLabel(day.date))}</strong><br>${tokens(value)} токенов · ${usd(day.spend)}<br>${Number(day.requests) || 0} запросов`;
      cells.push(`<div class="heat-cell" style="background:${color}" data-tip="${esc(tip)}"></div>`);
    });
    container.innerHTML = cells.join("");
    const total = values.reduce((acc, value) => acc + value, 0);
    const active = values.filter((value) => value > 0).length;
    $("#heatmapMeta").textContent = `${tokens(total)} токенов · ${active} активных дней`;
    container.querySelectorAll(".heat-cell[data-tip]").forEach((node) => {
      node.addEventListener("mousemove", (event) => showTooltip(event, node.dataset.tip));
      node.addEventListener("mouseleave", hideTooltip);
    });
  }

  function renderBreakdown() {
    const data = state.snapshot;
    const groups = state.breakdownTab === "models" ? data?.models : state.breakdownTab === "projects" ? data?.projects : data?.tools;
    const rows = Array.isArray(groups) ? groups.slice(0, 18) : [];
    if (!rows.length) {
      $("#breakdown").innerHTML = `<div class="empty">Нет данных за период</div>`;
      return;
    }
    const max = Math.max(1, ...rows.map((row) => Number(row.spend) || 0));
    $("#breakdown").innerHTML = rows.map((row) => {
      const fraction = (Number(row.spend) || 0) / max;
      return `
        <div class="breakdown-row">
          <div class="breakdown-name">
            <div>${esc(row.name || "unknown")}</div>
            <div class="bar-bg"><div class="bar-fill" style="width:${Math.max(2, fraction * 100).toFixed(1)}%"></div></div>
          </div>
          <div class="breakdown-value strong">${usd(row.spend)}</div>
          <div class="breakdown-value">${tokens(row.tokens)}</div>
          <div class="breakdown-value">${Number(row.requests) || 0}</div>
        </div>
      `;
    }).join("");
  }

  function renderSessions() {
    const data = state.snapshot;
    const rows = Array.isArray(data?.sessions) ? data.sessions.slice(0, 40) : [];
    $("#sessionsMeta").textContent = rows.length ? `${rows.length} сессий` : "";
    if (!rows.length) {
      $("#sessions").innerHTML = `<div class="empty">Нет сессий за период</div>`;
      return;
    }
    $("#sessions").innerHTML = rows.map((session) => `
      <div class="session-row">
        <div class="session-title">
          <strong title="${esc(session.title)}">${esc(session.title || session.id)}</strong>
          <span>${esc(session.tool || "")}${session.model ? ` · ${esc(session.model)}` : ""} · ${esc(relative(session.lastAt))}</span>
        </div>
        <div class="session-cell strong">${usd(session.spend)}</div>
        <div class="session-cell">${tokens(session.tokens)}</div>
        <div class="session-cell">${Number(session.requests) || 0}</div>
      </div>
    `).join("");
  }

  function renderUnpriced() {
    const items = state.snapshot?.unpriced || [];
    const panel = $("#unpricedPanel");
    if (!items.length) {
      panel.classList.add("hidden");
      return;
    }
    panel.classList.remove("hidden");
    $("#unpriced").innerHTML = items.map((name) => `<span class="chip">${esc(name)}</span>`).join("");
  }

  function renderAll() {
    if (!state.snapshot) return;
    state.period = state.snapshot.period || state.period;
    $$("#periods button").forEach((button) => button.classList.toggle("active", button.dataset.period === state.period));
    renderKPIs();
    renderBudgets();
    renderSubscriptions();
    renderChart();
    renderHeatmap();
    renderBreakdown();
    renderSessions();
    renderUnpriced();
  }

  function openSettings() {
    const budgets = state.snapshot?.budgets || {};
    $("#dailyBudget").value = Number(budgets.daily || 0).toFixed(2);
    $("#weeklyBudget").value = Number(budgets.weekly || 0).toFixed(2);
    $("#monthlyBudget").value = Number(budgets.monthly || 0).toFixed(2);
    $("#scanInterval").value = Number(state.snapshot?.scanInterval || 60);
    const subs = state.snapshot?.subscriptions || [];
    const byTool = Object.fromEntries(subs.map((row) => [row.tool, row.price]));
    $("#subscriptionOpencode").value = Number(byTool.opencode || 0);
    $("#subscriptionClaude").value = Number(byTool.claude || 0);
    $("#subscriptionCodex").value = Number(byTool.codex || 0);
    $("#settingsModal").classList.remove("hidden");
  }

  function closeSettings() {
    $("#settingsModal").classList.add("hidden");
  }

  function saveSettings() {
    post("saveSettings", {
      settings: {
        daily: Number($("#dailyBudget").value) || 0,
        weekly: Number($("#weeklyBudget").value) || 0,
        monthly: Number($("#monthlyBudget").value) || 0,
        scanInterval: Number($("#scanInterval").value) || 60,
        subscriptions: {
          opencode: Number($("#subscriptionOpencode").value) || 0,
          claude: Number($("#subscriptionClaude").value) || 0,
          codex: Number($("#subscriptionCodex").value) || 0,
        },
      },
    });
    closeSettings();
  }

  window.llmSpend = {
    render(snapshot) {
      state.snapshot = snapshot;
      renderAll();
    },
  };

  $$("#periods button").forEach((button) => {
    button.addEventListener("click", () => {
      state.period = button.dataset.period;
      $$("#periods button").forEach((item) => item.classList.toggle("active", item === button));
      post("setPeriod", { period: state.period });
    });
  });

  $$("#chartMode button").forEach((button) => {
    button.addEventListener("click", () => {
      state.chartMode = button.dataset.mode;
      $$("#chartMode button").forEach((item) => item.classList.toggle("active", item === button));
      renderChart();
    });
  });

  $$("#breakdownTabs button").forEach((button) => {
    button.addEventListener("click", () => {
      state.breakdownTab = button.dataset.tab;
      $$("#breakdownTabs button").forEach((item) => item.classList.toggle("active", item === button));
      renderBreakdown();
    });
  });

  $("#scanBtn").addEventListener("click", () => post("scan"));
  $("#settingsBtn").addEventListener("click", openSettings);
  $("#closeSettings").addEventListener("click", closeSettings);
  $("#cancelSettings").addEventListener("click", closeSettings);
  $("#saveSettings").addEventListener("click", saveSettings);
  $("#openDataFolder").addEventListener("click", () => post("dataFolder"));
  $("#settingsModal").addEventListener("click", (event) => {
    if (event.target === $("#settingsModal")) closeSettings();
  });

  let resizeTimer = null;
  window.addEventListener("resize", () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => {
      renderChart();
      renderHeatmap();
    }, 120);
  });
})();
