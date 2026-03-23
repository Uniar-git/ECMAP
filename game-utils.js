// ============================================================
//  game-utils.js
//  全ゲームHTMLから共通で使うユーティリティ。
//  ゲーム終了時に finishGame(gameName, score) を呼ぶだけでOK。
// ============================================================

/**
 * ゲーム終了処理。Firestoreにスコアを保存してホームに戻る。
 *
 * @param {string} gameName - ゲーム名（変えないこと）
 * @param {number} score    - スコア（数値のみ）
 */
async function finishGame(gameName, score) {
  const userId = await authReady;

  if (!userId) {
    console.error("ユーザーIDが取得できませんでした。オフラインか設定エラーの可能性があります。");
    window.location.href = "index.html";
    return;
  }

  const result = {
    gameId:    "eSports-Training",
    gameName:  gameName,
    score:     score,
    userId:    userId,
    playedAt:  firebase.firestore.FieldValue.serverTimestamp()
  };

  try {
    await db.collection("results").add(result);
  } catch (err) {
    console.error("スコアの保存に失敗しました:", err);
  }

  window.location.href = "index.html";
}
