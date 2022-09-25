---
title: "sway環境構築"
date: 2022-09-25
draft: false
tags: ["wayland", "sway"]
---

久々に環境構築することになったのでメモ。

## コンポジタ
せっかくなのでwaylandに再挑戦。
元々i3[^i3]ユーザーなのでsway[^sway]を使う。
vim-likeなキーバインドは使わないので削除。

```console
# pacman -S noto-fonts noto-fonts-cjk polkit sway ttf-font-awesome xorg-xwayland
$ cp /etc/sway/config ~/.config/sway/config
```

`~/.config/sway/config`
```diff
@@ -8,17 +8,12 @@
 #
 # Logo key. Use Mod1 for Alt.
 set $mod Mod4
-# Home row direction keys, like vim
-set $left h
-set $down j
-set $up k
-set $right l
 # Your preferred terminal emulator
 set $term foot
 # Your preferred application launcher
@@ -87,22 +86,12 @@
 # Moving around:
 #
     # Move your focus around
-    bindsym $mod+$left focus left
-    bindsym $mod+$down focus down
-    bindsym $mod+$up focus up
-    bindsym $mod+$right focus right
-    # Or use $mod+[up|down|left|right]
     bindsym $mod+Left focus left
     bindsym $mod+Down focus down
     bindsym $mod+Up focus up
     bindsym $mod+Right focus right

     # Move the focused window with the same, but add Shift
-    bindsym $mod+Shift+$left move left
-    bindsym $mod+Shift+$down move down
-    bindsym $mod+Shift+$up move up
-    bindsym $mod+Shift+$right move right
-    # Ditto, with arrow keys
     bindsym $mod+Shift+Left move left
     bindsym $mod+Shift+Down move down
     bindsym $mod+Shift+Up move up
@@ -140,7 +129,7 @@
     # You can "split" the current object of your focus with
     # $mod+b or $mod+v, for horizontal and vertical splits
     # respectively.
-    bindsym $mod+b splith
+    bindsym $mod+h splith
     bindsym $mod+v splitv

     # Switch the current container between different layout styles
@@ -179,12 +168,6 @@
     # right will grow the containers width
     # up will shrink the containers height
     # down will grow the containers height
-    bindsym $left resize shrink width 10px
-    bindsym $down resize grow height 10px
-    bindsym $up resize shrink height 10px
-    bindsym $right resize grow width 10px
-
-    # Ditto, with arrow keys
     bindsym Left resize shrink width 10px
     bindsym Down resize grow height 10px
     bindsym Up resize shrink height 10px
@@ -214,4 +197,14 @@
     }
 }

+bindsym $mod+Shift+comma move workspace to output left
+bindsym $mod+Shift+period move workspace to output right
+focus_follows_mouse no
+font pango:Noto Sans Mono, Font Awesome 6 Free 12
+
 include /etc/sway/config.d/*
```

## キーボード
US配列。capsをctrlに、左右のaltを無変換/変換に対応させる。

`~/.config/sway/config`
```diff
@@ -57,6 +52,10 @@
 #
 # You can get the names of your inputs by running: swaymsg -t get_inputs
 # Read `man 5 sway-input` for more information about this section.
+input * {
+    xkb_layout us_henkan
+    xkb_options ctrl:nocaps
+}

 ### Key bindings
 #
```

`~/.xkb/symbols/us_henkan`
```
partial modifier_keys
xkb_symbols "basic" {
    include "us"
    replace key <LALT> { [ Muhenkan ] };
    replace key <RALT> { [ Henkan_Mode ] };
};
```

## ステータスバー
i3status-rust[^i3status-rust]を使う。
```console
# pacman -S i3status-rust
```

`~/.config/sway/config`
```diff
@@ -205,7 +188,7 @@

     # When the status_command prints a new line to stdout, swaybar updates.
     # The default just shows the current date and time.
-    status_command while date +'%Y-%m-%d %I:%M:%S %p'; do sleep 1; done
+    status_command i3status-rs

     colors {
         statusline #ffffff
```

`~/.config/i3status-rust/config.toml`
```toml
[icons]
name = "awesome6"
[theme]
name = "solarized-dark"

[[block]]
block = "cpu"
format = "{barchart} {utilization} {frequency}"
interval = 1

[[block]]
block = "memory"
format_mem = "{mem_used}/{mem_total}"
interval = 5

[[block]]
block = "time"
format = "%F %T"
interval = 1
```

## ターミナルエミュレータ
sway推奨のfoot[^foot]を使う。
```console
# pacman -S foot ttf-iosevka-nerd
$ cp /etc/xdg/foot/foot.ini ~/.config/foot/foot.ini
```

`~/.config/foot/foot.ini`
```diff
@@ -8,7 +8,7 @@
 # title=foot
 # locked-title=no

-# font=monospace:size=8
+font=iosevka:size=16
 # font-bold=<bold variant of regular font>
 # font-italic=<italic variant of regular font>
 # font-bold-italic=<bold+italic variant of regular font>
@@ -18,7 +18,7 @@
 # vertical-letter-offset=0
 # underline-offset=<font metrics>
 # box-drawings-uses-font-glyphs=no
-# dpi-aware=auto
+dpi-aware=false

 # initial-window-size-pixels=700x500  # Or,
 # initial-window-size-chars=<COLSxROWS>
```

## 日本語入力
fcitx5[^fcitx5]+libskk[^libskk]を使う。
```console
# pacman -S fcitx5-configtool fctix5-gtk fcitx5-qt fcitx5-skk
$ cp -r /usr/share/libskk/rules/default/ ~/.config/libskk/rules/custom/
```

`fcitx5-configtool`をポチポチ
- Input Method > Current Input Method > Default: `Keyboard - English (US)`, `SKK`
- Global Options > Hotkey
    - Activate Input Method: `Henkan`
    - Deactivate Input Method: `Muhenkan`
    - その他: `Empty`
- Addons > SKK > Candidate Layout: `Horizontal`

`~/.config/libskk/rules/custom/keymap/hiragana.json`
```diff
+++     2022-09-24 09:31:43.089906030 +0900
@@ -6,7 +6,6 @@
         "keymap": {
             "q": "set-input-mode-katakana",
             "Q": "start-preedit",
-            "l": "set-input-mode-latin",
             "L": "set-input-mode-wide-latin",
             "C-q": "set-input-mode-hankaku-katakana",
            "C-j": "commit"
```

`~/.config/libskk/rules/custom/keymap/katakana.json`
```diff
@@ -6,7 +6,6 @@
         "keymap": {
             "q": "set-input-mode-hiragana",
             "Q": "start-preedit",
-            "l": "set-input-mode-latin",
             "L": "set-input-mode-wide-latin",
             "C-q": "set-input-mode-hankaku-katakana",
            "C-j": "commit"
```

`~/.config/libskk/rules/custom/metadata.json`
```diff
@@ -1,4 +1,4 @@
 {
-    "name": "Default",
-    "description": "Default typing rule"
+    "name": "Custom",
+    "description": "Custom typing rule"
 }
```

`~/.local/share/fcitx5/skk/dictionary_list`
```
encoding=UTF-8,file=$FCITX_CONFIG_DIR/skk/user.dict,mode=readwrite,type=file
file=/usr/share/skk/SKK-JISYO.L,mode=readonly,type=file
```

## ランチャー
```console
# pacman -S skim
$ paru -S j4-dmenu-desktop
```

`~/.config/sway/config`
```diff
@@ -8,17 +8,12 @@
 # Your preferred application launcher
 # Note: pass the final command to swaymsg so that the resulting window can be opened
 # on the original workspace that the command was run on.
-set $menu dmenu_path | dmenu | xargs swaymsg exec --
+set $menu $HOME/.config/sway/dmenu

 ### Output configuration
 #
@@ -214,4 +197,14 @@
bindsym $mod+Shift+period move workspace to output right
focus_follows_mouse no
font pango:Noto Sans Mono, Font Awesome 6 Free 12
+for_window [app_id="foot-skim"] floating enabled
+for_window [app_id="foot-skim"] opacity 0.9

 include /etc/sway/config.d/*
 ```

`~/.config/sway/dmenu`
```sh
#! /usr/bin/env sh

exec foot \
     --app-id foot-skim \
     --title dmenu \
     j4-dmenu-desktop \
     --dmenu 'sk --color light --layout reverse' \
     --no-generic \
     --term foot \
     --wrapper 'swaymsg exec'
```

## 未解決
firefoxのインジケータが変

## 参考
[^i3]: https://i3wm.org/
[^sway]: https://swaywm.org/
[^i3status-rust]: https://github.com/greshake/i3status-rust
[^foot]: https://codeberg.org/dnkl/foot
[^fcitx5]: https://github.com/fcitx/fcitx5
[^libskk]: https://github.com/ueno/libskk
