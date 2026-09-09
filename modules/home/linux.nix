{ lib, pkgs, ... }:
lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
  # 非 NixOS の Linux（= Ubuntu）で standalone home-manager を動かすための受け皿。
  #
  # NixOS なら OS 側がやってくれることを home-manager に肩代わりさせる:
  #   - /etc/profile 由来の PATH や XDG_DATA_DIRS を壊さずに Nix プロファイルを足す
  #   - LOCALE_ARCHIVE を glibcLocales に向ける（無いと Nix 製のコマンドが
  #     "locale not supported" を出したり日本語が化けたりする）
  #   - Nix プロファイルの .desktop / アイコン / man を探索パスに載せる
  targets.genericLinux.enable = true;

  # XDG のベースディレクトリを明示する。Linux では既定値と同じだが、
  # XDG_*_HOME をセッション変数として書き出すので、これを見て挙動を変える
  # ツール（helix / ghostty の設定探索など）が Ubuntu 側の設定と食い違わない。
  xdg.enable = true;

  # GNOME のアプリ一覧（app grid）はシェルの rc ファイルではなく systemd --user の
  # 環境変数を見て .desktop を探すが、その面倒は home-manager が既に見ている:
  # 上の 2 つを有効にすると ~/.config/environment.d/10-home-manager.conf が生成され、
  # XDG_DATA_DIRS に ~/.nix-profile/share が（Ubuntu の /usr/share/ubuntu や
  # /var/lib/snapd/desktop を保ったまま）差し込まれる。ここに自前で XDG_DATA_DIRS を
  # 書き足すと同じファイルの後ろに追記されて元の行を上書きしてしまうので、書かないこと。
  # 反映はログインし直しが必要（systemd --user は起動時にしか読まない）。

  # Nix のインストーラは /etc/zsh/zshrc などを書き換えて daemon プロファイルを
  # PATH に載せるが、zsh を Nix の後に入れた場合などは zsh 側だけ漏れる。
  # 漏れているときだけ自前で読み込む（NIX_PROFILES が既にあれば何もしない）。
  # mkBefore で zsh.nix の設定より前に置き、以降の行で nix / home-manager が使える状態にする。
  programs.zsh.initContent = lib.mkBefore ''
    if [[ -z ''${NIX_PROFILES:-} && -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
      . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    fi
  '';
}
