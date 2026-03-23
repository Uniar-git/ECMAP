// ============================================================
//  firebase-config.example.js  ← これはサンプルファイルです
//
//  使い方:
//  1. このファイルを firebase-config.js という名前でコピーする
//  2. Firebaseコンソールで取得した値を下記に貼り付ける
//  3. firebase-config.js は .gitignore により git 管理対象外です
// ============================================================

const firebaseConfig = {
  apiKey:            "YOUR_API_KEY",
  authDomain:        "YOUR_PROJECT_ID.firebaseapp.com",
  projectId:         "YOUR_PROJECT_ID",
  storageBucket:     "YOUR_PROJECT_ID.appspot.com",
  messagingSenderId: "YOUR_SENDER_ID",
  appId:             "YOUR_APP_ID"
};

firebase.initializeApp(firebaseConfig);

const db   = firebase.firestore();
const auth = firebase.auth();

const authReady = auth.signInAnonymously()
  .then(credential => credential.user.uid)
  .catch(err => {
    console.error("Firebase匿名ログインに失敗しました:", err);
    return null;
  });
