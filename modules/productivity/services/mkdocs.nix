{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

with lib;

let
  productivityLib = import ../lib.nix {
    inherit config lib pkgs;
  };
  inherit (productivityLib) cfg mkdocsConfig mkdocsEnv mkdocsIndex mkdocsRoot;
 in
{
  config = mkIf cfg.enable {
systemd.services.mkdocs-material-init = {
  description = "Initialize Material for MkDocs source tree";
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
  };
  path = [
    pkgs.coreutils
  ];
  script = ''
    set -euo pipefail

    install -d -m 0775 -o root -g productivity '${mkdocsRoot}/docs'
    install -d -m 0775 -o root -g productivity '${mkdocsRoot}/site'

    if [ ! -f '${mkdocsRoot}/mkdocs.yml' ]; then
      install -m 0664 -o root -g productivity ${mkdocsConfig} '${mkdocsRoot}/mkdocs.yml'
    fi

    if [ ! -f '${mkdocsRoot}/docs/index.md' ]; then
      install -m 0664 -o root -g productivity ${mkdocsIndex} '${mkdocsRoot}/docs/index.md'
    fi
  '';
};

systemd.services.mkdocs-material-build = {
  description = "Build Material for MkDocs static site";
  wantedBy = [ "multi-user.target" ];
  requires = [ "mkdocs-material-init.service" ];
  after = [ "mkdocs-material-init.service" ];
  path = [
    mkdocsEnv
  ];
  serviceConfig = {
    Type = "oneshot";
    User = "root";
    Group = "productivity";
  };
  script = ''
    set -euo pipefail

    mkdocs build \
      --clean \
      --config-file '${mkdocsRoot}/mkdocs.yml' \
      --site-dir '${mkdocsRoot}/site'

    chgrp -R productivity '${mkdocsRoot}/site'
    chmod -R g=u '${mkdocsRoot}/site'
  '';
};

systemd.paths.mkdocs-material-build = {
  description = "Rebuild Material for MkDocs when source changes";
  wantedBy = [ "multi-user.target" ];
  pathConfig = {
    PathChanged = [
      "${mkdocsRoot}/docs"
      "${mkdocsRoot}/mkdocs.yml"
    ];
    Unit = "mkdocs-material-build.service";
  };
};
  };
}
