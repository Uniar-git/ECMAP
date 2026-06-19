// ===== 定数 =====
const GAMES = [
  { id: "nback", name: "N-Back",       file: "game-nback.html", color: "#818cf8" },
  { id: "mot",   name: "MOT",          file: "game-mot.html",   color: "#06b6d4" },
  { id: "cat",   name: "予測タイミング", file: "game-cat.html",   color: "#f97316" },
  { id: "ufov",  name: "UFOV",         file: "game-ufov.html",  color: "#ec4899" },
];

const DEFAULT_SETTINGS = {
  weeklyGoal: 3,
  rotation: ["nback", "mot", "cat", "ufov"],
  rotationEnabled: { nback: true, mot: true, cat: true, ufov: true },
  notificationTime: "20:00",
  notificationEnabled: false,
};

const SETTINGS_KEY = "ecmap_settings";

// フィルターの現在選択値（null = すべて）
let currentFilter = null;

// キャッシュ済み履歴
let cachedHistory = [];

// 現在の設定
let currentSettings = { ...DEFAULT_SETTINGS };

// 設定モーダルの編集中状態
let draftSettings = null;

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

// ===== 設定の読み書き =====
function loadSettingsFromCache() {
  try {
    const raw = localStorage.getItem(SETTINGS_KEY);
    if (!raw) return null;
    return normalizeSettings(JSON.parse(raw));
  } catch {
    return null;
  }
}

function saveSettingsToCache(settings) {
  try {
    localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings));
  } catch {}
}

function normalizeSettings(s) {
  const validIds = GAMES.map(g => g.id);
  const merged = { ...DEFAULT_SETTINGS, ...s };
  // rotation には現存する全ゲームが必ず含まれるように補完
  const rotation = (merged.rotation || []).filter(id => validIds.includes(id));
  validIds.forEach(id => { if (!rotation.includes(id)) rotation.push(id); });
  // rotationEnabled も補完
  const enabled = { ...merged.rotationEnabled };
  validIds.forEach(id => { if (typeof enabled[id] !== "boolean") enabled[id] = true; });
  return { ...merged, rotation, rotationEnabled: enabled };
}

async function fetchSettings(uid) {
  try {
    const doc = await db.collection("users").doc(uid).collection("settings").doc("preferences").get();
    if (doc.exists) return normalizeSettings(doc.data());
  } catch (err) {
    console.warn("settings fetch failed", err);
  }
  return null;
}

async function persistSettings(uid, settings) {
  saveSettingsToCache(settings);
  try {
    await db.collection("users").doc(uid).collection("settings").doc("preferences").set(settings);
  } catch (err) {
    console.warn("settings save failed", err);
    showError("設定の保存に失敗しました。ネットワーク接続を確認してください。");
  }
}

// ===== 週・ストリーク計算 =====
function getMondayStart(date = new Date()) {
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  const day = d.getDay(); // 0=Sun ... 6=Sat
  const diff = day === 0 ? -6 : 1 - day;
  d.setDate(d.getDate() + diff);
  return d;
}

function getTodayStart() {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d;
}

function getPlayedAtDate(record) {
  return record.playedAt?.toDate?.() ?? new Date(record.playedAt ?? 0);
}

function countPlaysInWeek(history, weekStart) {
  const weekEnd = new Date(weekStart);
  weekEnd.setDate(weekEnd.getDate() + 7);
  return history.filter(r => {
    const t = getPlayedAtDate(r);
    return t >= weekStart && t < weekEnd;
  }).length;
}

function calcWeekStreak(history, weeklyGoal) {
  // 前週から遡り、目標達成し続けた連続週数を返す
  let streak = 0;
  let weekStart = getMondayStart();
  weekStart.setDate(weekStart.getDate() - 7);
  for (let i = 0; i < 52; i++) {
    if (countPlaysInWeek(history, weekStart) >= weeklyGoal) {
      streak++;
      weekStart.setDate(weekStart.getDate() - 7);
    } else {
      break;
    }
  }
  return streak;
}

function isPlayedToday(history) {
  const todayStart = getTodayStart();
  return history.some(r => getPlayedAtDate(r) >= todayStart);
}

function daysSinceLastPlay(history) {
  if (history.length === 0) return Infinity;
  const last = getPlayedAtDate(history[0]);
  const lastDay = new Date(last);
  lastDay.setHours(0, 0, 0, 0);
  const diffMs = getTodayStart() - lastDay;
  return Math.floor(diffMs / (24 * 60 * 60 * 1000));
}

// ===== 今日のローテーション =====
function getTodayRotationGame(settings) {
  const enabledIds = settings.rotation.filter(id => settings.rotationEnabled[id]);
  if (enabledIds.length === 0) return GAMES[0];
  const day = new Date().getDay(); // 0=Sun ... 6=Sat
  const monIndex = day === 0 ? 6 : day - 1; // Mon=0, Sun=6
  const id = enabledIds[monIndex % enabledIds.length];
  return GAMES.find(g => g.id === id) || GAMES[0];
}

// ===== 動的コピー =====
function buildDynamicCopy(state) {
  const { isFirstTime, playedToday, thisWeekCount, weeklyGoal, weekStreak, daysAway } = state;
  if (isFirstTime) {
    return "ようこそ。まず1つだけ、約1分で終わります。";
  }
  if (playedToday && thisWeekCount >= weeklyGoal) {
    return "今週の目標達成！ おつかれさまでした。";
  }
  if (playedToday) {
    return `今日もおつかれさまでした。残り${weeklyGoal - thisWeekCount}回でゴールです。`;
  }
  if (daysAway >= 3) {
    return "おかえりなさい。今日からまた、気軽に再開しましょう。";
  }
  if (weekStreak >= 2) {
    return `${weekStreak}週連続中。今日も1分だけ、続けましょう。`;
  }
  if (thisWeekCount > 0) {
    return `今週はあと${weeklyGoal - thisWeekCount}回。コツコツ進みましょう。`;
  }
  return "今日も1分だけ、はじめましょう。";
}

// ===== ヘッダーのユーザー情報 =====
function renderUser(user) {
  const el = document.getElementById("user-email");
  if (el) el.textContent = user.email || "--";
}

// ===== ヒーロー描画 =====
function renderHero(history, settings) {
  const game = getTodayRotationGame(settings);
  const weekStart = getMondayStart();
  const thisWeekCount = countPlaysInWeek(history, weekStart);
  const weekStreak = calcWeekStreak(history, settings.weeklyGoal);
  const playedToday = isPlayedToday(history);
  const daysAway = daysSinceLastPlay(history);
  const isFirstTime = history.length === 0;

  // 週カウント
  document.getElementById("week-count").textContent = Math.min(thisWeekCount, settings.weeklyGoal);
  document.getElementById("week-goal").textContent = settings.weeklyGoal;

  // 達成済みなら炎を強調
  const streakEl = document.getElementById("hero-streak");
  streakEl.classList.toggle("achieved", thisWeekCount >= settings.weeklyGoal);

  // 連続週数バッジ
  const weekStreakEl = document.getElementById("hero-streak-week");
  if (weekStreak >= 2) {
    weekStreakEl.style.display = "";
    document.getElementById("streak-weeks").textContent = weekStreak;
  } else {
    weekStreakEl.style.display = "none";
  }

  // 動的コピー
  document.getElementById("hero-copy").textContent = buildDynamicCopy({
    isFirstTime, playedToday, thisWeekCount,
    weeklyGoal: settings.weeklyGoal, weekStreak, daysAway,
  });

  // 今日のゲーム
  document.getElementById("hero-game-dot").style.background = game.color;
  document.getElementById("hero-game-name").textContent = game.name;

  // CTA色
  const startBtn = document.getElementById("hero-start-btn");
  startBtn.style.background = game.color;
  startBtn.style.color = ["#06b6d4", "#f97316", "#ec4899"].includes(game.color) ? "#fff" : "#fff";
  startBtn.onclick = () => { window.location.href = game.file; };
}

// ===== 簡素化グリッド =====
function renderGamesGrid(history) {
  const el = document.getElementById("games-grid");
  if (!el) return;
  el.innerHTML = GAMES.map(game => {
    const scores = history.filter(r => r.gameName === game.name).map(r => r.score);
    const best = scores.length > 0 ? Math.max(...scores) : null;
    return `
      <div class="game-card-simple" style="border-color:${game.color}33;">
        <div class="game-card-simple-main">
          <div class="game-dot-lg" style="background:${game.color}"></div>
          <div class="game-card-simple-name">${game.name}</div>
        </div>
        <div class="game-card-simple-meta">
          <div class="best-score-simple">ベスト ${best !== null ? best.toLocaleString() : "--"}</div>
          <button class="play-btn-simple" style="background:${game.color};color:#fff;" onclick="location.href='${game.file}'">▶ 開始</button>
        </div>
      </div>
    `;
  }).join("");
}

// ===== 折りたたみトグル =====
function initHeroToggle() {
  const btn = document.getElementById("hero-toggle");
  const section = document.getElementById("games-section");
  btn.addEventListener("click", () => {
    const open = !section.hasAttribute("hidden");
    if (open) {
      section.setAttribute("hidden", "");
      btn.setAttribute("aria-expanded", "false");
      btn.querySelector(".toggle-arrow").textContent = "▼";
    } else {
      section.removeAttribute("hidden");
      btn.setAttribute("aria-expanded", "true");
      btn.querySelector(".toggle-arrow").textContent = "▲";
      section.scrollIntoView({ behavior: "smooth", block: "start" });
    }
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
    renderAll(cachedHistory, currentSettings);
  } catch (err) {
    showError("削除に失敗しました。ネットワーク接続を確認してください。");
  } finally {
    hideLoading();
  }
}

// ===== まとめて描画 =====
function renderAll(history, settings) {
  renderHero(history, settings);
  renderGamesGrid(history);
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

// ===== 設定モーダル =====
function openSettingsModal() {
  draftSettings = JSON.parse(JSON.stringify(currentSettings));
  renderGoalPicker();
  renderRotationList();
  document.getElementById("notification-time").value = draftSettings.notificationTime || "20:00";
  document.getElementById("settings-modal").removeAttribute("hidden");
}

function closeSettingsModal() {
  document.getElementById("settings-modal").setAttribute("hidden", "");
  draftSettings = null;
}

function renderGoalPicker() {
  const el = document.getElementById("goal-picker");
  el.innerHTML = [1,2,3,4,5,6,7].map(n => `
    <button class="goal-btn ${draftSettings.weeklyGoal === n ? "active" : ""}" data-goal="${n}">${n}回</button>
  `).join("");
  el.querySelectorAll(".goal-btn").forEach(btn => {
    btn.addEventListener("click", () => {
      draftSettings.weeklyGoal = parseInt(btn.dataset.goal, 10);
      renderGoalPicker();
    });
  });
}

function renderRotationList() {
  const el = document.getElementById("rotation-list");
  el.innerHTML = draftSettings.rotation.map((id, idx) => {
    const game = GAMES.find(g => g.id === id);
    if (!game) return "";
    const enabled = draftSettings.rotationEnabled[id];
    return `
      <li class="rotation-item ${enabled ? "" : "disabled"}" draggable="true" data-id="${id}" data-index="${idx}">
        <div class="drag-handle" aria-hidden="true">⠿</div>
        <div class="rotation-dot" style="background:${game.color}"></div>
        <div class="rotation-name">${game.name}</div>
        <label class="rotation-toggle">
          <input type="checkbox" data-id="${id}" ${enabled ? "checked" : ""}>
          <span class="toggle-slider"></span>
        </label>
      </li>
    `;
  }).join("");

  // トグル
  el.querySelectorAll('input[type="checkbox"]').forEach(input => {
    input.addEventListener("change", () => {
      draftSettings.rotationEnabled[input.dataset.id] = input.checked;
      renderRotationList();
    });
  });

  // ドラッグ&ドロップ
  let dragSrcId = null;
  el.querySelectorAll(".rotation-item").forEach(item => {
    item.addEventListener("dragstart", e => {
      dragSrcId = item.dataset.id;
      item.classList.add("dragging");
      e.dataTransfer.effectAllowed = "move";
      e.dataTransfer.setData("text/plain", dragSrcId);
    });
    item.addEventListener("dragend", () => {
      item.classList.remove("dragging");
      el.querySelectorAll(".rotation-item").forEach(i => i.classList.remove("drag-over"));
    });
    item.addEventListener("dragover", e => {
      e.preventDefault();
      e.dataTransfer.dropEffect = "move";
      if (item.dataset.id !== dragSrcId) item.classList.add("drag-over");
    });
    item.addEventListener("dragleave", () => {
      item.classList.remove("drag-over");
    });
    item.addEventListener("drop", e => {
      e.preventDefault();
      const targetId = item.dataset.id;
      if (!dragSrcId || dragSrcId === targetId) return;
      const arr = draftSettings.rotation;
      const fromIdx = arr.indexOf(dragSrcId);
      const toIdx = arr.indexOf(targetId);
      if (fromIdx < 0 || toIdx < 0) return;
      arr.splice(fromIdx, 1);
      arr.splice(toIdx, 0, dragSrcId);
      renderRotationList();
    });
  });
}

async function saveSettingsAndClose() {
  draftSettings.notificationTime = document.getElementById("notification-time").value || "20:00";
  currentSettings = normalizeSettings(draftSettings);
  saveSettingsToCache(currentSettings);
  const uid = auth.currentUser?.uid;
  if (uid) {
    await persistSettings(uid, currentSettings);
  }
  closeSettingsModal();
  renderAll(cachedHistory, currentSettings);
}

function initSettingsUI() {
  document.getElementById("settings-btn").addEventListener("click", openSettingsModal);
  document.getElementById("settings-close").addEventListener("click", closeSettingsModal);
  document.getElementById("settings-cancel").addEventListener("click", closeSettingsModal);
  document.getElementById("settings-save").addEventListener("click", saveSettingsAndClose);
  // オーバーレイクリックで閉じる
  document.getElementById("settings-modal").addEventListener("click", e => {
    if (e.target.id === "settings-modal") closeSettingsModal();
  });
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
  initHeroToggle();
  initSettingsUI();
  showLoading();

  // localStorageキャッシュから先にロード
  const cached = loadSettingsFromCache();
  if (cached) currentSettings = cached;

  if (typeof auth === "undefined") {
    showLoadingError("Firebaseの読み込みに失敗しました。\nネットワーク接続を確認してください。");
    return;
  }

  const authTimeout = setTimeout(() => {
    showLoadingError("接続がタイムアウトしました。\nネットワーク接続を確認してください。");
  }, 8000);

  auth.onAuthStateChanged(async user => {
    clearTimeout(authTimeout);

    if (!user) {
      window.location.href = "login.html";
      return;
    }

    renderUser(user);

    try {
      const [history, remoteSettings] = await Promise.all([
        fetchHistory(user.uid),
        fetchSettings(user.uid),
      ]);
      cachedHistory = history;
      if (remoteSettings) {
        currentSettings = remoteSettings;
        saveSettingsToCache(currentSettings);
      }
      renderAll(cachedHistory, currentSettings);
    } catch (err) {
      console.error(err);
      showError("データの読み込みに失敗しました。ネットワーク接続を確認してください。");
    } finally {
      hideLoading();
    }
  });
});
