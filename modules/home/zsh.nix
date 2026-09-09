{ pkgs, ... }:
{
  # ~/.zshrc は home-manager が生成するので、これが両 OS 共通の zsh 設定の実体になる。
  # macOS では nix-darwin 側（modules/darwin/nix.nix）でも zsh を有効化しているが、
  # home-manager 側でも有効化すると direnv などのフックが確実に挿入される。
  # Ubuntu ではログインシェルの変更（chsh）だけが Nix の管轄外で、
  # scripts/ubuntu-bootstrap.sh がやる。
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    # ~/.zshrc に `alias <name>='<value>'` として展開される。
    # 値は zsh の文字列としてそのまま渡るので、クォートは Nix 側で意識しない。
    shellAliases = {
      # このリポジトリの適用・確認
      # 末尾スペースがないと `drs` のような別名を続けて書いたとき展開されないが、
      # ここは単独で使う想定なので不要。
      claude = "claude --permission-mode auto";
    };

    # zsh 標準の補完は大文字小文字を区別するため、`cd doc<TAB>` では
    # `Documents` が候補に出ない。小文字入力を大文字にもマッチさせる。
    # fzf-tab は補完システムが生成した候補を表示するだけなので、
    # マッチ規則はこちらの zstyle で調整する必要がある。
    initContent = ''
      # m:{a-z}={A-Za-z} … 入力した小文字は大小どちらにもマッチする。
      # 大文字を明示的に入力した場合は大文字のみにマッチするので、
      # 完全な case-insensitive よりも候補が絞り込みやすい。
      zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

      # 素の zsh は前方削除キー（Mac の fn + delete、フルサイズなら Delete）を
      # どのキーマップにも割り当てていない。端末が送る CSI 3~ が未定義のままだと
      # 途中まで読み捨てられ、末尾の `~` だけが行に挿入される。
      # terminfo の kdch1 が引ければそれを使い（TERM ごとの差異を吸収できる）、
      # zsh/terminfo が無い・値が空のときだけ xterm 系のリテラルへ倒す。
      # `''${...}` は Nix の文字列補間を抑止して zsh にそのまま渡すためのエスケープ。
      zmodload zsh/terminfo 2>/dev/null
      if [[ -n ''${terminfo[kdch1]} ]]; then
        bindkey -- "''${terminfo[kdch1]}" delete-char
      else
        bindkey -- '^[[3~' delete-char
      fi
    '';

    # Plugin 関連の設定を追加
    plugins = [
      {
        # 補完候補を fzf で選ぶ。compinit の後に読み込まれる必要があるが、
        # home-manager は plugins を compinit の後に source するので条件を満たす。
        name = "fzf-tab";
        src = pkgs.zsh-fzf-tab;
        file = "share/fzf-tab/fzf-tab.plugin.zsh";
      }
    ];
  };

  # サブコマンドの自動補完。
  # plugins で入れると補完関数のあるディレクトリが fpath に入るのが
  # compinit より後になって効かないため、パッケージとして入れる。
  # nix パッケージは share/zsh/site-functions に置かれ、こちらは
  # home-manager が compinit より前に fpath へ追加してくれる。
  home.packages = [ pkgs.zsh-completions ];

  home.sessionPath = [
    "$HOME/.local/bin"
  ];
}
