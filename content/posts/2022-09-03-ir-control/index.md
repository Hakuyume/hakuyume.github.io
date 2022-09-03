---
title: "ADIR01Pでシーリングライトを操作する"
date: 2022-09-03
draft: false
tags: ["rust", "react"]
---

流行のスマートハウスを目指して自宅のシーリングライトをネットワーク経由で操作できるようにした。

## デバイス選定

自宅のシーリングライトは付属の赤外線リモコンで操作できる。
赤外線を出力するためのハードウェアは既製品を使うことにした。

選定基準は以下の4つ。
- 送信するメッセージを自由にカスタマイズできる
- (USB接続の場合) Linux対応している
- APIが公開されている
- 外部サーバーに依存しない

調査の結果以下の3つが候補になった。
- Nature Remo[^nature-remo]
    - Wi-Fi接続
    - UIつき
    - 基本的に外部サーバー経由で使う。
    - 外部サーバー障害時のためのローカルモードがあり、その通信プロトコルも公開されている。
- RS-WFIREX4[^rs-wfirex4]
    - Wi-Fi接続
    - UIつき
    - ローカルモードがある。
    - 通信プロトコルは野良の解析記事[^gcd-rs-wfirex4]がある。
- ADIR01P[^adir01p]
    - USB接続
    - ユーザーが自分でプログラムを書く前提の製品。
    - HIDデバイスとして認識されるのでLinuxでもいけそう。
    - 公式でWindows向けのライブラリがある。

余計な機能がなく一番遊べそうなADIR01Pに決定。

## ライブラリ実装
ADIR01Pは制御用のDLLをGitHub[^github-adir01p]に公開してくれているのでそれを参考に…しようと思ったがなんとビルド済みのDLLをzipに固めて置いてあった。gitとは一体…。

調べたら野良のC実装[^naohirotamura]が見つかったので、こちらを参考にした。
READMEによると公式のC#実装を移植したとのことだが、公式のGitHubからはC#のソースを発見できなかった。

Cのコードを愚直に移植してRustライブラリを書いた(https://github.com/Hakuyume/adir01p-rs)。

## 赤外線フォーマット解析

手持ちのリモコン (LEDHCL-R1) の赤外線フォーマットを解析する。
ADIR01Pの赤外線受信機能を使ってdumpした「電源」ボタンの出力は以下の通り。
`(1T)`や`(3T)`は最頻値を`T`として推定した値。
```
on = 79 (4T), off = 42 (2T)
on = 217 (11T), off = 42 (2T)
on = 59 (3T), off = 21 (1T)
on = 20 (1T), off = 22 (1T)
...
on = 59 (3T), off = 22 (1T)
on = 20 (1T), off = 21 (1T)
on = 20 (1T), off = 358 (18T)
on = 217 (11T), off = 41 (2T)
on = 60 (3T), off = 22 (1T)
on = 20 (1T), off = 21 (1T)
...
on = 60 (3T), off = 21 (1T)
on = 20 (1T), off = 22 (1T)
on = 19 (1T), off = 358 (18T)
on = 217 (11T), off = 42 (2T)
on = 59 (3T), off = 22 (1T)
on = 19 (1T), off = 23 (1T)
...
on = 17 (1T), off = 25 (1T)
on = 16 (1T), off = 26 (1T)
on = 16 (1T), off = 7693 (385T)
```

眺めると同じパターンの繰り返しになっている。
おそらく`11T/2T`が開始bit、`1T/18T`が終了bitで、その間の`1T/1T`と`3T/1T`がデータbitのはず。
解説記事[^ir-format]によるとNEC, AEHA, SONYの3種類の代表的なフォーマットが存在し、
それぞれ`1T/3T`, `1T/3T`, `2T/1T`で`1`を表現しているらしい。
`3T/1T`はどのフォーマットにも当てはまらないのでアイリスオーヤマ独自のフォーマットのよう。
`1T/1T` -> `0`, `3T/1T` -> `1`と仮定すると各メッセージは以下のようになる。
```
電源 (CH1)
10000000 10001000 00000000 00000000 01010010
調光 (CH1)
10000000 10000100 00000000 00000000 01011110
常夜灯 (CH1)
10000000 10000010 00000000 00000000 01011000
電源 (CH2)
10000000 00001000 00000000 00000000 11010010
調光 (CH2)
10000000 00000100 00000000 00000000 11011110
```

どれも40bitsで、その内訳はおそらく以下の通り。
- 0-7: `10000000` (固定)
- 8-11: `1000` (CH1) | `0000` (CH2)
- 12-15: `1000` (電源) | `0100` (調光) | `0010` (常夜灯)
- 16-31：未使用?
- 32-39: チェックサム

チェックサムの計算方法を調べたかったが適当なCRCをかけても一致しなかったので謎。
とりあえずリモコンを模倣するだけならチェックサムも含めて丸ごと真似すればいいのでよしとする。

## サービス化

スマホから叩けるようにしたいのでWeb UIを実装する。

### バックエンド
バックエンドはaxum[^axum]を利用し、POSTで叩くと各種メッセージが送信されるようにした。
死活監視用のhealthz APIではADIR01Pのfirmware versionを取得するようにして、デバイスの切断を検知できるようにした。
```rust
async fn healthz(
    Extension(device): Extension<Arc<Mutex<Device<GlobalContext>>>>,
) -> Result<(), StatusCode> {
    tokio::task::spawn_blocking(move || {
        let mut device = device.lock().map_err(|e| {
            tracing::error!("{}", e);
            StatusCode::SERVICE_UNAVAILABLE
        })?;
        device.firmware_version().map_err(|e| {
            tracing::error!("{}", e);
            StatusCode::SERVICE_UNAVAILABLE
        })?;
        Ok(())
    })
    .await
    .unwrap()
}
```

### フロントエンド
フロントエンドはVite[^vite]+React[^react]+MUI[^mui]で実装した。
リモコン自体は状態を持たないので、単にボタンが押されたらPOSTを叩くだけ。
```tsx
function App() {
  return (
    <Box>
      <AppBar position="static">
        <Toolbar>caeda</Toolbar>
      </AppBar>
      <Card>
        <CardHeader title="照明 (居室)" />
        <Container>
          <Grid container spacing={2}>
            {[
              ["電源", "power"],
              ["調光", "dimming"],
              ["常夜灯", "night-light"],
            ].map(([name, path]) => (
              <Grid item xs={4}>
                <Button
                  fullWidth={true}
                  variant="outlined"
                  onClick={() =>
                    fetch(`/api/ledhci-r1/ch1/${path}`, {
                      method: "POST",
                    })
                  }
                >
                  {name}
                </Button>
              </Grid>
            ))}
          </Grid>
        </Container>
      </Card>
    </Box>
  );
}
```

よさそう。
{{< figure src="00.webp" >}}

## おまけ
シーリングライトの状態遷移図
{{< figure src="01.svg" >}}

## 参考
[^nature-remo]: https://nature.global/nature-remo/
[^rs-wfirex4]: https://iot.ratocsystems.com/products/rs-wfirex4/
[^gcd-rs-wfirex4]: https://www.gcd.org/blog/2020/09/1357/
[^adir01p]: https://bit-trade-one.co.jp/product/module/adir01p/
[^github-adir01p]: https://github.com/bit-trade-one/ADIR01P-USB_IR_Remote_Controller_Advance
[^naohirotamura]: https://github.com/NaohiroTamura/bto_advanced_USBIR_cmd
[^ir-format]: http://elm-chan.org/docs/ir_format.html
[^axum]: https://docs.rs/axum/latest/axum/
[^react]: https://reactjs.org/
[^vite]: https://vitejs.dev/
[^mui]: https://mui.com/
