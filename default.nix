{ pkgs, ... }:
pkgs.writeShellApplication
{
  name = "rbld";
  runtimeInputs = with pkgs;
  [
    jq
    nix-output-monitor # aka nom
    nixos-rebuild
    home-manager
    git
  ];

  text =
  ''
    set -e # Exit early if any commands fail
    CONFIG_DIRECTORY=/etc/nixos
    cd $CONFIG_DIRECTORY

    run_rbld() # Add any new files to git and pipe command output into `nom`
    {
      git add -AN &&
      "$@" |&
      nom || return
    }

    get_time() # Get flake.lock revisions times for the inputs we care about
    {
      jq -r '([.nodes["home-manager", "nixpkgs", "nixpkgs-unstable"].locked.lastModified] | add)' flake.lock
    }

    case "$1" in
      -n)
        run_rbld nixos-rebuild switch --use-remote-sudo --fast
        ;;
      -h)
        run_rbld home-manager switch -b backup --flake $CONFIG_DIRECTORY
        ;;
      -f)
        OLD_TIME=$(get_time)
        nix flake update
        NEW_TIME=$(get_time)

        echo "Old time: $OLD_TIME" # Logs for debugging
        echo "New time: $NEW_TIME"

        if [[ $NEW_TIME == "$OLD_TIME" ]]; then
          echo "No important updates to flake.lock, so skipping rebuild"
          exit 0
      fi

        rbld -n # If we fail here, we exit early and don't commit something broken
        git commit -q -m "flake: update flake.lock" flake.lock
        git push
        ;;
      *)
        cat <<EOF
        ${"\n" + ''
        Usage: rbld (-n|-h|-f|)
        Options:
        -n          Rebuild both the system configuration and the home-manager configuration
        -h          Rebuild *only* the home-manager configuration
        -f          Update the flake.lock and rebuild if necessary
      ''}EOF
        ;;
    esac
  '';
}