{
  description = "S-Tatsuya's Nix Configuration";

  inputs = {
    # macOS 用の nixpkgs。nixpkgs-*-darwin は Darwin のジョブセットが通った
    # コミットだけが進むチャンネルなので、Darwin のバイナリキャッシュが埋まっている。
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    # Linux 用の nixpkgs。上の darwin チャンネルは Linux のビルドが検証されておらず、
    # そのコミットの Linux 成果物がキャッシュに載っている保証がない（ソースビルドに
    # 落ちて LLVM などを引きかねない）。同じ 26.05 系列の NixOS チャンネルを別 input で持つ。
    nixpkgs-linux.url = "github:NixOS/nixpkgs/nixos-26.05";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # herdr（AI コーディングエージェント用のターミナルワークスペース管理）
    # nixpkgs は follows させない: 向こうは nixos-unstable + rust-overlay 前提のため
    herdr.url = "github:herdrdev/herdr";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
  };

  outputs = inputs@{ self, nixpkgs, nixpkgs-linux, nix-darwin, home-manager, herdr, nix-homebrew, homebrew-core, homebrew-cask }:
  let
    username = "s-tatsuya";

    # M1/M2/M3 Mac は aarch64-darwin
    darwinSystem = "aarch64-darwin";
    # 一般的なデスクトップ PC は x86_64-linux（ARM 機なら aarch64-linux に変える）
    linuxSystem = "x86_64-linux";
  in
  {
    # ── macOS（nix-darwin + home-manager 統合方式）─────────────────────────────
    # 適用: sudo darwin-rebuild switch --flake ~/dotfiles#mac
    darwinConfigurations."mac" = nix-darwin.lib.darwinSystem {
      system = darwinSystem;
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

        nix-homebrew.darwinModules.nix-homebrew
        {
          nix-homebrew = {
            enable = true;
            enableRosetta = true;
            user = username;
            taps = {
              "homebrew/homebrew-core" = homebrew-core;
              "homebrew/homebrew-cask" = homebrew-cask;
            };
            mutableTaps = false;
          };
        }
      ];
    };

    # ── Ubuntu（standalone home-manager）───────────────────────────────────────
    # Ubuntu は NixOS ではないので、システム層（nix-darwin / NixOS モジュールに
    # 相当するもの）は Nix では管理できない。ユーザー環境だけを home-manager が持ち、
    # OS 側の下ごしらえ（Nix 本体・Docker・ログインシェル）は scripts/ubuntu-bootstrap.sh が行う。
    #
    # 適用: home-manager switch --flake ~/dotfiles#s-tatsuya@ubuntu
    homeConfigurations."${username}@ubuntu" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs-linux.legacyPackages.${linuxSystem};
      extraSpecialArgs = { inherit inputs username; };
      modules = [
        ./home/${username}.nix
        ./hosts/ubuntu/default.nix
      ];
    };
  };
}
