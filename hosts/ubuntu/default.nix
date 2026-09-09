{ ... }:
{
  # Ubuntu 26.04 デスクトップ（非 NixOS）固有の設定を置く場所。
  #
  # 共通のユーザー設定は home/s-tatsuya.nix、非 NixOS Linux で共通に必要になる
  # 受け皿（targets.genericLinux など）は modules/home/linux.nix にある。
  # ここには「このマシンだけ」の設定を足していく。
  #
  # システム層（Nix 本体・Docker・ログインシェル・apt パッケージ）は
  # standalone home-manager の管轄外なので scripts/ubuntu-bootstrap.sh が扱う。
  # 例えば nix.settings をここに書いても ~/.config/nix/nix.conf に出るだけで、
  # ビルドを実際に行う daemon（/etc/nix/nix.conf）には効かない点に注意。

  # ── NVIDIA のプロプライエタリドライバを使っている場合 ──────────────────
  # GPU はマシン固有なので設定はここに置く。
  #
  # targets.genericLinux.enable = true にすると gpu.enable も既定で true になり、
  # Nix 側の Mesa が /run/opengl-driver 経由で使われるようになる（Ghostty の
  # GPU 描画はこれに乗る）。Mesa（Intel / AMD）ならこれだけで完結する。
  #
  # NVIDIA のプロプライエタリドライバの場合は、Nix 側に「ホストのカーネル
  # モジュールと完全に同じバージョン」のユーザー空間ライブラリを用意しないと
  # 動かない。version は `nvidia-smi --query-gpu=driver_version --format=csv,noheader`、
  # sha256 は下記コマンドで取得して、コメントを外して埋める。
  #
  #   nix store prefetch-file \
  #     https://download.nvidia.com/XFree86/Linux-x86_64/<VERSION>/NVIDIA-Linux-x86_64-<VERSION>.run
  #
  # ホスト側のドライバを更新したらここも追従させること（ズレると GL が動かない）。
  #
  # targets.genericLinux.gpu.nvidia = {
  #   enable = true;
  #   version = "580.95.05";
  #   sha256 = "sha256-...";
  # };
}
