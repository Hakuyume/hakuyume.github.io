---
title: "hyperでHTTP Connect clientを実装した話"
date: 2022-08-07
draft: false
tags: ["rust"]
---

proxyに対応していないソフトウェアをHTTP Connect[^mdn-http-connect]経由で外部のサーバに接続させないといけないことがあったのでRustで実装してみた。

通信の流れはこんな感じ  
client -(TCP)-> Rust製proxy -(HTTP/TCP)-> proxyサーバ (`proxy.example`) -(TCP)-> targetサーバ (`target.example:8080`)

## TCP serverの実装
ほぼtokioのexampleと変わらない。tower[^tower]系のcrateで抽象化ができないかと思ったが、HTTP (gRPC含む) しかできなさそうなので断念した。`tracing::Instrument::instrument`を使うといい感じにcontext (`peer_addr`) 付きでloggingできて便利。
```rust
use futures::TryFutureExt;
use std::net::Ipv4Addr;
use tokio::net::TcpListener;
use tracing::Instrument;

let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await?;
loop {
    let (mut stream, peer_addr) = listener.accept().await?;
    tokio::spawn(
        async move {
            tracing::info!("accept");
            // ...
        }
        .map_err(|e| tracing::error!("{}", e))
        .instrument(tracing::info_span!(
            "handler",
            peer_addr = peer_addr.to_string(),
        )),
    );
}
```

### proxyサーバへの接続
proxyサーバにHTTP Connectで接続し、targetサーバへの転送を要求する。ここで注意しないといけないのは`hyper::Client::request`はデフォルトの設定だと`Request`で指定されているhostにTCP接続を試みるということ。HTTP ConnectではproxyサーバにTCPの接続し、hostにはtargetを指定しないといけないのでこの挙動では問題がある[^hyper-2863]。hyperでは`Uri`から`TcpStream` (正確には`AsyncRead + AsyncWrite`) を返す`Service`をcustom connectorとして設定できるので、`Request`由来のuriは無視してproxyサーバへのTCPコネクションを返すような`Service`を実装すればよい。当初は愚直に自前でstructを定義しtrait実装をしていたが、`tower::util::MapRequest`を使うと既存の`HttpConnector`を流用できることに気づいたのでそうした。
```rust
use hyper::client::HttpConnector;
use hyper::{Body, Client, Request, Url};
use tower::util::MapRequest;

let client = Client::builder().build(
     MapRequest::new(HttpConnector::new(), move |_| Uri::from_static("http://proxy.example"))
);
// ...
loop {
    let (mut stream, peer_addr) = listener.accept().await?;
    let client = client.clone();
    tokio::spawn(
        async move {
            tracing::info!("accept");

            let request = Request::connect("target.example:8080").body(Body::empty())?;
            let response = client.request(request).await?;

            if response.status().is_success() {
                // ...
                Ok(())
            } else {
                Err(anyhow::format_err!("status code = {}", response.status()))
            }
        }
   );
```

### 通信のバイパス
clientとの接続およびproxyサーバとの接続が確立できたので、
あとは双方の通信をバイパスするだけでよい。
proxyサーバとの接続はHTTPに則った処理のあとにTCPコネクションを流用する形になるので、`hyper::upgrade::on`[^hyper-upgrade-on]で`AsyncRead + AsyncWrite`として扱えるようにする。`hyper::client::conn`を使って`TCPStream`を自分でハンドリングするという方法もあり[^hyper-2863]、試したところ問題なく動作した。ただ今回の用途ではこちらの方が簡便。最後に`tokio::io::copy_bidirectional`で双方向にコピーすることでバイパスするだけでOK (tokioがあれもこれも提供してくれていて驚く)。
```rust
use hyper::upgrade;
use tokio::io;
// ...
            if response.status().is_success() {
                let mut upgraded = upgrade::on(response).await?;
                let (a, b) = io::copy_bidirectional(&mut stream, &mut upgraded).await?;
                tracing::info!("upload {} bytes, download {} bytes", a, b);
                Ok(())
            } else {
```

## 参考
[^mdn-http-connect]: https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods/CONNECT
[^tower]: https://docs.rs/tower/latest/tower/
[^hyper-2863]: https://github.com/hyperium/hyper/issues/2863
[^hyper-connect]: https://docs.rs/hyper/0.14.20/hyper/client/connect/trait.Connect.html
[^hyper-upgrade-on]: https://docs.rs/hyper/0.14.20/hyper/upgrade/fn.on.html
