// ===== 定数 =====
const GAMES = [
  { id: "basic-aim",         name: "基本エイム", file: "game-basic-aim.html",         color: "#3fb950" },
  { id: "divided-attention", name: "注意配分",   file: "game-divided-attention.html", color: "#d29922" },
  { id: "go-nogo",           name: "抑制課題",   file: "game-go-nogo.html",           color: "#f85149" },
  { id: "task-switching",    name: "ルール切替", file: "game-task-switching.html",    color: "#8b5cf6" },
];

// フィルターの現在選択値（null = すべて）
let currentFilter = null;

// キャッシュ済み履歴
let cachedHistory = [];

// ===== ローディングUI =====
function showLoading() {
  document.getElementById("loading-overlay").classList.add("visible");
}

function hideLoading() {
  document.getElementById("loading-overlay").classList.remove("visible");
}

// ===== エラーUI =====
function showError(message) {
  const el = document.getElementById("error-banner");
  if (!el) return;
  el.textContent = message;
  el.classList.add("visible");
}

// ===== オフライン検知 =====
function initOfflineBanner() {
  const banner = document.getElementById("offline-banner");
  if (!banner) return;

  function update() {
    if (navigator.onLine) {
      banner.classList.remove("visible");
    } else {
      banner.classList.add("visible");
    }
  }

  window.addEventListener("online",  update);
  window.addEventListener("offline", update);
  update();
}

// ===== Firestoreからスコア履歴を取得 =====
async function fetchHistory(userId) {
  const snapshot = await db.collection("results")
    .where("userId", "==", userId)
    .get();

  return snapshot.docs
    .map(doc => doc.data())
    .sort((a, b) => {
      const toMs = v => v?.toDate?.().getTime() ?? new Date(v ?? 0).getTime();
      return toMs(b.playedAt) - toMs(a.playedAt);
    });
}

// ===== ヘッダーの総プレイ回数 =====
function renderTotalPlays(count) {
  const el = document.getElementById("total-plays");
  if (el) el.textContent = count;
}

// ===== カードのベストスコア =====
function renderBestScores(history) {
  GAMES.forEach(game => {
    const el = document.getElementById("best-" + game.id);
    if (!el) return;
    const scores = history.filter(r => r.gameName === game.name).map(r => r.score);
    const best = scores.length > 0 ? Math.max(...scores) : null;
    el.innerHTML = best !== null
      ? `ベスト: <span>${best.toLocaleString()}</span>`
      : `ベスト: <span>--</span>`;
  });
}

// ===== ゲーム別統計パネル =====
function renderStats(history) {
  const el = document.getElementById("stats-grid");
  if (!el) return;

  el.innerHTML = GAMES.map(game => {
    const records = history.filter(r => r.gameName === game.name);
    const count   = records.length;
    const best    = count > 0 ? Math.max(...records.map(r => r.score)) : null;
    const avg     = count > 0
      ? Math.round(records.reduce((s, r) => s + r.score, 0) / count)
      : null;

    return `
      <div class="stat-card">
        <div class="stat-card-title">
          <div class="stat-dot" style="background:${game.color}"></div>
          ${game.name}
        </div>
        <div class="stat-row">
          <span class="stat-label">プレイ回数</span>
          <span class="stat-value">${count}回</span>
        </div>
        <div class="stat-row">
          <span class="stat-label">ベスト</span>
          <span class="stat-value" style="color:${game.color}">${best !== null ? best.toLocaleString() : "--"}</span>
        </div>
        <div class="stat-row">
          <span class="stat-label">平均</span>
          <span class="stat-value">${avg !== null ? avg.toLocaleString() : "--"}</span>
        </div>
      </div>
    `;
  }).join("");
}

// ===== 履歴フィルター =====
function initFilter() {
  const bar = document.getElementById("filter-bar");
  if (!bar) return;

  const filters = [{ label: "すべて", value: null }, ...GAMES.map(g => ({ label: g.name, value: g.name }))];

  bar.innerHTML = filters.map(f => `
    <button
      class="filter-btn ${f.value === currentFilter ? "active" : ""}"
      onclick="setFilter(${f.value === null ? "null" : `'${f.value}'`})"
    >${f.label}</button>
  `).join("");
}

function setFilter(value) {
  currentFilter = value;
  initFilter();
  renderHistory(cachedHistory);
}

// ===== 履歴リスト =====
function renderHistory(history) {
  const el = document.getElementById("history-list");
  if (!el) return;

  const filtered = currentFilter
    ? history.filter(r => r.gameName === currentFilter)
    : history;

  const items = filtered.slice(0, 30);

  if (items.length === 0) {
    el.innerHTML = '<p class="history-empty">該当する記録がありません。</p>';
    return;
  }

  el.innerHTML = items.map(r => {
    const game = GAMES.find(g => g.name === r.gameName) || { color: "#8b949e" };

    let dateStr = "--";
    if (r.playedAt) {
      const date = r.playedAt.toDate ? r.playedAt.toDate() : new Date(r.playedAt);
      dateStr = `${date.getMonth() + 1}/${date.getDate()} ${date.getHours()}:${String(date.getMinutes()).padStart(2, "0")}`;
    }

    return `
      <div class="history-item">
        <div class="history-game">
          <div class="history-dot" style="background:${game.color}"></div>
          <div>
            <div class="history-name">${r.gameName}</div>
            <div class="history-date">${dateStr}</div>
          </div>
        </div>
        <div class="history-score" style="color:${game.color}">${r.score.toLocaleString()}</div>
      </div>
    `;
  }).join("");
}

// ===== グラフ（直近10プレイのスコア推移） =====
let chartInstance = null;

function renderChart(history) {
  const ctx = document.getElementById("score-chart");
  if (!ctx) return;

  const recent = history.slice(0, 10).reverse();

  const labels = recent.map(r => {
    if (!r.playedAt) return "--";
    const d = r.playedAt.toDate ? r.playedAt.toDate() : new Date(r.playedAt);
    return `${d.getMonth() + 1}/${d.getDate()}`;
  });

  const datasets = GAMES.map(game => ({
    label: game.name,
    data: recent.map(r => r.gameName === game.name ? r.score : null),
    borderColor: game.color,
    backgroundColor: game.color + "33",
    pointBackgroundColor: game.color,
    pointRadius: 5,
    tension: 0.3,
    spanGaps: true,
  }));

  if (chartInstance) chartInstance.destroy();

  chartInstance = new Chart(ctx, {
    type: "line",
    data: { labels, datasets },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: { labels: { color: "#8b949e", font: { size: 11 } } }
      },
      scales: {
        x: { ticks: { color: "#8b949e", font: { size: 11 } }, grid: { color: "#30363d" } },
        y: { ticks: { color: "#8b949e", font: { size: 11 } }, grid: { color: "#30363d" } }
      }
    }
  });
}

// ===== 履歴リセット =====
async function clearHistory() {
  if (!confirm("スコア履歴をすべて削除しますか？")) return;

  const userId = auth.currentUser?.uid;
  if (!userId) return;

  showLoading();
  try {
    const snapshot = await db.collection("results").where("userId", "==", userId).get();
    const batch = db.batch();
    snapshot.docs.forEach(doc => batch.delete(doc.ref));
    await batch.commit();
    cachedHistory = [];
    renderAll(cachedHistory);
  } catch (err) {
    showError("削除に失敗しました。ネットワーク接続を確認してください。");
  } finally {
    hideLoading();
  }
}

// ===== まとめて描画 =====
function renderAll(history) {
  renderTotalPlays(history.length);
  renderBestScores(history);
  renderStats(history);
  initFilter();
  renderHistory(history);
  renderChart(history);
}

// ===== ログアウト =====
async function logout() {
  await auth.signOut();
  window.location.href = "login.html";
}

// ===== ローディング画面にエラーを表示（オーバーレイ上） =====
function showLoadingError(message) {
  document.getElementById("loading-spinner").style.display = "none";
  document.getElementById("loading-text").textContent = message;
  document.getElementById("loading-text").style.color = "#f85149";
  document.getElementById("loading-reload-btn").style.display = "block";
}

// ===== 初期化 =====
document.addEventListener("DOMContentLoaded", () => {
  initOfflineBanner();
  showLoading();

  // Firebase自体が読み込めていない場合（CDNブロックなど）
  if (typeof auth === "undefined") {
    showLoadingError("Firebaseの読み込みに失敗しました。\nネットワーク接続を確認してください。");
    return;
  }

  // 8秒以内に応答がなければエラーを表示
  const authTimeout = setTimeout(() => {
    showLoadingError("接続がタイムアウトしました。\nネットワーク接続を確認してください。");
  }, 8000);

  auth.onAuthStateChanged(async user => {
    clearTimeout(authTimeout);

    if (!user) {
      window.location.href = "login.html";
      return;
    }

    // ヘッダーにメールアドレスを表示
    const emailEl = document.getElementById("user-email");
    if (emailEl) emailEl.textContent = user.email;

    try {
      cachedHistory = await fetchHistory(user.uid);
      renderAll(cachedHistory);
    } catch (err) {
      console.error(err);
      showError("データの読み込みに失敗しました。ネットワーク接続を確認してください。");
    } finally {
      hideLoading();
    }
  });
});
