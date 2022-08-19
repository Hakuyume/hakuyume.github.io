---
title: "c2rustでgraphvizをRust化しようとしたら上手くいかなかった話 (2)"
date: 2022-08-19
draft: false
tags: ["rust"]
---

前回[^graphviz-rs-1]graphviz[^graphviz]の`sffmtpos`がc2rust[^c2rust]で変換できないことがわかった。

## c2rustの調査

c2rustのリポジトリでエラーメッセージを検索すると次のコードが見つかる。

[builtins.rs#L278-L295](https://github.com/immunant/c2rust/blob/34904d7ed1749e1688c047a9a614f3941437030e/c2rust-transpile/src/translator/builtins.rs#L278-L295)
```rust
            "__builtin_va_copy" => {
                if ctx.is_unused() && args.len() == 2 {
                    if let Some((_dst_va_id, _src_va_id)) = self.match_vacopy(args[0], args[1]) {
                        let dst = self.convert_expr(ctx.expect_valistimpl().used(), args[0])?;
                        let src = self.convert_expr(ctx.expect_valistimpl().used(), args[1])?;

                        let call_expr = mk().method_call_expr(src.to_expr(), "clone", vec![]);
                        let assign_expr = mk().assign_expr(dst.to_expr(), call_expr);
                        let stmt = mk().semi_stmt(assign_expr);

                        return Ok(WithStmts::new(
                            vec![stmt],
                            self.panic_or_err("va_copy stub"),
                        ));
                    }
                }
                Err(TranslationError::generic("Unsupported va_copy"))
            }
```

`self.match_vacopy(args[0], args[1])`が`None`のときに`Err`になりそうなので、`Translation::va_copy`の実装を確認。

[variadic.rs#L77-L84](https://github.com/immunant/c2rust/blob/34904d7ed1749e1688c047a9a614f3941437030e/c2rust-transpile/src/translator/variadic.rs#L77-L84)
```rust
    pub fn match_vacopy(&self, dst_expr: CExprId, src_expr: CExprId) -> Option<(CDeclId, CDeclId)> {
        let dst_id = self.match_vastart(dst_expr);
        let src_id = self.match_vastart(src_expr);
        if let (Some(did), Some(sid)) = (dst_id, src_id) {
            return Some((did, sid));
        }
        None
    }
```

`va_copy`の2つの引数をそれぞれ`Translation::match_vastart`で処理している。両方とも`Some`を返さないと変換に失敗する。

[variadic.rs#L36-L71](https://github.com/immunant/c2rust/blob/34904d7ed1749e1688c047a9a614f3941437030e/c2rust-transpile/src/translator/variadic.rs#L36-L71)
```rust
    pub fn match_vastart(&self, expr: CExprId) -> Option<CDeclId> {
        // struct-based va_list (e.g. x86_64)
        fn match_vastart_struct(ast_context: &TypedAstContext, expr: CExprId) -> Option<CDeclId> {
            match_or! { [ast_context[expr].kind]
            CExprKind::ImplicitCast(_, e, _, _, _) => e }
            match_or! { [ast_context[e].kind]
            CExprKind::DeclRef(_, va_id, _) => va_id }
            Some(va_id)
        }

        // struct-based va_list (e.g. x86_64) where va_list is accessed as a struct member
        // supporting this pattern is necessary to transpile apache httpd
        fn match_vastart_struct_member(
            ast_context: &TypedAstContext,
            expr: CExprId,
        ) -> Option<CDeclId> {
            match_or! { [ast_context[expr].kind]
            CExprKind::ImplicitCast(_, me, _, _, _) => me }
            match_or! { [ast_context[me].kind]
            CExprKind::Member(_, e, _, _, _) => e }
            match_or! { [ast_context[e].kind]
            CExprKind::DeclRef(_, va_id, _) => va_id }
            Some(va_id)
        }

        // char pointer-based va_list (e.g. x86)
        fn match_vastart_pointer(ast_context: &TypedAstContext, expr: CExprId) -> Option<CDeclId> {
            match_or! { [ast_context[expr].kind]
            CExprKind::DeclRef(_, va_id, _) => va_id }
            Some(va_id)
        }

        match_vastart_struct(&self.ast_context, expr)
            .or_else(|| match_vastart_pointer(&self.ast_context, expr))
            .or_else(|| match_vastart_struct_member(&self.ast_context, expr))
    }
```

`Translation::match_vastart`の中身を見ると3つのパターンが用意されており、どれか1つにmatchしたら変換成功という処理になっている。
謎のmacroでわかりにくいが、`match_vastart_struct_member`が`a.args`という形式に対応する。残りの2つはおそらく`args`に対応している (未確認)。
問題の`sffmtpos`では[`ft->args`](https://gitlab.com/graphviz/graphviz/-/blob/5.0.0/lib/sfio/sftable.c#L321)が引数として渡されており、
`Translation::match_vastart`がmatchに失敗する。

## c2rustへのpatch

原因がわかったので[pull request](https://github.com/immunant/c2rust/pull/612)を送ってみた。
`match_vastart_struct_member`を参考に`match_vastart_struct_pointer_member`というパターンを追加して、`a->args`にmatchするように謎マクロを見様見真似で書いた。
かなりアドホックな実装だが、汎用的な書き方が難しそうということで無事mergeされた。

## いざ変換
c2rustを更新したのでtranspileしてみる。
前回大量に潰したエラーを再度潰すのは大変なので、`sftable.rs`のみを対象にした上で`sffmtpos`の箇所だけ残して他は前回の変換結果を使うことにした ([3f07f87](https://github.com/Hakuyume/graphviz-rs/commit/3f07f87708a6f8c2671c7544894f06ba63e82d6a))。

無事`sffmtpos`が変換できたのでbuildしてみる。
```shell
$ cargo build
...
error: could not compile `graphviz-rs` due to 8 previous errors; 1060 warnings emitted
```

あまり進んだ感じはしない。


## 修正作業
rustcのsuggest通りに直してみる ([365ad6f](https://github.com/Hakuyume/graphviz-rs/commit/365ad6f373a84bd59912fe529b6d1bfa8426a659), [e20151f](https://github.com/Hakuyume/graphviz-rs/commit/e20151f9f09ec91c88094fdd3797770eb7d96f87), [9e6f8cc](https://github.com/Hakuyume/graphviz-rs/commit/9e6f8cc56d4fbb256a999c5590d8d3a0736b79ba))。
```shell
$ cargo build
...
error: could not compile `graphviz-rs` due to 25 previous errors; 1608 warnings emitted
```
グエー

このエラーが大量に出ている。
```shell
error[E0015]: cannot call non-const fn `f128::new::<f64>` in statics
    --> src/lib_/sfio/sftable.rs:1017:17
     |
1017 |                 f128::f128::new(1e-32f64),
     |                 ^^^^^^^^^^^^^^^^^^^^^^^^^
     |
     = note: calls in statics are limited to constant functions, tuple structs and tuple variants
```

## 参考
[^graphviz-rs-1]: [{{< ref "2022-08-11-graphviz-rs.md" >}}]({{< ref "2022-08-11-graphviz-rs.md" >}})
[^graphviz]: https://graphviz.org/
[^c2rust]: https://c2rust.com/
