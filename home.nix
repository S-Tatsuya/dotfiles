{
  home = rec {
    username = "s-tatsuya0123";
    homeDirectory = "/home/${username}";
    stateVersion = "25.05";
  };
  programs.home-manager.enable = true;
}