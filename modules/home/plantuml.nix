{ config, lib, pkgs, ... }:
{
  # ポートは helix.nix の mpls 側（--plantuml-server）と対で使うので、
  # 両方にリテラルを書かずオプションとして公開する。
  options.local.plantuml.port = lib.mkOption {
    type = lib.types.port;
    default = 45123;
    description = "PlantUML 内蔵 HTTP サーバが待ち受けるポート。";
  };

  config = {
    # nixpkgs の plantuml は JDK と graphviz を同梱した wrapper なので、
    # これ 1 つで CLI もサーバも動く（GRAPHVIZ_DOT も設定済み）。
    home.packages = [ pkgs.plantuml ];

    # PlantUML のレンダリングサーバ。nixpkgs には plantuml-server もあるが、
    # あちらは war だけを吐くパッケージで、別に jetty を用意してデプロイする
    # 必要がある（NixOS モジュールはそれをやっているが darwin 版はない）。
    # plantuml.jar 内蔵の --http-server なら同じレンダリング API を単体で出せるので、
    # jetty も Docker も Apple container も要らない。
    #
    # エンドポイントは /plantuml/svg/<encoded> と /svg/<encoded> の両方で応答する。
    # 前者が mpls の既定パス（--plantuml-path の既定値 "plantuml"）と一致するので、
    # mpls 側はホストの差し替えだけで済む。
    #
    # 常駐 JVM なので待機中もメモリを数百 MB 使う。UML を書かない期間は
    # enable = false にすればよい。
    #
    # launchd は darwin 専用。home-manager の launchd.enable は非 darwin で
    # 既定 false になり、その場合 agents を定義しても plist は生成されず無視される。
    # Linux で常駐させるなら systemd.user.services に同じことを書く必要がある。
    launchd.agents.plantuml-server = {
      enable = true;
      config = {
        ProgramArguments = [
          "${pkgs.plantuml}/bin/plantuml"
          "--http-server:${toString config.local.plantuml.port}"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/plantuml-server.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/plantuml-server.log";
      };
    };
  };
}
