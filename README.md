# M1 MacBook Pro と Ubuntu デスクトップを Nix で宣言的に管理する完全ガイド（2026年版）

## TL;DR

- クリーンな M1 Mac には **公式 NixOS インストーラ（Nix Installer Working Group が維持する foundation-owned fork、`artifacts.nixos.org/nix-installer` に `--enable-flakes` を付与）で上流 Nix を入れる**のが最も競合の少ない選択。上流 Nix なら nix-darwin の `nix.enable = true`（既定）のまま nix.conf を管理でき、過去に苦しんだ Determinate 起因の `nix.enable = false` 分岐を避けられる。
- nix-darwin は初回のみ `sudo nix run nix-darwin -- switch --flake ~/dotfiles#mac` でブートストラップし、以降は `sudo darwin-rebuild switch --flake ~/dotfiles#mac`。2025年の "The Plan" Phase 1（nix-darwin Issue #1457）以降、システムアクティベーションは root 実行が必須。home-manager は nix-darwin モジュールとして統合するのが現行推奨。
- dotfiles は `flake.nix` + `hosts/`（ホスト別）+ `modules/darwin`・`modules/home`（機能別モジュール）+ `home/<user>.nix` に分割するのがメンテしやすい。Homebrew は最初は入れず、必要になってから nix-homebrew で宣言的に管理すると Nix と競合しない。
- **Ubuntu 26.04（非 NixOS）は standalone home-manager で運用する**。システム層に相当する宣言的レイヤ（nix-darwin / NixOS モジュール）が存在しないので、ユーザー環境だけを `homeConfigurations."s-tatsuya@ubuntu"` が持ち、OS 側の下ごしらえ（Nix 本体・Docker・ログインシェル）は `scripts/ubuntu-bootstrap.sh` に閉じ込める。`modules/home` は両 OS で共有し、差分は `pkgs.stdenv.hostPlatform.isDarwin` / `isLinux` で分岐する。

## Key Findings

### 1. Nix 本体のインストール（2026年の推奨）

2026年半ば時点で macOS 用の主要なインストーラは 2 つある。

- **Determinate Systems インストーラ**（`curl -fsSL https://install.determinate.systems/nix | sh -s -- install`）は、**既定で Determinate Nix（下流ディストリビューション）をインストールする**。公式ブログ「Dropping upstream Nix from Determinate Nix Installer」（Graham Christensen, 2025年9月10日）によれば、デフォルトの Determinate Nix 切替は 2025年11月10日 に開始され、"Determinate Nix Installer will no longer prompt for Determinate Nix and will always install Determinate Nix. The `--prefer-upstream-nix` flag will no longer have an effect." とされている。つまり上流 Nix を選ぶ `--prefer-upstream-nix` フラグは README に残っているものの実質的に無効。Determinate Nix を使う場合、nix-darwin 側で必ず `nix.enable = false;` を設定しないとアクティベーションが中断する。
- **公式（上流）NixOS インストーラ**は `github.com/NixOS/nix-installer`（Nix Installer Working Group が維持する "foundation-owned fork"、Determinate インストーラのフォーク）で、`artifacts.nixos.org` から配信される。README の逐語どおり、既定では flakes / nix-command は有効化されないため `--enable-flakes` を付ける（`curl -sSfL https://artifacts.nixos.org/nix-installer | sh -s -- install --enable-flakes`）。クリーンなアンインストーラ（`/nix/nix-installer uninstall`）を備える。

**このガイドの結論**：過去に Determinate と競合した経緯があり、かつ「default 設定でシンプルに動く」ことが目的なので、**公式 NixOS インストーラで上流 Nix を入れる**。こうすれば nix-darwin が Nix 設定を一元管理でき、`nix.enable` は既定の `true` のままでよい。

インストールコマンド：

```bash
curl -sSfL https://artifacts.nixos.org/nix-installer | sh -s -- install --enable-flakes
```

マルチユーザー / シングルユーザーを聞かれたら **マルチユーザー**を選ぶ。完了後はシェルを開き直す。

### 2. flakes / nix-command 実験的機能の有効化

- 上記インストーラに `--enable-flakes` を付ければ `/etc/nix/nix.conf` に `experimental-features = nix-command flakes` が書き込まれる。
- 恒久的な管理は nix-darwin 側の `nix.settings.experimental-features = [ "nix-command" "flakes" ];` に集約するのがベスト。`darwin-rebuild switch` のたびに nix.conf が再生成される。

### 3. nix-darwin のブートストラップ

- nix-darwin には専用インストーラがなく、フレークを用意したうえで初回に次を実行する：
  ```bash
  sudo nix run nix-darwin -- switch --flake ~/dotfiles#mac
  ```
- これで `darwin-rebuild` コマンドが PATH に入る。以降の適用は **`sudo darwin-rebuild switch --flake ~/dotfiles#mac`**。nix-darwin Issue #1457「system activation must now be run as root」の逐語のとおり "nix-darwin has recently switched over to running the entire system activation process as root... you need to use `sudo darwin-rebuild switch` instead of `darwin-rebuild switch` from now on." であり、この変更は "The Plan" Phase 1（メンテナ emilazy）によるもの。関連する nix-homebrew Issue #60（2025年2月22日）にも "darwin-rebuild must now be run as root, the `system.activationScripts.{extraUserActivation,preUserActivation,postUserActivation}` settings have been removed" と記録されている。

### 4. home-manager の統合方式

- **nix-darwin モジュールとして統合する**（`home-manager.darwinModules.home-manager` を使う）のが現行の推奨。`darwin-rebuild switch` の一発でシステム設定とユーザー設定が同時に構築される。
- スタンドアロン（`home-manager` CLI を単体で使う）方式もあるが、システムとユーザーを別々に管理したい場合に限られる。統合方式では `home-manager.useGlobalPkgs = true;` と `home-manager.useUserPackages = true;` を設定する。
- `programs.home-manager.enable = true;` をユーザー設定に入れておくと、`home-manager` CLI 自体がユーザープロファイルに入り、`home-manager --version` などが実行可能になる。

### 5. Homebrew との競合回避

- 最初の最小構成では **Homebrew を入れない**。過去の競合は、Nix と Homebrew が両方 PATH を奪い合ったり、両方で同じツールを入れたことに起因することが多い。
- GUI アプリなどで Homebrew が必要になったら、`nix-homebrew`（`github:zhaofengli/nix-homebrew`）で Homebrew 本体をインストール・ピン留めし、`homebrew.casks` / `homebrew.brews` で宣言的に管理する。nix-darwin の `homebrew.enable = true` は Homebrew 本体をインストールしない点に注意（別途 nix-homebrew か手動インストールが必要）。

### 6. GitHub 認証方式（SSH ではなく gh CLI に一本化）

「HTTPS トークン / SSH 鍵 / gh CLI」は並列の選択肢ではない。**gh CLI 認証は HTTPS トークン認証そのもの**で、`gh auth login` が OAuth トークンを取得して macOS キーチェーンに保存し、`credential.helper = gh auth git-credential` を git に登録する。したがって実質の選択は SSH か HTTPS かであり、HTTPS を選ぶなら gh に任せるのが最も手数が少ない（PAT を手発行する方式は有効期限とスコープの管理が自分持ちになるだけ）。

**この構成で HTTPS + gh を採る理由：**

- **root 実行の副作用を構造的に回避できる**。Caveats に挙げた nix-darwin Issue #1471（`sudo darwin-rebuild` が root で走るため SSH 鍵が見つからない）は **SSH 固有**の摩擦。HTTPS + トークンなら `nix.settings.access-tokens` がシステム設定として効くので同じ問題が起きない。
- **flake input の取得と相性が良い**。未認証の GitHub API は 60 req/h でレート制限され、input 解決で引っかかる。これを解消する `access-tokens` はトークン方式でしか書けず、SSH 鍵では解決できない。プライベート flake を input に入れる場合も同様。
- **カバー範囲が広い**。SSH 鍵は git の push/pull しか賄わないが、gh は PR / Issue / Release / Actions・`gh api`・`gh extension` まで扱え、`gh auth token` で他ツールにトークンを渡せる。
- **ネットワーク耐性**。443 は塞がれないが 22 は社内 NW や公衆 Wi-Fi で塞がれることがある。

**SSH を併用する価値が出る場合**：コミット署名（`gpg.format = "ssh"` は GPG より運用が楽）、複数アカウントを `~/.ssh/config` のホスト別エイリアスで切り替えたい場合。いずれも現時点では不要なので鍵は作らない。

## Details

### 推奨ディレクトリ構成（dotfiles リポジトリ）

複数ファイルに分割してメンテしやすくする、コミュニティで一般的なフレーク構成：

```
~/dotfiles/
├── flake.nix                 # エントリポイント（inputs / darwinConfigurations / homeConfigurations）
├── flake.lock                # 依存の固定（自動生成）
├── README.md
├── hosts/                    # ホスト固有の設定
│   ├── mac/
│   │   └── default.nix       # nix-darwin 側の設定（primaryUser 等）
│   └── ubuntu/
│       └── default.nix       # Ubuntu デスクトップ固有の home-manager 設定
├── modules/
│   ├── darwin/               # nix-darwin（システム）用モジュール。macOS 専用
│   │   ├── default.nix       # 集約（imports）
│   │   ├── nix.nix           # nix 設定・experimental-features
│   │   ├── system.nix        # macOS system.defaults / Touch ID
│   │   └── homebrew.nix      # Homebrew 宣言（GUI アプリ）
│   └── home/                 # home-manager（ユーザー）用モジュール。両 OS 共通
│       ├── default.nix       # 集約（imports）
│       ├── linux.nix         # 非 NixOS Linux 用の受け皿（isLinux のときだけ有効）
│       ├── packages.nix      # ユーザーパッケージ
│       ├── git.nix           # アプリ別設定の例
│       └── zsh.nix
├── home/
│   └── s-tatsuya.nix         # ユーザー固有の home-manager エントリ（両 OS 共通）
└── scripts/
    └── ubuntu-bootstrap.sh   # Ubuntu 側の「Nix で管理できない部分」をまとめて実行
```

新しいアプリ設定を足すときは `modules/home/<app>.nix` を作って `modules/home/default.nix` の imports に追加、macOS 固有のシステム機能なら `modules/darwin/<feature>.nix` を作って `modules/darwin/default.nix` に追加する。ホストを増やすときは `hosts/<name>/` を作り、`flake.nix` の `darwinConfigurations` か `homeConfigurations` にエントリを足す。

### 両 OS で 1 つの `modules/home` を共有する書き方

`modules/home/*` は macOS からも Ubuntu からも読まれるので、OS 差はモジュールの中で吸収する。使い分けは 3 パターンしかない。

1. **モジュールまるごと片方だけ**：ファイルの先頭で `lib.mkIf pkgs.stdenv.hostPlatform.isLinux { ... }` と包む（`modules/home/linux.nix`）。
2. **一部の属性だけ足す**：`// lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin { ... }`（`ghostty.nix` の `macos-option-as-alt`）。
3. **同じ目的を別の仕組みで実現する**：両方書いて片方を `mkIf` で消す（`plantuml.nix` の `launchd.agents` と `systemd.user.services`）。`launchd` / `systemd` のオプション自体は home-manager がどちらの OS でも宣言しているので、`mkIf` で false 側に倒せば評価は通り、生成物にも現れない。

パスの分岐（`/Users` と `/home`）は `home/s-tatsuya.nix` の 1 箇所に閉じ込めてあるので、`hosts/*` 側では意識しなくてよい。

### 最小構成の flake.nix

安定版 Nixpkgs 26.05 系列を使う例（unstable を使いたい場合は各 URL を `nixpkgs-unstable` / `master` / `release-26.05` の対応ブランチに変える）：

```nix
{
  description = "Tatsuya's macOS configuration (nix-darwin + home-manager)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, nix-darwin, home-manager }:
  let
    username = "s-tatsuya";
    system = "aarch64-darwin";   # M1/M2/M3 は aarch64-darwin
  in
  {
    darwinConfigurations."mac" = nix-darwin.lib.darwinSystem {
      inherit system;
      specialArgs = { inherit inputs username; };
      modules = [
        ./hosts/mac/default.nix

        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit inputs username; };
          home-manager.users.${username} = import ./home/${username}.nix;
        }
      ];
    };
  };
}
```

> 注：`darwin-rebuild switch --flake ~/dotfiles#mac` の `#mac` は、上の `darwinConfigurations."mac"` を指す。過去に使っていた `#mac` 出力名をそのまま踏襲できる。

### hosts/mac/default.nix

```nix
{ pkgs, username, ... }:
{
  imports = [
    ../../modules/darwin
  ];

  # sudo / Touch ID / homebrew などが適用される主ユーザー
  system.primaryUser = username;

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  # Apple Silicon
  nixpkgs.hostPlatform = "aarch64-darwin";

  # 後方互換用。`darwin-rebuild changelog` を参照。
  # `nix flake init -t nix-darwin` が生成する現行値を使うのが安全。
  system.stateVersion = 6;
}
```

### modules/darwin/default.nix

```nix
{ ... }:
{
  imports = [
    ./nix.nix
    ./system.nix
  ];
}
```

### modules/darwin/nix.nix

```nix
{ ... }:
{
  # 公式（上流）インストーラで Nix を入れた場合はこのまま（既定 true）。
  # nix-darwin が /etc/nix/nix.conf を管理する。
  # ※ Determinate Nix を使う場合はここを false にすること。
  nix.enable = true;

  # flakes と nix-command を恒久的に有効化
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # ストア自動最適化
  nix.optimise.automatic = true;

  # /etc/zshrc に nix-darwin 環境を読み込ませる
  programs.zsh.enable = true;
}
```

### modules/darwin/system.nix

```nix
{ ... }:
{
  system.defaults = {
    dock.autohide = true;
    finder.AppleShowAllExtensions = true;
  };

  # Touch ID で sudo を解除（要再起動で有効化）
  security.pam.services.sudo_local.touchIdAuth = true;
}
```

### home/s-tatsuya.nix

```nix
{ pkgs, username, ... }:
{
  imports = [
    ../modules/home
  ];

  home.username = username;
  home.homeDirectory = "/Users/${username}";

  # 初回導入時のバージョン。基本的に変更しない。
  home.stateVersion = "26.05";

  # home-manager 自身を管理（CLI も利用可能になる）
  programs.home-manager.enable = true;
}
```

### modules/home/default.nix

```nix
{ ... }:
{
  imports = [
    ./packages.nix
    ./git.nix
    ./zsh.nix
  ];
}
```

### modules/home/packages.nix

```nix
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    ripgrep
    fd
    jq
    tree
  ];
}
```

### modules/home/git.nix

```nix
{ ... }:
{
  programs.git = {
    enable = true;
    userName = "Tatsuya";
    userEmail = "you@example.com";
  };
}
```

### modules/home/gh.nix

```nix
{ ... }:
{
  programs.gh = {
    enable = true;
    settings.git_protocol = "https";
  };
}
```

`gitCredentialHelper.enable` は既定で `true` なので明示不要。これにより git 設定側へ次がマージされる：

```gitconfig
[credential "https://github.com"]
	helper = ""
	helper = "/nix/store/....-gh-2.96.0/bin/gh auth git-credential"
```

先頭の `helper = ""` が既存ヘルパー（macOS 既定の `osxkeychain`）を**該当ホストについてのみ**リセットするため、ヘルパーが二重登録されて認証情報が食い違うことはない。同じブロックが `https://gist.github.com` にも生成される。

トークン自体は宣言的に管理しない（フレークの内容は world-readable な Nix ストアにコピーされるため）。マシンごとに一度 `gh auth login` を実行する。

### modules/home/zsh.nix

```nix
{ ... }:
{
  # nix-darwin 側でも zsh を有効化しているが、home-manager 側でも
  # 有効化すると direnv などのフックが確実に挿入される。
  programs.zsh.enable = true;
}
```

## Recommendations（手順：クリーンな Mac → 動作確認まで）

**Step 0 — Mac の初期化**
「システム設定 → 一般 → 転送またはリセット → すべてのコンテンツと設定を消去」で初期化するか、リカバリで macOS を再インストールする。

**Step 1 — 初期セットアップと git**
macOS の初期設定でユーザー `s-tatsuya` を作成。ターミナルで Xcode コマンドラインツール（git を含む）を入れる：

```bash
xcode-select --install
```

**Step 2 — Nix をインストール（上流 + flakes）**

```bash
curl -sSfL https://artifacts.nixos.org/nix-installer | sh -s -- install --enable-flakes
```

マルチユーザーを選択。完了後、ターミナルを開き直して確認：

```bash
nix --version
nix run nixpkgs#hello        # Hello, world! が出れば OK
```

**Step 3 — dotfiles リポジトリを作る**

```bash
mkdir -p ~/dotfiles
cd ~/dotfiles
git init
# 上記の flake.nix / hosts / modules / home を作成
git add .                    # ★フレークは git 追跡下のファイルしか見ないので必須
```

**Step 4 — nix-darwin をブートストラップ**

```bash
sudo nix run nix-darwin -- switch --flake ~/dotfiles#mac
```

`/etc/zshrc` などの既存ファイルで衝突警告が出たら、退避してから再実行：

```bash
sudo mv /etc/zshrc /etc/zshrc.before-nix-darwin
```

**Step 5 — 動作確認**
新しいターミナルを開いて：

```bash
which darwin-rebuild
darwin-rebuild --version
darwin-rebuild --list-generations
home-manager --version       # programs.home-manager.enable = true; により利用可能
nix --version
```

**Step 6 — GitHub 認証（マシンごとに1回）**
トークンはリポジトリに置けないので、ここだけは手作業になる（SSH 鍵を配れないのと同じ）。

```bash
gh auth login                        # HTTPS → ブラウザ認証 を選択
gh auth status
git config --get-regexp '^credential\.'   # gh のヘルパーが登録されているか確認
git ls-remote https://github.com/s-tatsuya/dotfiles.git >/dev/null && echo OK
```

flake input の取得で GitHub API のレート制限（未認証は 60 req/h）に当たる場合や、プライベート flake を input にする場合は access-token を設定する。トークンをフレークに直書きすると world-readable な Nix ストアに載るので、git 管理外のファイルを include する：

```nix
# modules/darwin/nix.nix
nix.extraOptions = ''
  !include /etc/nix/secret.conf
'';
```

```bash
sudo sh -c 'echo "access-tokens = github.com=$(gh auth token)" > /etc/nix/secret.conf'
sudo chmod 600 /etc/nix/secret.conf
```

**Step 7 — 以降の運用**
設定を変えたら：

```bash
sudo darwin-rebuild switch --flake ~/dotfiles#mac
```

依存を更新したいときは `nix flake update` を実行してから switch する。

**運用を変える閾値：**

- Homebrew でしか入らない GUI アプリが必要になったら → `nix-homebrew` を inputs に追加して宣言的管理へ移行。
- 複数 Mac / Linux を管理し始めたら → `hosts/` にエントリを追加し、`modules/home` を共通化。**（対応済み：Ubuntu デスクトップは次章）**
- ビルドが極端に遅い（LLVM 等をソースビルドしてしまう）なら → `nixpkgs` の URL を `nixos-*` ではなく `nixpkgs-*-darwin` チャンネルに固定（Darwin バイナリがキャッシュされている）。

## Ubuntu 26.04（デスクトップPC）のセットアップ

### 方式：standalone home-manager

Ubuntu は NixOS ではないので、macOS の nix-darwin にあたる「システム層の宣言的レイヤ」が存在しない。したがって役割を次のように割る。

| 層 | macOS | Ubuntu 26.04 |
| --- | --- | --- |
| システム設定 | nix-darwin（`modules/darwin`） | **Nix の管轄外**。apt と systemd（`scripts/ubuntu-bootstrap.sh`） |
| GUI アプリ | Homebrew cask（nix-homebrew で宣言） | nixpkgs か apt |
| ユーザー環境 | home-manager（nix-darwin モジュールとして統合） | home-manager（standalone） |
| 適用コマンド | `sudo darwin-rebuild switch --flake ~/dotfiles#mac` | `home-manager switch --flake ~/dotfiles#s-tatsuya@ubuntu` |

`modules/home/*` は両方から読まれる共通資産で、OS 差はモジュール内で吸収する（前章「両 OS で 1 つの `modules/home` を共有する書き方」）。`nix-darwin` / `nix-homebrew` の input は `darwinConfigurations` からしか参照されないので、Ubuntu 側の評価では引かれない。

### nixpkgs を 2 本持つ理由

`flake.nix` の input は `nixpkgs`（`nixpkgs-26.05-darwin`）と `nixpkgs-linux`（`nixos-26.05`）の 2 本ある。

`nixpkgs-*-darwin` は **Darwin のジョブセットが通ったコミットだけが進む**チャンネルで、Darwin のバイナリキャッシュが埋まっている代わりに、そのコミットの Linux 成果物がキャッシュに載っている保証がない。Linux 側から同じ input を使うと、条件次第で LLVM などをソースビルドし始める。同じ 26.05 系列の NixOS チャンネルを別 input として持ち、`homeConfigurations` にだけ渡すことでこれを避ける。

実際に `cache.nixos.org` に問い合わせた結果（x86_64-linux）：

| パッケージ | キャッシュ |
| --- | --- |
| ghostty 1.3.1 / helix 25.07.1 / plantuml 1.2026.3 / explex-nf 0.0.3 / starship 1.25.1 / zsh 5.9.1 | あり |
| herdr 0.7.5 | **なし（ソースビルド）** |

herdr は自前フレークで公開キャッシュを持たないため Rust のビルドが走る。これは macOS でも同じ（aarch64-darwin も未キャッシュ）なので、Linux 移行による新たな劣化ではない。初回の `home-manager switch` が数分かかる要因にはなる。

### 手順

**Step 1 — リポジトリを取得**

```bash
sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/s-tatsuya/dotfiles.git ~/dotfiles
```

**Step 2 — ブートストラップスクリプトを実行**

```bash
~/dotfiles/scripts/ubuntu-bootstrap.sh
```

`sudo` を付けずに実行する（`$HOME` と `$USER` が root になってしまうため）。スクリプトの中で必要な箇所だけ `sudo` を呼ぶ。やっていることは 5 つで、いずれも冪等：

1. apt の最小パッケージ（`ca-certificates` / `curl` / `git` / `gnupg` / `xz-utils` / `zsh`）。**zsh は Nix より先に入れる**。Nix のインストーラは「そのとき存在するシェルの設定ファイル」にプロファイル読み込みを差し込むので、順番が逆だと zsh 側だけ漏れる。
2. Nix 本体（macOS と同じ公式インストーラ、`--enable-flakes`）。Ubuntu には nix-darwin がいないので、`/etc/nix/nix.conf` の内容はここで確定する（`nix.settings` を home-manager に書いても `~/.config/nix/nix.conf` に出るだけで daemon には効かない）。
3. Docker Engine（次項）。
4. ログインシェルを zsh に変更。
5. `home-manager switch --flake ~/dotfiles#s-tatsuya@ubuntu`。初回は CLI がまだ無いので、代わりに自前の flake から `activationPackage` をビルドして `$out/activate` を直接叩く：

   ```bash
   act="$(nix build --no-link --print-out-paths \
     '~/dotfiles#homeConfigurations."s-tatsuya@ubuntu".activationPackage')"
   HOME_MANAGER_BACKUP_EXT=backup "$act/activate"
   ```

   `nix run github:nix-community/home-manager -- switch` でも動くが、あちらは home-manager 側の nixpkgs（nixos-unstable）まで引くので余計なダウンロードが増え、このリポジトリの `flake.lock` が固定している版ともズレる。`HOME_MANAGER_BACKUP_EXT=backup` は `switch -b backup` と同じ意味で、既存の `~/.zshenv` などを `.backup` 付きに退避してから symlink を張る。アクティベート後は `programs.home-manager.enable = true` により `home-manager` CLI が入るので、2 回目からは普通に `home-manager switch` でよい。
6. `sudo non-nixos-gpu-setup`（次項）。

**Step 3 — ログインし直す**

次の 3 つはログインし直して初めて効く。

- docker グループ（`sudo` なしの `docker`）
- ログインシェルの zsh
- `XDG_DATA_DIRS`（GNOME のアプリ一覧に Ghostty が出る。`systemd --user` は起動時にしか `~/.config/environment.d/` を読まない）

**Step 4 — GitHub 認証（マシンごとに 1 回）**

```bash
gh auth login        # HTTPS → ブラウザ認証
gh auth status
```

macOS ではトークンがキーチェーンに入るが、Ubuntu ではキーチェーンに相当するものが無いので `~/.config/gh/hosts.yml` に平文で保存される（パーミッションは 600）。ディスク暗号化を有効にしておくこと。

**Step 5 — 動作確認**

```bash
home-manager --version
ghostty --version
docker run --rm hello-world                       # sudo なしで通ること
fc-list | grep -i explex                          # フォントが見えていること
systemctl --user status plantuml-server           # PlantUML サーバが動いていること
readlink /run/opengl-driver                       # GPU 連携が設定されていること（空なら未設定）
```

**Step 6 — 以降の運用**

```bash
home-manager switch --flake ~/dotfiles#s-tatsuya@ubuntu
```

`nix flake update` は両 OS 共通の `flake.lock` を動かすので、どちらか一方で更新して push し、もう一方は pull してから switch する。

### Docker（`sudo` なしで実行する）

**Nix で管理しない。** `dockerd` はシステムの systemd サービスで、`/var/run/docker.sock` の所有権も `docker` グループの作成も root 権限が要る。NixOS なら `virtualisation.docker.enable` で宣言できるが、Ubuntu の standalone home-manager にはそれに相当するものが無い。よってブートストラップスクリプトの担当にする。

インストール元は **Docker 公式 apt リポジトリ**（Ubuntu の `docker.io` ではない）。`docker compose` と `buildx` がプラグインとして付いてきて、バージョンも上流に追随するため。スクリプトは公式手順どおり、名前がぶつかるディストリ側のパッケージ（`docker.io` / `docker-compose` / `podman-docker` / `containerd` / `runc` …）を先に外し、`/etc/apt/keyrings/docker.asc` と deb822 形式の `/etc/apt/sources.list.d/docker.sources` を置いてから `docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin` を入れる。

`sudo` なしで叩けるようにする部分：

```bash
sudo groupadd -f docker
sudo usermod -aG docker "$USER"
# 反映はログインし直してから（その場で試すなら newgrp docker）
```

> **`docker` グループ = 実質 root**。このグループに入ると、コンテナ経由でホストのファイルシステムを root 権限で読み書きできる（`docker run -v /:/host` など）。Docker 公式ドキュメントも明記している既知のトレードオフで、「`sudo` なしで実行する」という要件を満たす以上は避けられない。より強い分離が要るなら rootless モード（`dockerd-rootless-setuptool.sh install`）に切り替える選択肢もあるが、バインドマウント・ネットワーク・GPU 周りに制約が付く。

**Ubuntu 26.04 のコードネームについて**：Docker のリポジトリは Ubuntu の新バージョンへの追随に時間差がある。スクリプトは `dists/<codename>/Release` の存在を確認し、無ければ `noble`（24.04 LTS）のパッケージへ自動的に落とす。手動で指定したいときは環境変数で上書きする：

```bash
DOCKER_APT_SUITE=noble ~/dotfiles/scripts/ubuntu-bootstrap.sh
```

### GPU ドライバ（非 NixOS 特有の一手間）

**`home-manager switch` だけでは完結しない唯一の箇所**なので独立した節にする。

非 NixOS では、Nix でビルドされた OpenGL / Vulkan アプリはホスト（Ubuntu）側の GPU ドライバをそのまま使えない。ライブラリの探索パスが `/nix/store` に閉じているためで、いわゆる nixGL 問題として知られている。home-manager 26.05 はこれを `targets.genericLinux.gpu` として取り込んでおり、`targets.genericLinux.enable = true` にすると `gpu.enable` も既定で true になって `non-nixos-gpu` パッケージが `home.packages` に入る。

ただし実体の設置には root が要る（`/etc/tmpfiles.d/non-nixos-gpu.conf` を置いて `/run/opengl-driver` を張る）ため、home-manager のアクティベーションは**自動実行せず警告を出すだけ**：

```
This non-NixOS system is not yet set up to use the GPU with Nix packages.
To set up GPU drivers, run
  sudo /nix/store/.../bin/non-nixos-gpu-setup
```

`scripts/ubuntu-bootstrap.sh` は home-manager 適用のあとにこれを代わりに実行する（冪等）。手で流すなら：

```bash
sudo ~/.nix-profile/bin/non-nixos-gpu-setup
```

Ghostty は GPU 描画なので、飛ばすとソフトウェアレンダリングに落ちるか起動に失敗する。

**NVIDIA プロプライエタリドライバの場合はこれだけでは足りない。** Nix 側に「ホストのカーネルモジュールと完全に同じバージョン」のユーザー空間ライブラリを用意する必要がある。`hosts/ubuntu/default.nix` にコメントアウト済みのひな型を置いてあるので、次の 2 つを埋めて有効にする。

```bash
nvidia-smi --query-gpu=driver_version --format=csv,noheader   # → version
nix store prefetch-file \
  https://download.nvidia.com/XFree86/Linux-x86_64/<VERSION>/NVIDIA-Linux-x86_64-<VERSION>.run   # → sha256
```

Intel / AMD（Mesa）なら `non-nixos-gpu-setup` を流すだけで完結する。ホスト側のドライバを更新したら、NVIDIA の場合はこの設定も追従させること（バージョンがズレると GL が動かなくなる）。

### Ghostty（Ubuntu）

本体は **nixpkgs の `ghostty` をそのまま使う**（apt にも公式 PPA にも無いので、Nix で入れるのが最も手数が少ない）。macOS 側が Homebrew cask なのは、nixpkgs の ghostty が `meta.platforms = *-linux` で darwin では評価が通らないという事情によるもので、`modules/home/ghostty.nix` は `package = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin null;` の 1 行だけでこの差を吸収している。

- 設定ファイル（`~/.config/ghostty/config`）は両 OS 共通。macOS の Ghostty も XDG のパスを読む。
- `macos-option-as-alt` だけは `lib.optionalAttrs isDarwin` で macOS 限定にしてある（Linux の Alt は最初から Alt として届く）。
- ランチャー（GNOME の app grid）に出すには `XDG_DATA_DIRS` に `~/.nix-profile/share` が入っている必要がある。これは `modules/home/linux.nix` の `targets.genericLinux.enable` と `xdg.enable` を有効にすることで home-manager が `~/.config/environment.d/10-home-manager.conf` を生成して行う。**ここに自前で `XDG_DATA_DIRS` を書き足してはいけない**：同じファイルの後ろに追記される結果、home-manager が組み立てた行（`/usr/share/ubuntu` や `/var/lib/snapd/desktop` を含む）を上書きしてしまう。
- `Ctrl+Alt+T` で開く既定のターミナルは GNOME 側の設定であり Nix の管轄外。必要なら GNOME の設定でカスタムキーバインドを割り当てる。

### PlantUML サーバ（常駐プロセスの OS 差）

`modules/home/plantuml.nix` は同じプロセス（`plantuml --http-server:45123`）を 2 通りに書いてある。

- macOS：`launchd.agents.plantuml-server`（ログは `~/Library/Logs/plantuml-server.log`）
- Ubuntu：`systemd.user.services.plantuml-server`（ログは `journalctl --user -u plantuml-server`）

home-manager は `launchd` も `systemd` もどちらの OS でもオプションとして宣言しているので、`lib.mkIf` で片方を false に倒せば評価は通り、生成物には現れない。Helix 側（`mpls --plantuml-server`）はポート番号を `local.plantuml.port` オプション経由で共有しているだけなので OS 差はない。

なお `systemd --user` が前提なので、systemd を持たない環境（既定の WSL など）ではこのサービスは動かない。

### フォント

`explex-nf` は `home.packages` に入れているが、OS から見えるようにする経路が違う。

- macOS：home-manager が `~/Library/Fonts/HomeManager/` へ実体コピーする（macOS は symlink のフォントを認識しない）。探索は CoreText なので fontconfig は不要。
- Ubuntu：fontconfig 経由。ただし `fonts.fontconfig.enable` の既定値は「NixOS の submodule として動いていて `useUserPackages` が有効」なときだけ true なので、standalone home-manager では **明示的に有効化しないと見つからない**。`modules/home/packages.nix` で `pkgs.stdenv.hostPlatform.isLinux` のとき true にしてある。

確認は `fc-list | grep -i explex`。

## Caveats

- **`system.stateVersion` の値**：`nix flake init -t nix-darwin` が生成する現行値を使うのが最も安全。ここでは 6 を例示したが、導入時のテンプレート値に合わせること。一度決めたら基本的に変更しない。
- **`home.stateVersion`**：導入時の Nixpkgs リリースに合わせる（例では 26.05）。Nixpkgs と home-manager のリリースがずれると警告が出る。
- **Intel Mac（x86_64-darwin）は打ち切り方向**：NixOS 26.05 リリースノート逐語のとおり "This will be the last release of Nixpkgs to support x86_64-darwin. Platform support will be maintained and binaries built until Nixpkgs 26.05 goes out of support at the end of 2026. For 26.11... we will no longer build packages for x86_64-darwin or support building them from source."（背景は Apple の "macOS 26 will be the final version to support Intel Macs"）。M1 なら `aarch64-darwin` で問題なし。
- **Determinate インストーラの README は表記が古い**：`--prefer-upstream-nix` が残っているが 2025年11月10日以降は実質無効。Determinate を選ぶなら nix-darwin 側で `nix.enable = false;` が必須。設定しないと `error: Determinate detected, aborting activation`（nix-darwin の modules/system/checks.nix が出す逐語メッセージ："Determinate uses its own daemon to manage the Nix installation that conflicts with nix-darwin's native Nix management. To turn off nix-darwin's management of the Nix installation, set: `nix.enable = false;`"）で中断する。この opt-out 機構は nix-darwin PR #1313（master）・#1326（24.11）で追加された。
- **root 実行の副作用**：`sudo darwin-rebuild` は root で走るため、プライベートフレークや SSH 鍵を要する場合に鍵が見つからないことがある。nix-darwin Issue #1471 の逐語 "Now that darwin-rebuild requires using sudo, I am unable to access private flakes / git repos, as root does not have my ssh keys, so my system fails to build." のとおり既知の摩擦点。回避策として同 Issue で "`darwin-rebuild build --flake ~/flake.nix && sudo ./result/activate` seems to work okay"（ビルドはユーザーで、アクティベートのみ root で）が報告されている。
- **秘密情報はリポジトリに置かない**：フレークの内容は world-readable な Nix ストアにコピーされる。SSH 鍵・API トークンは別管理（sops-nix 等）。
- **`flake.lock` が root 所有になることがある**：`sudo darwin-rebuild` や `sudo nix flake update` の名残で、以降 `nix flake update` が `opening file "flake.lock": Permission denied` で落ちる。`sudo chown "$(id -un)" ~/dotfiles/flake.lock` で直す。
- **`flake.lock` は両 OS 共有**：`nix flake update` はどちらか一方で実行して push し、もう一方は pull してから switch する。片方だけで更新し続けると、もう片方の switch のたびに差分が出る。
- **Ubuntu 側のアーキテクチャは `x86_64-linux` 固定**：`flake.nix` の `linuxSystem` に書いてある。ARM のデスクトップ／ミニ PC を足すときは `aarch64-linux` に変えるか、ホストごとに分ける。
- **`homeConfigurations` は macOS からはビルドできない**：評価（`nix eval`）は通るが、Linux のバイナリを darwin 上でビルドすることはできない。Mac 側で Ubuntu 用の設定を触ったときは、評価が通ることだけ確認して実機で switch する：
  ```bash
  nix eval --raw '.#homeConfigurations."s-tatsuya@ubuntu".activationPackage.drvPath'
  ```
- **GPU ドライバだけは `home-manager switch` で完結しない**：`/etc/tmpfiles.d` への設置に root が要るため、`sudo non-nixos-gpu-setup` を別途 1 回流す必要がある（詳細は前章）。NVIDIA を使う場合はホスト側のドライバ更新のたびに `hosts/ubuntu/default.nix` の追従も要る。
- **Ubuntu には keychain が無い**：`gh` のトークンは `~/.config/gh/hosts.yml` に平文で置かれる（600）。ディスク暗号化前提で運用する。

## 一部のアプリはNixで管理しない

- Claude Code 最新版の更新が早くモデルが利用できない機能が使えない可能性があるため
  - 更新の遅れを気にしての採用のため、公式インストーラを使った運用とする
- Naya Flow は Nix でも Homebrew でも管理されていないキーボードのキーマップ変更GUIツールのため
- HHKB のキーマップ変更ツールも Nix でも Homebrew でも管理されていないGUIツールのため
- Docker Engine（Ubuntu）は dockerd がシステムの systemd サービスであり、`docker` グループの作成も含めて root 権限が要るため
  - NixOS の `virtualisation.docker` に相当するものが Ubuntu + standalone home-manager には無い
  - `scripts/ubuntu-bootstrap.sh` が Docker 公式 apt リポジトリから入れ、`usermod -aG docker` まで行う
- Ubuntu のログインシェル（`chsh`）は `/etc/passwd` の書き換えなので同上。`~/.zshrc` の中身は home-manager が持つ

### Herdr のプラグインも Nix で管理しない

- `herdr plugin install persiyanov/herdr-reviewr`: コーディングエージェントの変化点を確認しやすくするためのプラグイン
