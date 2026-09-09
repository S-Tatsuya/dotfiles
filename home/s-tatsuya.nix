{ pkgs, username, ... }:
{
  imports = [
    ../modules/home
  ];

  home.username = username;

  # ホームディレクトリの位置は OS で違う。macOS は /Users、Linux は /home。
  # ホストごとの分岐をここ一箇所に閉じ込めておけば、hosts/* は空のままで済む。
  home.homeDirectory =
    if pkgs.stdenv.hostPlatform.isDarwin then "/Users/${username}" else "/home/${username}";

  # 初回導入時のバージョン。基本的に変更しない。
  home.stateVersion = "26.05";

  # home-manager 自身を管理（CLI も利用可能になる）
  #
  # macOS では nix-darwin のモジュールとして動くので darwin-rebuild が面倒を見るが、
  # Ubuntu では standalone なのでこの CLI 自体が適用手段になる。
  programs.home-manager.enable = true;
}
