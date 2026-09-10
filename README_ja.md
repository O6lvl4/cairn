<p align="center">
  <img src="docs/images/cairn.png" alt="黒い岩の隙間から金色の光が輝く、石の守り手 Cairn" width="400">
</p>

<h1 align="center">cairn</h1>
<p align="center"><strong>まず観察する。確かめながら作る。</strong></p>
<p align="center">Almide 製のコーディングエージェント。<br>プロジェクトを読み、編集し、テストで確かめる。</p>
<p align="center">
  <a href="https://github.com/O6lvl4/cairn/actions/workflows/quality.yml"><img src="https://github.com/O6lvl4/cairn/actions/workflows/quality.yml/badge.svg" alt="品質検証 CI"></a>
  · <a href="README.md">English</a>
  · <a href="#使い始める">使い始める</a>
  · <a href="docs/quality-plan.md">品質改善の計画</a>
</p>

cairn は、リポジトリにある事実を手がかりに動きます。ソースファイル、プロジェクトの設定、
コンパイラの診断、テスト結果を読み、必要なファイルを選び、編集を提案します。
利用できるツールで構文を確認してから書き込み、検証コマンドをもう一度実行します。

[Almide](https://github.com/almide/almide) で作られた、単一のネイティブバイナリです。
任意の連携ツールを加えると、構文木、構造を意識した読み取り、長い失敗ログの要約を使えます。

## 使い始める

Almide をインストールした環境で、このリポジトリをビルドします。

```sh
almide build
./cairn observe --root ../project
```

`observe` はモデルを呼ばずにプロジェクトを調べ、検証コマンドを実行します。
編集するには、環境変数か対象プロジェクトの `.env` に `CLOUDFLARE_ACCOUNT_ID` と
`CLOUDFLARE_API_TOKEN` を設定し、タスクを渡します。

```sh
./cairn solve "clamp が範囲外の値で失敗する問題を直す" \
  --root ../project --verify "cargo test" --attempts 6
```

`--verify` はプロジェクトに合わせて指定してください。その終了コードが成功を決めます。
オプションは `./cairn help`、モデルを 1 回呼んで認証を確認するには `./cairn llm-test` を使います。

`cairn polish` は、検証コマンドが**既に通っている**プロジェクトに対して、同じ振る舞いを
より単純に書き直すよう求めます。通らなくなった場合は、通っていた版に巻き戻します。

```sh
./cairn polish --root ../project --verify "cargo test"
```

## 観察から、検証済みの編集へ

1. **観察する。** プロジェクトとファイル一覧を調べ、利用できればリポジトリ地図を作り、
   現在の検証結果を集めます。
2. **読む。** 必要なファイルを選びます。小さなプロジェクトでは、ファイル選択のために
   モデルを呼ばず、全体を読めます。
3. **編集する。** 完全なファイルをモデルに求め、設定された、または利用可能なチェッカで
   一つずつ構文を確認してから書き込みます。
4. **確かめる。** 検証コマンドを再実行します。まだ修正が必要なら、結果、実際の差分、
   拒否された編集を次の試行に渡します。

コンパイラ自身の説明も診断の理解に使います。同じ失敗が続けば別の方法を促し、
使えない応答が返った場合は推論量やモデルを段階的に変えます。

## 小さな道具を組み合わせる

| ツール | cairn に加わる機能 |
|---|---|
| [gramide](https://github.com/O6lvl4/gramide) | Almide・Go・Rust の構文チェックと、順位付きリポジトリ地図 |
| [hew](https://github.com/O6lvl4/hew) | 元の本文を保つ上限付き読み取りと、パーサを使ったシンボル一覧 |
| [ctxgate](https://github.com/O6lvl4/ctxgate) | 長い検証ログから失敗の要点をまとめる機能 |

連携ツールは個別にインストールし、`PATH` に置きます。利用できる場合に使い、
無ければ組み込みの処理に切り替えます。

## 言語リファレンス

初見の言語を書くモデルは構文を推測し、その推測が高くつきます。このプロジェクトでの実測では、
失敗した attempt は**すべてコンパイルエラー**で、答えを間違えたものは一度もありませんでした。
そこで cairn はリファレンスを探して見せます。順序は固定で、どれが答えたかは実行時に出力されます。

| 段 | どこから |
|---|---|
| 1 | `CAIRN_REFERENCE_<LANGUAGE>=/path/to/notes.md`(`=off` で「無し」を指定) |
| 2 | プロジェクトが持つもの — `CHEATSHEET.md`、`docs/CHEATSHEET.md` |
| 3 | ツールチェーンが印刷するもの — Almide なら `almide ide stdlib-snapshot` |

段 3 は設定不要です。リファレンスの無い言語には無いままで、あるふりはせず「無い」と言います。
48 KB を超えるものは切り詰め、切り詰めたことをラベルに書きます。

## 遅いリクエスト

リクエストはヘッジされることがあります。`CAIRN_HEDGE_MS`(既定 120000)以内に応答が無ければ
同一のリクエストをもう 1 本立て、先に着いた方を使います。実行結果には**ヘッジした回数と
ヘッジが実際に勝った回数**の両方が出ます。勝てないヘッジは、金を払って捨てた 2 本目でしかないからです。

`CAIRN_CALL_MAX_MS`(既定 360000)は 1 リクエストの実時間上限です。アイドル判定では
最も高くつく失敗を捕まえられません — **喋り続けるモデルは決してアイドルになりません**。
実測では 1 本の呼び出しが 12 分かけて 1.7 MB を流し続け、手で止めるまで終わりませんでした。
上限を超えたリクエストは放棄され、次の attempt はより短く要求されます。

## 書き込む前の構文チェック

`CAIRN_CHECK_<EXT>` で拡張子ごとのチェッカを指定できます。未指定の場合は次の順で選びます。

| 言語 | チェック |
|---|---|
| Almide, Go | gramide。無ければ `almide check` / `gofmt -e` |
| Rust | gramide。無ければ `rustfmt --edition 2024 --emit stdout` |
| Python, Ruby, JavaScript, PHP, Lua, shell, JSON, TOML | 各言語向けのツール |
| Java, C++, C, C#, Kotlin, Scala, Swift, TypeScript | `gramide balance` による括弧・リテラルのチェック |

確認できる範囲はチェッカによって異なります。括弧の対応確認は限定的なチェックで、
構文が通ることもプログラムの正しさを保証しません。利用できないチェックは報告し、
最終的な判断にはプロジェクトの検証コマンドを使います。

## 測りながら進める

リポジトリの過去の Almide 演習結果は **23 問中 23 問、$0.19**。
`cf:glm-5.3-flash` に言語のチートシートを渡し、各課題で最大 6 回試行した記録です。
小規模な開発用ベンチマークであり、一般的な修復成功率や世界順位を示すものではありません。
モデルが学習時に課題を見たかどうかは不明です。

[品質改善の計画](docs/quality-plan.md) では、独立に検証した修復成功率、総費用と時間、
構文判定の精度、必要なコードを取り出す精度を比較対象にしています。
[Almide ベンチ](bench/almide.sh) は `BENCH_CHECK_ONLY=1` でモデルを呼ばずに検証でき、
[多言語ベンチ](bench/exercism.sh) も用意しています。

## 開発

```sh
almide test
bash ci/check.sh       # テスト・ビルド・CLI 検証。モデル呼び出しなし
```

CI ではコンパイラと Rust のバージョンを固定しています。[検証手順](ci/README.md)も参照してください。

| ソース | 役割 |
|---|---|
| `src/main.almd` | コマンド、オプション、認証情報 |
| `src/observe.almd` | プロジェクトの観察と検証コマンド |
| `src/solve.almd` | ファイル選択と編集・検証ループ |
| `src/gate.almd` | 書き込み前の構文チェック |
| `src/reference.almd` | モデルに見せる言語リファレンス |
| `src/explain.almd` | コンパイラ診断の説明 |
| `src/ask.almd` | 構造化したモデルへの問いと再試行 |
| `src/llm.almd` | Workers AI のストリーミングと費用集計 |

## ライセンス

[MIT](LICENSE-MIT) または [Apache-2.0](LICENSE-APACHE) を選べます。

読み取りは必要に応じて 24,000 文字から最大 96,000 文字まで拡張します。
それでも読み切れないファイルは参照専用とし、全体を置換する編集を拒否します。

Cairn は `gramide languages` の登録情報から `check` 機能を持つ言語を検出します。
読み取り専用パッケージは構文ゲートに使いません。プロジェクトの明示設定が優先され、
既存の代替チェッカーも利用できます。
