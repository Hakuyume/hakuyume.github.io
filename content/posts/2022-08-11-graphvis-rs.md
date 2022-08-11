---
title: "c2rustでgraphvizをRust化しようとしたら上手くいかなかった話"
date: 2022-08-11
draft: false
tags: ["rust"]
---

graphviz[^graphviz]をRustから叩きたくなったのでそれっぽいcrateを探したところ。FFIでgraphvizを叩いているものしか見つからなかった。せっかくなのでc2rust[^c2rust]でpure Rust化してみる。

## 準備
ソースをとってくる。
```shell
$ curl -LO https://gitlab.com/api/v4/projects/4207231/packages/generic/graphviz-releases/5.0.0/graphviz-5.0.0.tar.gz
$ tar -xf graphviz-5.0.0.tar.gz
```

c2rustを使うために`compile_commands.json`を生成する必要がある。c2rustのREADMEにいろいろやり方が載っているが導入済みだったintercept-buildを選んだ。`./configure`は本当はちゃんとオプション設定しないとマズそうだが、とりあえずデフォルトの設定を使う。
```shell
$ cd ./graphviz-5.0.0/
& ./configure
$ intercept-build make
```

## c2rust
`v0.16.0`を使った。大量にメッセージが出る (後述)。
```shell
$ c2rust transpile compile_commands.json
```

## cargo project化
c2rustは`*.c`を`*.rs`に変換してくれるだけなので、そのままではcargoで扱えない。
いい感じに整えてcargo project化する。

全体を`src`にrename。
```shell
$ cd ..
$ mv graphviz-5.0.0 src
```

`*.rs`以外のファイルを削除 (空ディレクトリも消える)。
```shell
$ find src/ -depth -not -name '*.rs' -delete
```

`lib`と`split.q`がRustのmodule名として不適切なので適当にrename。
```shell
$ mv src/lib src/lib_
$ mv src/lib_/label/split.q.rs src/lib_/label/split_q.rs
```

各ディレクトリに`mod.rs`を配置し、全部の`*.rs`が`lib.rs`から参照されるようにする。
```shell
$ find src/ | while read SRC; do echo "pub mod $(basename ${SRC%.rs});" >> $(dirname ${SRC})/mod.rs; done
$ rm mod.rs
$ mv src/mod.rs src/lib.rs
```

cargo projectを初期化。どうせnightlyじゃないとbuildできないので`rust-toolchain`を設定しておく。
```shell
$ cargo init --lib
$ echo nightly-2022-08-11 > rust-toolchain
```

これでとりあえず`cargo build`ができるようになる (6315 errors…)。
```shell
$ cargo build
...
error: could not compile `graphviz-rs` due to 6315 previous errors; 1035 warnings emitted
```

## 修正作業
大量のエラーを潰していく。

必要なcrateを追加する。また`#[derive(BitfieldStruct)]`を`#[derive(::c2rust_bitfields::BitfieldStruct)]`で置き換える。
```shell
$ cargo add c2rust-bitfields@0.3 f128@0.2 libc@0.2 num-traits@0.2
$ find src/ -name '*.rs' | xargs -I{} sed s/BitfieldStruct/::c2rust_bitfields::BitfieldStruct/g -i {}
$ cargo build
...
error: could not compile `graphviz-rs` due to 1727 previous errors; 1035 warnings emitted
```

unstable featureを有効にする。c2rustが生成したファイルには既に`#[feature(...)]`が含まれているが、crateのtop levelに書かないと効果がない。
```shell
$ sed '1i #![feature(c_variadic, extern_types, label_break_value, register_tool)]' -i src/lib.rs
$ cargo build
...
error: could not compile `graphviz-rs` due to 14 previous errors; 1035 warnings emitted
```

lifetime paramater周りで指定が間違っている部分を修正 ([fcbe39d](https://github.com/Hakuyume/graphviz-rs/commit/fcbe39d00f84c968c90cdfe4c012fa6a6311127d))｡
```shell
$ cargo build
...
error: could not compile `graphviz-rs` due to 6 previous errors; 1035 warnings emitted
```

`Copy` traitをderiveしようとして怒られている部分を修正 ([59df350](https://github.com/Hakuyume/graphviz-rs/commit/59df3500aff7857d19ac982deb32d9d6029ee474))｡
`Clone` traitをderiveしてなくて怒られている部分を修正 ([bd9a662](https://github.com/Hakuyume/graphviz-rs/commit/bd9a662b068f6e0477aed2828025d5f0709c5175))。
```shell
$ cargo build
...
error: could not compile `graphviz-rs` due to 6 previous errors; 1056 warnings emitted
```

かなり減らせたが、`sffmtpos`がないというエラーが残っている。
```shell
error[E0425]: cannot find value `sffmtpos` in this scope
   --> src/lib_/sfio/sftable.rs:537:17
    |
537 |                 sffmtpos
    |                 ^^^^^^^^ not found in this scope
```

[sftable.c](https://gitlab.com/graphviz/graphviz/-/blob/5.0.0/lib/sfio/sftable.c#L28)を確認すると`sffmtpos`は定義されている 。
`sftable.rs`になぜ反映されてないのかと不思議に思い、c2rustの大量のメッセージを再確認したところ次のエラーが出ていた。
```shell
Transpiling sftable.c
error: Failed to translate sffmtpos: Unsupported va_copy
```
うーん。


## 参考
[^graphviz]: https://graphviz.org/
[^c2rust]: https://c2rust.com/
