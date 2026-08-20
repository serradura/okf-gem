---
type: 概念
title: 日本語のタイトル
description: 全角文字だけで書かれた説明文。一文字が二列を占めるため、文字数と表示幅が一致しない。
tags: [全角, wide]
timestamp: 2026-07-18
---

# 概要

この概念の本文は全角文字で書かれている。日本語の文字は一文字あたり二列を占め
るので、`String#length` で数えた長さは画面上の幅の半分になる。レイアウトが文字
数で計算していれば、この行を含む枠は必ず崩れる。

見出しも表も同じ問題を持つ:

| 項目 | 説明 |
|------|------|
| 全角 | 二列 |
| 半角 | 一列 |

# 混在

Mixed text — 日本語 and ASCII in one line — is the harder case, because the
column count is neither the character count nor twice it.
