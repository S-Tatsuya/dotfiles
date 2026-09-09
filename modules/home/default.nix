{ ... }:
{
  imports = [
    # プラットフォーム差分の受け皿。中身は自身で isLinux / isDarwin を見て
    # 無効化するので、macOS / Ubuntu どちらの構成からも無条件に import してよい。
    ./linux.nix

    # 機能別モジュール
    ./packages.nix
    ./git.nix
    ./gh.nix
    ./zsh.nix
    ./starship.nix
    ./fzf.nix
    ./bat.nix
    ./helix.nix
    ./plantuml.nix
    ./ghostty.nix
  ];
}
