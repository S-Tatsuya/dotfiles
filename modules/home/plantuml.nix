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
    # enable = false（Linux は Install を消す）にすればよい。
    #
    # 常駐の仕組みは OS ごとに別物なので、同じプロセスを 2 通りに書く。
    # macOS: launchd。home-manager の launchd.enable は非 darwin では既定 false で、
    #   agents を定義しても plist が生成されず黙って無視される。
    # Linux: systemd --user。Ubuntu は systemd が PID 1 なのでそのまま使える。
    #   home-manager がアクティベーション時に daemon-reload と起動まで面倒を見る。
    launchd.agents.plantuml-server = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
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

    systemd.user.services.plantuml-server = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      Unit = {
        Description = "PlantUML built-in HTTP server (for mpls markdown preview)";
        # ローカル待ち受けだけなのでネットワーク到達性は要らないが、
        # 起動順を安定させるために network.target の後にしておく。
        After = [ "network.target" ];
      };
      Service = {
        ExecStart = "${pkgs.plantuml}/bin/plantuml --http-server:${toString config.local.plantuml.port}";
        # KeepAlive = true 相当。異常終了したら開け直す。
        Restart = "on-failure";
        RestartSec = 5;
      };
      # ログイン時に自動起動する（launchd の RunAtLoad = true 相当）。
      # ログは journald に入るので `journalctl --user -u plantuml-server` で読む。
      Install.WantedBy = [ "default.target" ];
    };
  };
}
