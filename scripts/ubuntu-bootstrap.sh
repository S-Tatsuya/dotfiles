#!/usr/bin/env bash
#
# Ubuntu 26.04 のデスクトップを、この dotfiles を適用できる状態まで持っていく。
#
# ここで面倒を見るのは「standalone home-manager では宣言的に管理できないもの」だけ:
#   1. apt の最小パッケージ（curl / git / zsh など）
#   2. Nix 本体（/nix と nix-daemon の作成に root が要る）
#   3. Docker Engine（システムの systemd サービスと docker グループ）
#   4. ログインシェルの zsh 化（/etc/passwd の書き換え）
#   5. 非 NixOS 向け GPU ドライバ連携（/etc/tmpfiles.d への配置）
# ユーザー環境（Ghostty / Helix / zsh の中身 / フォント …）は home-manager が持つ。
#
# 何度実行しても同じ結果になる（冪等）。sudo は必要になった時点で個別に呼ぶので、
# スクリプト自体を sudo で起動しないこと（$HOME と $USER が root になってしまう）。
#
#   使い方: ./scripts/ubuntu-bootstrap.sh
#
set -euo pipefail

FLAKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HM_ATTR='homeConfigurations."s-tatsuya@ubuntu".activationPackage'
HM_FLAKE_REF="${FLAKE_DIR}#s-tatsuya@ubuntu"

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -ne 0 ]] || die "sudo なしで実行してください（内部で必要な箇所だけ sudo します）"
[[ -r /etc/os-release ]] || die "/etc/os-release が読めません。Ubuntu で実行してください"
# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || warn "Ubuntu 以外（ID=${ID:-unknown}）で実行しています。想定外の動作をするかもしれません"

# ── 1. apt の最小パッケージ ────────────────────────────────────────────────
# zsh は Nix より先に入れておく。Nix のインストーラは「そのとき存在するシェルの
# 設定ファイル」にプロファイル読み込みを差し込むので、順番が逆だと zsh 側が漏れる。
# （漏れた場合の保険は modules/home/linux.nix の initContent に入れてある）
log "apt の基本パッケージを導入"
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  ca-certificates curl git gnupg xz-utils zsh

# ── 2. Nix 本体 ────────────────────────────────────────────────────────────
# README「Nix 本体のインストール」と同じ、公式（上流）NixOS インストーラを使う。
# --enable-flakes で /etc/nix/nix.conf に experimental-features が書かれる。
# macOS と違って nix-darwin が nix.conf を管理しないので、この設定はここで確定する。
if [[ -e /nix/var/nix/profiles/default/bin/nix ]]; then
  log "Nix は導入済み（スキップ）"
else
  log "Nix を導入（公式インストーラ / multi-user / flakes 有効）"
  # プランナ（linux / macos / wsl …）は指定しなければ自動判定される。README と同じ呼び出し。
  curl -sSfL https://artifacts.nixos.org/nix-installer | sh -s -- install --enable-flakes
fi

# このシェルからも nix を使えるようにする（インストール直後は PATH に無い）。
if ! command -v nix >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
command -v nix >/dev/null 2>&1 || die "nix が PATH に入りませんでした。ログインし直して再実行してください"

# ── 3. Docker Engine（sudo なしで使えるようにする）─────────────────────────
# Nix では入れない。dockerd はシステムの systemd サービスであり、/var/run/docker.sock の
# 所有権と docker グループの作成も root 権限が要るため、standalone home-manager の
# 管轄外になる（NixOS の virtualisation.docker に相当するものが Ubuntu には無い）。
# Ubuntu の docker.io ではなく Docker 公式 apt リポジトリを使う。compose / buildx が
# プラグインとして付いてきて、バージョンも上流に追随する。
if command -v docker >/dev/null 2>&1 && [[ -e /etc/apt/sources.list.d/docker.sources ]]; then
  log "Docker Engine は導入済み（スキップ）"
else
  log "Docker Engine を導入（Docker 公式 apt リポジトリ）"

  # 公式ドキュメントが「先に消せ」としている、名前がぶつかるディストリ側のパッケージ。
  # 入っていなくてもエラーにしない。
  for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    sudo apt-get remove -y "$pkg" >/dev/null 2>&1 || true
  done

  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  # Docker のリポジトリは Ubuntu の新バージョンに追随するまで時間差がある。
  # 当該コードネームの Release が無ければ、直近の LTS スイートへ落とす。
  # 手動で上書きしたいときは DOCKER_APT_SUITE=noble のように環境変数で指定する。
  suite="${DOCKER_APT_SUITE:-${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}}"
  [[ -n "$suite" ]] || die "Ubuntu のコードネームを判定できません。DOCKER_APT_SUITE を指定してください"
  if ! curl -fsI "https://download.docker.com/linux/ubuntu/dists/${suite}/Release" >/dev/null 2>&1; then
    warn "Docker のリポジトリに ${suite} がまだありません。noble（24.04 LTS）のパッケージで代替します"
    suite="noble"
  fi

  # deb822 形式（.sources）で書く。近年の apt は一行形式（.list）に非推奨警告を出す。
  sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${suite}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  sudo apt-get update
  sudo apt-get install -y \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# sudo なしで docker を叩けるようにする。docker グループは docker.sock の所有グループで、
# ここに入ると root と同等の権限を実質取得できる点は理解したうえで使う（公式も明記）。
log "docker グループにユーザーを追加"
sudo groupadd -f docker
if id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
  echo "  ${USER} は既に docker グループに所属しています"
else
  sudo usermod -aG docker "$USER"
fi

# dockerd をブート時から動かす。
sudo systemctl enable --now docker.service containerd.service

# ── 4. ログインシェルを zsh に ─────────────────────────────────────────────
# apt の /usr/bin/zsh を使う。/etc/shells に最初から載っていて chsh がそのまま通るため。
# Nix 側の zsh（~/.nix-profile/bin/zsh）は /etc/shells に無いので chsh に渡すと弾かれる。
# ~/.zshrc の中身は home-manager が生成するので、どちらの zsh でも設定内容は同じになる。
# 判定には $SHELL ではなく passwd の値を使う（$SHELL は親プロセス由来で当てにならない）。
log "ログインシェルを確認"
ZSH_PATH=/usr/bin/zsh
current_shell="$(getent passwd "$USER" | cut -d: -f7)"
if [[ "$current_shell" == "$ZSH_PATH" ]]; then
  echo "  すでに ${ZSH_PATH} です"
elif [[ ! -x "$ZSH_PATH" ]]; then
  warn "${ZSH_PATH} が見つかりません。ログインシェルの変更をスキップします"
else
  chsh -s "$ZSH_PATH"
fi

# ── 5. home-manager を適用 ─────────────────────────────────────────────────
log "home-manager を適用: ${HM_FLAKE_REF}"
if command -v home-manager >/dev/null 2>&1; then
  home-manager switch --flake "${HM_FLAKE_REF}"
else
  # 初回は home-manager CLI がまだ無い。ここで `nix run home-manager` を叩くと
  # home-manager 側の nixpkgs（nixos-unstable）まで引かれて余計なダウンロードが増え、
  # このリポジトリが flake.lock で固定している版ともズレる。
  # 代わりに自前の flake から activationPackage を build して $out/activate を直接叩く。
  # これは standalone home-manager の正規のブートストラップ経路で、Nix プロファイルの
  # 更新まで activate 側が行う。
  #
  # HOME_MANAGER_BACKUP_EXT は `switch -b backup` と同じ意味。既にある ~/.zshrc などを
  # <名前>.backup に退避してから symlink を張る（無いと衝突して中断する）。
  log "初回のため activationPackage をビルドして直接アクティベートします"
  act="$(nix build --no-link --print-out-paths "${FLAKE_DIR}#${HM_ATTR}")"
  HOME_MANAGER_BACKUP_EXT=backup "${act}/activate"
fi

# ── 6. 非 NixOS 向け GPU ドライバ連携 ──────────────────────────────────────
# targets.genericLinux.enable = true にすると gpu.enable も既定で true になり、
# non-nixos-gpu というセットアップ用パッケージが home.packages に入る。
# これは「Nix でビルドされた OpenGL/Vulkan アプリが、ホスト（Ubuntu）側の GPU
# ドライバではなく Nix 側の Mesa を見に行けるようにする」ための仕掛けで、
# /etc/tmpfiles.d に設定を置いて /run/opengl-driver を張るため root が要る。
# Ghostty は GPU 描画なのでここを飛ばすとソフトウェアレンダリングに落ちる。
#
# home-manager のアクティベーションはこれを自動実行せず、警告を出すだけなので
# ここで代わりに叩く。冪等（毎回張り直すだけ）。
GPU_SETUP="${HOME}/.nix-profile/bin/non-nixos-gpu-setup"
if [[ -x "$GPU_SETUP" ]]; then
  log "非 NixOS 向け GPU ドライバ連携をセットアップ"
  sudo "$GPU_SETUP"
else
  warn "non-nixos-gpu-setup が見つかりません（GPU 連携は未設定）。home-manager の適用が成功したか確認してください"
fi

# NVIDIA のプロプライエタリドライバを使っている場合は、これだけでは足りない。
# ホスト側と完全に同じバージョンのドライバを Nix 側にも用意する必要があるので、
# hosts/ubuntu/default.nix の targets.genericLinux.gpu.nvidia を設定すること。
if command -v nvidia-smi >/dev/null 2>&1; then
  warn "NVIDIA ドライバを検出しました。hosts/ubuntu/default.nix の gpu.nvidia 設定が必要です（README 参照）"
  echo "  ホスト側のドライバ版: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo '取得失敗')"
fi

log "完了"
cat <<'EOS'

次にやること:
  - gh auth login                     … GitHub 認証（マシンごとに 1 回。README「GitHub 認証方式」参照）
  - ログインし直す（推奨）             … 下記の 3 つがログインし直して初めて効きます
      * docker グループ（sudo なしの docker）
      * ログインシェルの zsh
      * XDG_DATA_DIRS（GNOME のアプリ一覧に Ghostty が出る）
  - 動作確認:
      docker run --rm hello-world
      ghostty --version
      home-manager --version

以降の適用:
  home-manager switch --flake ~/dotfiles#s-tatsuya@ubuntu
EOS
